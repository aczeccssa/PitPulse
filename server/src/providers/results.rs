use std::collections::{BTreeSet, HashMap};

use serde_json::Value;

use crate::domain::{
    calendar::SessionType,
    quality::{DataQuality, ProviderAvailability},
    results::SessionResult,
    standings::{ConstructorStanding, DriverStanding},
};

#[derive(Default, Clone)]
pub struct IdentityMaps {
    drivers_by_wikipedia: HashMap<String, String>,
    drivers_by_number: HashMap<i64, String>,
    constructors_by_wikipedia: HashMap<String, String>,
    constructors_by_name: HashMap<String, String>,
}

impl IdentityMaps {
    pub fn from_ergast(drivers: &[Value], constructors: &[Value]) -> Self {
        let mut maps = Self::default();
        for row in drivers {
            let Some(id) = row.get("driverId").and_then(Value::as_str) else {
                continue;
            };
            if let Some(url) = row.get("url").and_then(Value::as_str) {
                maps.drivers_by_wikipedia
                    .insert(normalize_url(url), id.to_string());
            }
            if let Some(number) = row
                .get("permanentNumber")
                .and_then(Value::as_str)
                .and_then(|value| value.parse().ok())
            {
                maps.drivers_by_number.insert(number, id.to_string());
            }
        }
        for row in constructors {
            let Some(id) = row.get("constructorId").and_then(Value::as_str) else {
                continue;
            };
            if let Some(url) = row.get("url").and_then(Value::as_str) {
                maps.constructors_by_wikipedia
                    .insert(normalize_url(url), id.to_string());
            }
            if let Some(name) = row.get("name").and_then(Value::as_str) {
                maps.constructors_by_name
                    .insert(normalize_name(name), id.to_string());
            }
        }
        maps
    }

    pub fn driver_for_wikipedia(&self, url: &str) -> Option<&str> {
        self.drivers_by_wikipedia
            .get(&normalize_url(url))
            .map(String::as_str)
    }

    pub fn driver_for_number(&self, number: i64) -> Option<&str> {
        self.drivers_by_number.get(&number).map(String::as_str)
    }

    pub fn constructor_for_wikipedia(&self, url: &str) -> Option<&str> {
        self.constructors_by_wikipedia
            .get(&normalize_url(url))
            .map(String::as_str)
    }

    pub fn constructor_for_name(&self, name: &str) -> Option<&str> {
        self.constructors_by_name
            .get(&normalize_name(name))
            .map(String::as_str)
    }

