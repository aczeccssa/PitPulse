use std::time::Duration;

use crate::{
    api::{dto::Meta, routes::current_year},
    app_state::AppState,
    domain::{
        calendar::{Meeting, MeetingStatus},
        country::country_code,
    },
    error::StorageError,
    providers::{f1_schedule, http},
    storage::sqlite::Database,
};

const SOURCE: &str = "formula1";

pub async fn calendar(
    database: &Database,
    season: i64,
) -> Result<Option<(Vec<Meeting>, Meta)>, StorageError> {
    let Some(snapshot) = database.next_season_schedule(season).await? else {
        return Ok(None);
    };
    let meetings = snapshot
        .events
        .into_iter()
        .map(|event| {
            let country = match event.id.as_str() {
                "miami" | "las-vegas" => "United States",
                "united-arab-emirates" => "United Arab Emirates",
                _ => &event.location,
            }
            .to_owned();
            let flag = match country.as_str() {
                "Portugal" => Some("PT".into()),
                "Türkiye" => Some("TR".into()),
                _ => country_code(&country),
            };
            Meeting {
                // Venue ids survive reordering. They cannot collide with Jolpica round ids.
                id: format!("{season}:formula1:{}", event.id),
                season,
                round: event.round.map(|round| round as i64),
                name: event.name,
                country,
                country_code: flag,
                location: event.location,
                start_date: format!("{}T00:00:00Z", event.start_date),
                end_date: format!("{}T23:59:59Z", event.end_date),
                status: MeetingStatus::Scheduled,
                sessions: Vec::new(),
                circuit: super::circuits::published_venue(&event.id, event.track.as_deref()),
                jolpica_round_id: None,
                source: Some(SOURCE.into()),
                fetched_at: Some(snapshot.checked_at.clone()),
                source_updated_at: None,
                revision: i64::try_from(snapshot.revision).ok(),
            }
        })
        .collect();
    let meta = Meta::from_cache(
        Some(SOURCE.into()),
        Some(snapshot.checked_at),
        snapshot.revision,
        snapshot.stale,
    );
    Ok(Some((meetings, meta)))
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
    use crate::providers::f1_schedule::tests::calendar as calendar_html;

    #[tokio::test]
    async fn refresh_revisions_change_only_for_valid_schedule_changes() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("schedule.sqlite");
        let database = Database::open(&db_path).await.unwrap();
        database.migrate().await.unwrap();
        let fixture = Router::new()
            .route("/published", get(|| async { calendar_html("12 - 14 Mar") }))
            .route("/changed", get(|| async { calendar_html("19 - 21 Mar") }))
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
            let (meetings, meta) = calendar(&database, 2027).await.unwrap().unwrap();
            assert_eq!(meta.revision, revision);
            assert_eq!(meetings[0].start_date, format!("{first_date}T00:00:00Z"));
            assert!(meetings[0].sessions.is_empty());
        }
        drop(database);
        let reopened = Database::open(&db_path).await.unwrap();
        let persisted = reopened.next_season_schedule(2027).await.unwrap().unwrap();
        assert_eq!(persisted.revision, 2);
        assert!(reopened.next_season_schedule(2028).await.unwrap().is_none());
        server.abort();
    }
}
