use std::time::Duration;

use axum::{Json, extract::State};
use serde_json::{Value, json};

use crate::{
    api::{dto::Meta, routes::current_year},
    app_state::AppState,
    error::ApiError,
    providers::{f1_schedule, http},
    storage::sqlite::Database,
};

pub async fn get(State(state): State<AppState>) -> Result<Json<Value>, ApiError> {
    let year = current_year(&state).await? + 1;
    let source_url = f1_schedule::source_url(year);
    let snapshot = state.database.next_season_schedule(year).await?;
    let mut meta = Meta::empty();
    let mut data = json!({ "year": year, "sourceUrl": source_url, "events": [] });
    if let Some(snapshot) = snapshot {
        meta = Meta::from_cache(
            Some("formula1".into()),
            Some(snapshot.checked_at),
            snapshot.revision,
            false,
        );
        data["events"] = snapshot.events;
        data["updatedAt"] = snapshot.updated_at.into();
    }
    Ok(Json(json!({ "data": data, "meta": meta })))
}

pub async fn run(state: AppState) {
    let client = match http::shared_client(&state.config.providers.user_agent) {
        Ok(client) => client,
        Err(error) => {
            tracing::warn!(%error, "failed to initialize official F1 schedule provider");
            return;
        }
    };
    let interval = Duration::from_secs(state.config.scheduler.calendar_interval_seconds.max(60));
    loop {
        let result = async {
            let year = current_year(&state).await? + 1;
            refresh(
                &state.database,
                &client,
                &f1_schedule::source_url(year),
                year,
            )
            .await
        }
        .await;
        let next_check = match result {
            Ok(()) => interval,
            Err(error) => {
                tracing::warn!(%error, "official F1 schedule refresh failed");
                interval.min(Duration::from_secs(15 * 60))
            }
        };
        tokio::time::sleep(next_check).await;
    }
}

async fn refresh(
    database: &Database,
    client: &reqwest::Client,
    url: &str,
    year: i64,
) -> anyhow::Result<()> {
    let events = f1_schedule::fetch(client, url, year).await?;
    let now = database.utc_now().await?;
    database
        .save_next_season_schedule(year, serde_json::to_string(&events)?, now)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use axum::{Router, routing::get};

    use super::*;
    use crate::providers::f1_schedule::tests::calendar;

    #[tokio::test]
    async fn refresh_revisions_change_only_for_valid_schedule_changes() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("schedule.sqlite");
        let database = Database::open(&db_path).await.unwrap();
        database.migrate().await.unwrap();
        let fixture = Router::new()
            .route("/published", get(|| async { calendar("12 - 14 Mar") }))
            .route("/changed", get(|| async { calendar("19 - 21 Mar") }))
            .route("/invalid", get(|| async { "<html>Temporary error</html>" }));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async { axum::serve(listener, fixture).await.unwrap() });
        let client = reqwest::Client::new();

        for (path, revision, first_date) in [
            ("published", 1, "2027-03-12"),
            ("published", 1, "2027-03-12"),
            ("changed", 2, "2027-03-19"),
            ("invalid", 2, "2027-03-19"),
            ("missing", 2, "2027-03-19"),
        ] {
            let result = refresh(&database, &client, &format!("{url}/{path}"), 2027).await;
            assert_eq!(result.is_ok(), matches!(path, "published" | "changed"));
            let snapshot = database.next_season_schedule(2027).await.unwrap().unwrap();
            assert_eq!(snapshot.revision, revision);
            assert_eq!(snapshot.events[0]["startDate"], first_date);
        }
        drop(database);
        let reopened = Database::open(&db_path).await.unwrap();
        let persisted = reopened.next_season_schedule(2027).await.unwrap().unwrap();
        assert_eq!(persisted.revision, 2);
        assert!(reopened.next_season_schedule(2028).await.unwrap().is_none());
        server.abort();
    }
}