    pub fn decode_alpha_results(
        &self,
        payload: &Value,
        session_id: &str,
        session_type: SessionType,
        expected_drivers: &[Value],
        fetched_at: &str,
    ) -> (Vec<SessionResult>, DataQuality) {
        let rows = payload
            .pointer("/data/results")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let source_updated_at = payload
            .pointer("/metadata/timestamp")
            .and_then(Value::as_str)
            .map(str::to_string);
        let expected_numbers = driver_numbers(expected_drivers);
        let expected_ids = expected_numbers
            .iter()
            .filter_map(|number| self.drivers_by_number.get(number).cloned())
            .collect::<BTreeSet<_>>();
        let mut complete = !rows.is_empty()
            && rows.len() == expected_numbers.len()
            && expected_numbers.len() == expected_drivers.len()
            && expected_ids.len() == expected_numbers.len();
        let mut results = rows
            .iter()
            .map(|row| {
                let driver = &row["driver"];
                let team = &row["team"];
                let raw_driver_id = driver["id"].as_str().unwrap_or("unknown");
                let raw_constructor_id = team["id"].as_str().unwrap_or("unknown");
                let driver_id = driver["wikipedia"]
                    .as_str()
                    .and_then(|url| self.drivers_by_wikipedia.get(&normalize_url(url)))
                    .cloned();
                let constructor_id = team["wikipedia"]
                    .as_str()
                    .and_then(|url| self.constructors_by_wikipedia.get(&normalize_url(url)))
                    .cloned();
                if driver_id.is_none() || constructor_id.is_none() {
                    complete = false;
                }
                let position_text = row["position_text"].as_str();
                let position = crate::providers::jolpica::result_position(row);
                let status = row["status"].as_str().unwrap_or_default();
                let normalized_status = status.trim().to_ascii_uppercase();
                let hint = if normalized_status.is_empty() {
                    position_text
                        .unwrap_or_default()
                        .trim()
                        .to_ascii_uppercase()
                } else {
                    normalized_status.clone()
                };
                let has_classification_evidence = position.is_some()
                    || !normalized_status.is_empty()
                    || row["is_classified"].as_bool().is_some()
                    || position_text.is_some_and(|value| !value.trim().is_empty());
                let classification = match hint.as_str() {
                    "DSQ" | "DISQUALIFIED" | "D" => "DSQ".to_string(),
                    "DNS" | "NOT STARTED" | "DID NOT START" => "DNS".to_string(),
                    "DNF" | "RETIRED" | "ACCIDENT" | "ENGINE" | "DID NOT FINISH" | "R" => {
                        "DNF".to_string()
                    }
                    "NC" => "NC".to_string(),
                    _ if position.is_some() || row["is_classified"].as_bool() == Some(true) => {
                        "classified".to_string()
                    }
                    _ if row["is_classified"].as_bool() == Some(false) => "DNF".to_string(),
                    _ if !hint.is_empty() => {
                        if normalized_status.is_empty() {
                            position_text.unwrap_or_default().to_string()
                        } else {
                            status.to_string()
                        }
                    }
                    _ => "NC".to_string(),
                };
                if !has_classification_evidence
                    || (position.is_none()
                        && !matches!(classification.as_str(), "DSQ" | "DNS" | "DNF" | "NC"))
                {
                    complete = false;
                }
                let components = &row["components"];
                let component = |key: &str| {
                    components[key]["time"]
                        .as_str()
                        .or_else(|| components[key].as_str())
                        .map(str::to_string)
                };
                let time = row["time"].as_str().map(str::to_string);
                let best_lap = row["fastest_lap"]
                    .as_str()
                    .or_else(|| row["best_lap"].as_str())
                    .map(str::to_string)
                    .or_else(|| component("FL"));
                let race_time = matches!(session_type, SessionType::Race | SessionType::Sprint)
                    .then(|| time.clone())
                    .flatten();
                SessionResult {
                    session_id: session_id.to_string(),
                    position,
                    classification,
                    driver_id: driver_id
                        .unwrap_or_else(|| format!("jolpica-alpha:{raw_driver_id}")),
                    driver_name: format!(
                        "{} {}",
                        driver["given_name"].as_str().unwrap_or_default(),
                        driver["family_name"].as_str().unwrap_or_default()
                    )
                    .trim()
                    .to_string(),
                    constructor_id: constructor_id
                        .unwrap_or_else(|| format!("jolpica-alpha:{raw_constructor_id}")),
                    team: team["name"].as_str().unwrap_or_default().to_string(),
                    time,
                    best_lap,
                    q1: component("Q1"),
                    q2: component("Q2"),
                    q3: component("Q3"),
                    race_time,
                    gap: row["gap"].as_str().map(str::to_string),
                    laps: row["laps"].as_i64(),
                    points: row["points"].as_f64(),
                    source: "jolpica-alpha".to_string(),
                    source_updated_at: source_updated_at.clone(),
                    fetched_at: fetched_at.to_string(),
                    revision: 1,
                    quality: "partial".to_string(),
                }
            })
            .collect::<Vec<_>>();
        let actual_ids = results
            .iter()
            .filter(|row| !row.driver_id.contains(':'))
            .map(|row| row.driver_id.clone())
            .collect::<BTreeSet<_>>();
        complete &= actual_ids == expected_ids && actual_ids.len() == results.len();
        let quality = if complete {
            DataQuality::Provisional
        } else {
            DataQuality::Partial
        };
        for row in &mut results {
            row.quality = quality.as_str().to_string();
        }
        (results, quality)
    }

