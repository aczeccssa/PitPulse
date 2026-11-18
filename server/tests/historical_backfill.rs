use pitpulse_server::{
    domain::calendar::SessionType,
    providers::{jolpica::decode_alpha_schedule, results::IdentityMaps},
    storage::sqlite::Database,
};
use serde_json::{Value, json};

#[tokio::test]
async fn recorded_historical_weekends_keep_session_numbers_and_stable_revisions() {
    let temp = tempfile::tempdir().unwrap();
    let db = Database::open(&temp.path().join("history.sqlite"))
        .await
        .unwrap();
    db.migrate().await.unwrap();
    for (year, calendar, qualifying, constructor, number) in [
        (
            2021,
            include_str!("fixtures/jolpica-2021-calendar.json"),
            include_str!("fixtures/jolpica-2021-qualifying.json"),
            "alphatauri",
            "33",
        ),
        (
            2024,
            include_str!("fixtures/jolpica-2024-calendar.json"),
            include_str!("fixtures/jolpica-2024-qualifying.json"),
            "rb",
            "1",
        ),
    ] {
        let meetings = decode_alpha_schedule(&serde_json::from_str(calendar).unwrap()).unwrap();
        assert_eq!(meetings[0].season, year);
        let session = meetings[0]
            .sessions
            .iter()
            .find(|s| s.session_type == SessionType::Qualifying)
            .unwrap();
        let ids = IdentityMaps::from_ergast(&[], &[json!({"constructorId":constructor})]);
        assert_eq!(ids.constructor_for_name("Racing Bulls"), Some(constructor));
        let payload: Value = serde_json::from_str(qualifying).unwrap();
        let (rows, quality) = ids.decode_alpha_results(
            &payload,
            &session.id,
            session.session_type,
            &[],
            "2026-11-18T00:00:00Z",
        );
        let pole = rows.iter().find(|r| r.position == Some(1)).unwrap();
        assert_eq!(pole.driver_number.as_deref(), Some(number));
        assert!(pole.q3.is_some());
        for _ in 0..2 {
            db.replace_calendar(&meetings, "2026-11-18T00:00:00Z")
                .await
                .unwrap();
            assert_eq!(
                db.replace_session_results(rows.clone(), quality.as_str())
                    .await
                    .unwrap(),
                1
            );
            assert_eq!(db.session_results(&session.id).await.unwrap().0.len(), 20);
        }
    }
}

#[test]
fn historical_branding_and_roster_numbers_resolve_to_season_identities() {
    for constructor in ["alfa", "sauber", "audi"] {
        let ids = IdentityMaps::from_ergast(
            &[
                json!({"driverId":"max_verstappen","code":"VER","permanentNumber":"3"}),
                json!({"driverId":"norris","code":"NOR","permanentNumber":"1"}),
            ],
            &[json!({"constructorId":constructor})],
        );
        assert_eq!(ids.constructor_for_name("Kick Sauber"), Some(constructor));
        assert_eq!(
            ids.driver_for_roster(&json!({"driver_number":1,"name_acronym":"VER"})),
            Some("max_verstappen")
        );
    }
}