    pub fn decode_openf1_results(
        &self,
        rows: &[Value],
        drivers: &[Value],
        session_id: &str,
        session_type: SessionType,
        expected_drivers: usize,
        fetched_at: &str,
    ) -> (Vec<SessionResult>, DataQuality) {
        let roster = drivers
            .iter()
            .filter_map(|row| {
                let number = row.get("driver_number")?.as_i64()?;
                Some((number, row))
            })
            .collect::<HashMap<_, _>>();
        let expected_numbers = driver_numbers(drivers);
        let mut complete = !rows.is_empty()
            && rows.len() == expected_numbers.len()
            && expected_numbers.len() == expected_drivers
            && expected_numbers.len() == drivers.len();
        let mut results = rows
            .iter()
            .map(|row| {
                let number = row["driver_number"].as_i64();
                let roster_driver = number.and_then(|number| roster.get(&number).copied());
                let driver_id = number
                    .and_then(|number| self.drivers_by_number.get(&number))
                    .cloned();
                let team_name = roster_driver
                    .and_then(|driver| driver["team_name"].as_str())
                    .unwrap_or_default();
                let constructor_id = self
                    .constructors_by_name
                    .get(&normalize_name(team_name))
                    .cloned();
                if driver_id.is_none() || constructor_id.is_none() || roster_driver.is_none() {
                    complete = false;
                }
                let classification = if row["dsq"] == true {
                    "DSQ"
                } else if row["dns"] == true {
                    "DNS"
                } else if row["dnf"] == true {
                    "DNF"
                } else if row["position"].as_i64().is_some() {
                    "classified"
                } else {
                    "NC"
                };
                let position = row["position"].as_i64().filter(|value| *value > 0);
                if position.is_none()
                    && row["dsq"] != true
                    && row["dns"] != true
                    && row["dnf"] != true
                {
                    complete = false;
                }
                let seconds = |field: &str| {
                    row[field]
                        .as_f64()
                        .map(|value| value.to_string())
                        .or_else(|| row[field].as_str().map(str::to_string))
                };
                let time = seconds("duration");
                let best_lap = matches!(
                    session_type,
                    SessionType::Fp1 | SessionType::Fp2 | SessionType::Fp3
                )
                .then(|| time.clone())
                .flatten();
                let source_driver_id =
                    number.map_or_else(|| "unknown".to_string(), |number| number.to_string());
                let source_constructor_id = if team_name.is_empty() {
                    "unknown"
                } else {
                    team_name
                };
                SessionResult {
                    session_id: session_id.to_string(),
                    position,
                    classification: classification.to_string(),
                    driver_id: driver_id.unwrap_or_else(|| format!("openf1:{source_driver_id}")),
                    driver_name: roster_driver
                        .and_then(|driver| driver["full_name"].as_str())
                        .unwrap_or_default()
                        .to_string(),
                    constructor_id: constructor_id
                        .unwrap_or_else(|| format!("openf1:{source_constructor_id}")),
                    team: team_name.to_string(),
                    time: time.clone(),
                    best_lap,
                    q1: None,
                    q2: None,
                    q3: None,
                    race_time: matches!(session_type, SessionType::Race | SessionType::Sprint)
                        .then_some(time)
                        .flatten(),
                    gap: seconds("gap_to_leader"),
                    laps: row["number_of_laps"].as_i64(),
                    points: row["points"].as_f64(),
                    source: "openf1".to_string(),
                    source_updated_at: None,
                    fetched_at: fetched_at.to_string(),
                    revision: 1,
                    quality: "partial".to_string(),
                }
            })
            .collect::<Vec<_>>();
        let actual_numbers = rows
            .iter()
            .filter_map(|row| row["driver_number"].as_i64())
            .collect::<BTreeSet<_>>();
        complete &= actual_numbers == expected_numbers && actual_numbers.len() == rows.len();
        let quality = if complete {
            DataQuality::Provisional
        } else {
            DataQuality::Partial
        };
        for row in &mut results {
            row.quality = quality.as_str().to_string();
        }
        (results, quality)
    }

    pub fn decode_driver_standings(
        &self,
        rows: &[Value],
        season: i64,
        fetched_at: &str,
    ) -> Vec<DriverStanding> {
        rows.iter()
            .filter_map(|row| {
                let driver = &row["Driver"];
                Some(DriverStanding {
                    season,
                    position: row["position"].as_str()?.parse().ok()?,
                    driver_id: driver["driverId"].as_str()?.to_string(),
                    driver_name: format!(
                        "{} {}",
                        driver["givenName"].as_str()?,
                        driver["familyName"].as_str()?
                    ),
                    constructor: row["Constructors"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|constructor| constructor["name"].as_str())
                        .collect::<Vec<_>>()
                        .join(", "),
                    constructor_ids: row["Constructors"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|c| c["constructorId"].as_str().map(str::to_string))
                        .collect(),
                    points: row["points"].as_str()?.parse().ok()?,
                    wins: row["wins"].as_str()?.parse().ok()?,
                    source: "jolpica-ergast".to_string(),
                    fetched_at: fetched_at.to_string(),
                    revision: 1,
                })
            })
            .collect()
    }

    pub fn decode_constructor_standings(
        &self,
        rows: &[Value],
        season: i64,
        fetched_at: &str,
    ) -> Vec<ConstructorStanding> {
        rows.iter()
            .filter_map(|row| {
                Some(ConstructorStanding {
                    season,
                    position: row["position"].as_str()?.parse().ok()?,
                    constructor_id: row["Constructor"]["constructorId"].as_str()?.to_string(),
                    constructor_name: row["Constructor"]["name"].as_str()?.to_string(),
                    points: row["points"].as_str()?.parse().ok()?,
                    wins: row["wins"].as_str()?.parse().ok()?,
                    source: "jolpica-ergast".to_string(),
                    fetched_at: fetched_at.to_string(),
                    revision: 1,
                })
            })
            .collect()
    }
}

fn driver_numbers(drivers: &[Value]) -> BTreeSet<i64> {
    drivers
        .iter()
        .filter_map(|driver| driver["driver_number"].as_i64())
        .collect()
}

pub fn is_complete(quality: DataQuality) -> bool {
    quality == DataQuality::Provisional
}

pub fn availability(quality: DataQuality) -> ProviderAvailability {
    if is_complete(quality) {
        ProviderAvailability::Available
    } else {
        ProviderAvailability::Partial
    }
}

fn normalize_url(value: &str) -> String {
    value
        .trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_start_matches("www.")
        .trim_end_matches('/')
        .to_ascii_lowercase()
}

fn normalize_name(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identities() -> IdentityMaps {
        IdentityMaps::from_ergast(
            &[serde_json::json!({
                "driverId": "leclerc", "permanentNumber": "16",
                "url": "https://en.wikipedia.org/wiki/Charles_Leclerc"
            })],
            &[serde_json::json!({
                "constructorId": "ferrari", "name": "Ferrari",
                "url": "https://en.wikipedia.org/wiki/Scuderia_Ferrari"
            })],
        )
    }

    #[test]
    fn test_alpha_fixtures_cover_all_session_types_and_phase_times() {
        let source = identities();
        let drivers = [serde_json::json!({"driver_number":16,"full_name":"Charles Leclerc"})];
        let cases = [
            (
                SessionType::Fp1,
                include_str!("../../tests/fixtures/jolpica-result-fp1.json"),
            ),
            (
                SessionType::Fp2,
                include_str!("../../tests/fixtures/jolpica-result-fp2.json"),
            ),
            (
                SessionType::Fp3,
                include_str!("../../tests/fixtures/jolpica-result-fp3.json"),
            ),
            (
                SessionType::SprintQualifying,
                include_str!("../../tests/fixtures/jolpica-result-sprint-qualifying.json"),
            ),
            (
                SessionType::Sprint,
                include_str!("../../tests/fixtures/jolpica-result-sprint.json"),
            ),
            (
                SessionType::Qualifying,
                include_str!("../../tests/fixtures/jolpica-result-qualifying.json"),
            ),
            (
                SessionType::Race,
                include_str!("../../tests/fixtures/jolpica-result-race.json"),
            ),
        ];
        for (session_type, fixture) in cases {
            let payload: Value = serde_json::from_str(fixture).unwrap();
            let (rows, quality) = source.decode_alpha_results(
                &payload,
                "2026:1:test",
                session_type,
                &drivers,
                "2026-10-09T00:00:00Z",
            );
            assert_eq!(quality, DataQuality::Provisional);
            assert_eq!(rows[0].driver_id, "leclerc");
            assert_eq!(rows[0].constructor_id, "ferrari");
            assert_eq!(rows[0].session_id, "2026:1:test");
        }
        let qualifying: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-result-qualifying.json"
        ))
        .unwrap();
        let (rows, _) = source.decode_alpha_results(
            &qualifying,
            "2026:1:qualifying",
            SessionType::Qualifying,
            &drivers,
            "2026-10-09T00:00:00Z",
        );
        assert_eq!(rows[0].q1.as_deref(), Some("1:20.100"));
        assert_eq!(rows[0].q2.as_deref(), Some("1:19.400"));
        assert_eq!(rows[0].q3.as_deref(), Some("1:19.100"));
        let race: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-result-race.json"
        ))
        .unwrap();
        let (rows, _) = source.decode_alpha_results(
            &race,
            "2026:1:race",
            SessionType::Race,
            &drivers,
            "2026-10-09T00:00:00Z",
        );
        assert_eq!(rows[0].race_time.as_deref(), Some("1:20.123"));
    }

    #[test]
    fn test_partial_roster_and_explicit_classification_are_preserved() {
        let source = identities();
        let mut payload: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-result-race.json"
        ))
        .unwrap();
        payload["data"]["results"][0]["position"] = Value::Null;
        payload["data"]["results"][0]["position_text"] = serde_json::json!("DSQ");
        payload["data"]["results"][0]["status"] = serde_json::json!("DSQ");
        payload["data"]["results"][0]["is_classified"] = serde_json::json!(false);
        let (rows, quality) = source.decode_alpha_results(
            &payload,
            "session",
            SessionType::Race,
            &[
                serde_json::json!({"driver_number":16}),
                serde_json::json!({"driver_number":99}),
            ],
            "2026-10-09T00:00:00Z",
        );
        assert_eq!(quality, DataQuality::Partial);
        assert_eq!(rows[0].position, None);
        assert_eq!(rows[0].classification, "DSQ");
        assert_eq!(rows[0].driver_id, "leclerc");
    }

    #[test]
    fn test_unknown_identity_and_unplaced_status_are_preserved_as_partial() {
        let source = identities();
        for (status, expected) in [
            ("Retired", "DNF"),
            ("Did not start", "DNS"),
            ("Disqualified", "DSQ"),
        ] {
            let mut payload: Value = serde_json::from_str(include_str!(
                "../../tests/fixtures/jolpica-result-race.json"
            ))
            .unwrap();
            let row = &mut payload["data"]["results"][0];
            row["driver"]["wikipedia"] = serde_json::json!("https://example.com/unknown");
            row["team"]["wikipedia"] = serde_json::json!("https://example.com/unknown-team");
            row["position"] = Value::Null;
            row["position_text"] = serde_json::json!(status);
            row["status"] = serde_json::json!(status);
            row["is_classified"] = serde_json::json!(false);
            let (rows, quality) = source.decode_alpha_results(
                &payload,
                "session",
                SessionType::Race,
                &[serde_json::json!({"driver_number":16})],
                "2026-10-09T00:00:00Z",
            );
            assert_eq!(quality, DataQuality::Partial);
            assert_eq!(rows[0].classification, expected);
            assert_eq!(rows[0].driver_id, "jolpica-alpha:driver_lc");
            assert_eq!(rows[0].constructor_id, "jolpica-alpha:team_ferrari");
        }
    }

    #[test]
    fn test_no_valid_lap_keeps_optional_times_empty_without_downgrading_classified_roster() {
        let source = identities();
        let mut payload: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-result-qualifying.json"
        ))
        .unwrap();
        let row = &mut payload["data"]["results"][0];
        row["time"] = Value::Null;
        row["fastest_lap"] = Value::Null;
        row["components"] = serde_json::json!({});
        let (rows, quality) = source.decode_alpha_results(
            &payload,
            "session",
            SessionType::Qualifying,
            &[serde_json::json!({"driver_number":16})],
            "2026-10-09T00:00:00Z",
        );
        assert_eq!(quality, DataQuality::Provisional);
        assert_eq!(rows[0].time, None);
        assert_eq!(rows[0].best_lap, None);
        assert_eq!(rows[0].q1, None);
        assert_eq!(rows[0].q2, None);
        assert_eq!(rows[0].q3, None);
    }

    #[test]
    fn test_openf1_results_map_by_car_number_and_roster_team() {
        let source = identities();
        let drivers = [
            serde_json::json!({"driver_number":16,"full_name":"Charles Leclerc","team_name":"Ferrari"}),
        ];
        let rows = [
            serde_json::json!({"driver_number":16,"position":1,"duration":82.4,"gap_to_leader":0,"number_of_laps":58,"points":25,"dnf":false,"dns":false,"dsq":false}),
        ];
        let (results, quality) = source.decode_openf1_results(
            &rows,
            &drivers,
            "session",
            SessionType::Race,
            1,
            "2026-10-09T00:00:00Z",
        );
        assert_eq!(quality, DataQuality::Provisional);
        assert_eq!(results[0].driver_id, "leclerc");
        assert_eq!(results[0].constructor_id, "ferrari");
        assert_eq!(results[0].race_time.as_deref(), Some("82.4"));

        let practice_rows = [serde_json::json!({
            "driver_number":16,"position":1,"duration":82.4,
            "gap_to_leader":"+1 LAP","number_of_laps":4,
            "dnf":false,"dns":false,"dsq":false
        })];
        let (practice, quality) = source.decode_openf1_results(
            &practice_rows,
            &drivers,
            "practice",
            SessionType::Fp1,
            1,
            "2026-10-09T00:00:00Z",
        );
        assert_eq!(quality, DataQuality::Provisional);
        assert_eq!(practice[0].best_lap.as_deref(), Some("82.4"));
        assert_eq!(practice[0].gap.as_deref(), Some("+1 LAP"));
    }

    #[test]
    fn test_official_standings_include_all_constructor_ids() {
        let source = identities();
        let rows = [serde_json::json!({
            "position":"1","points":"25.0","wins":"1",
            "Driver":{"driverId":"leclerc","givenName":"Charles","familyName":"Leclerc"},
            "Constructors":[{"constructorId":"ferrari","name":"Ferrari"},{"constructorId":"mclaren","name":"McLaren"}]
        })];
        let standings = source.decode_driver_standings(&rows, 2026, "2026-10-09T00:00:00Z");
        assert_eq!(standings.len(), 1);
        assert_eq!(standings[0].constructor_ids, vec!["ferrari", "mclaren"]);
        assert_eq!(standings[0].constructor, "Ferrari, McLaren");
    }
}
