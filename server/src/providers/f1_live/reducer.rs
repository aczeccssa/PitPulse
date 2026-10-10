use std::collections::BTreeMap;

use serde_json::Value;

use crate::{
    domain::live::{LiveDriver, LiveSector, LiveSnapshot, LiveSourceMode, LiveStatus},
    providers::f1_live::{models::TopicPatch, patches::deep_merge},
};

pub const LIVE_TOPICS: [&str; 8] = [
    "Heartbeat",
    "SessionInfo",
    "SessionStatus",
    "DriverList",
    "TimingData",
    "LapCount",
    "TrackStatus",
    "RaceControlMessages",
];

#[derive(Debug, Default, Clone)]
pub struct LiveTopicReducer {
    topics: BTreeMap<String, Value>,
    session_id: Option<String>,
    last_data_updated_at: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ReducedLiveUpdate {
    pub snapshot: LiveSnapshot,
    pub data_updated: bool,
}

impl LiveTopicReducer {
    pub fn reset(&mut self) {
        self.topics.clear();
        self.session_id = None;
        self.last_data_updated_at = None;
    }

    pub fn apply_batch(&mut self, value: &Value, received_at: &str) -> Option<ReducedLiveUpdate> {
        let mut patches = Vec::new();
        collect_patches(value, &mut patches);
        if patches.is_empty() {
            return None;
        }

        let mut data_updated = false;
        for patch in patches {
            if patch.topic != "Heartbeat" {
                data_updated = true;
            }
            self.apply_patch(&patch);
        }
        if data_updated {
            self.last_data_updated_at = Some(received_at.to_string());
        }
        Some(ReducedLiveUpdate {
            snapshot: self.snapshot(received_at),
            data_updated,
        })
    }

    pub fn snapshot(&self, received_at: &str) -> LiveSnapshot {
        let session_info = self.topic("SessionInfo");
        let timing_lines = self
            .topic("TimingData")
            .and_then(|topic| topic.get("Lines"))
            .and_then(Value::as_object);
        let driver_list = self.topic("DriverList").and_then(Value::as_object);
        let mut drivers = timing_lines
            .into_iter()
            .flat_map(|lines| lines.iter())
            .filter(|(_, line)| line.is_object())
            .map(|(number, line)| {
                let metadata = driver_list.and_then(|list| list.get(number));
                LiveDriver {
                    number: metadata
                        .and_then(|driver| driver.get("RacingNumber"))
                        .and_then(value_string)
                        .unwrap_or_else(|| number.clone()),
                    name: metadata.and_then(|driver| {
                        first_string(driver, &["FullName", "BroadcastName", "Tla"])
                    }),
                    team: metadata.and_then(|driver| first_string(driver, &["TeamName"])),
                    position: value_i64(line.get("Position").or_else(|| line.get("Line"))),
                    gap: line.get("GapToLeader").and_then(value_string),
                    interval: line
                        .get("IntervalToPositionAhead")
                        .or_else(|| line.get("IntervalToNext"))
                        .and_then(|value| value_string(value.get("Value").unwrap_or(value))),
                    lap_count: value_i64(line.get("NumberOfLaps").or_else(|| line.get("Laps"))),
                    last_lap: line
                        .get("LastLapTime")
                        .and_then(|value| value_string(value.get("Value").unwrap_or(value))),
                    sectors: line.get("Sectors").map(project_sectors),
                    in_pit: line.get("InPit").and_then(Value::as_bool),
                    retired: line.get("Retired").and_then(Value::as_bool),
                    best_lap: line
                        .get("BestLapTime")
                        .and_then(|value| value_string(value.get("Value").unwrap_or(value))),
                }
            })
            .collect::<Vec<_>>();
        if drivers.is_empty() {
            drivers = driver_list
                .into_iter()
                .flat_map(|list| list.iter())
                .filter(|(_, driver)| driver.is_object())
                .map(|(number, driver)| LiveDriver {
                    number: driver
                        .get("RacingNumber")
                        .and_then(value_string)
                        .unwrap_or_else(|| number.clone()),
                    name: first_string(driver, &["FullName", "BroadcastName", "Tla"]),
                    team: first_string(driver, &["TeamName"]),
                    position: None,
                    gap: None,
                    interval: None,
                    lap_count: None,
                    last_lap: None,
                    best_lap: None,
                    sectors: None,
                    in_pit: None,
                    retired: None,
                })
                .collect();
        }
        drivers.sort_by(|left, right| {
            left.position
                .cmp(&right.position)
                .then_with(|| left.number.cmp(&right.number))
        });

        let lap_count = self
            .topic("LapCount")
            .and_then(|topic| topic.get("CurrentLap"))
            .and_then(|value| value_i64(Some(value.get("Value").unwrap_or(value))));
        let track_status = self
            .topic("TrackStatus")
            .and_then(|topic| first_string(topic, &["Message", "Status"]))
            .map(|status| match status.as_str() {
                "1" => "All clear".to_string(),
                "2" => "Yellow flag".to_string(),
                "4" => "Safety car".to_string(),
                "5" => "Red flag".to_string(),
                "6" => "Virtual safety car".to_string(),
                "7" => "Virtual safety car ending".to_string(),
                _ => status,
            });
        let race_control = self
            .topic("RaceControlMessages")
            .and_then(|topic| topic.get("Messages"))
            .map(recent_messages);

        LiveSnapshot {
            schema_version: 1,
            state_version: 0,
            session_id: self.session_id.clone(),
            session_name: session_info
                .and_then(|topic| first_string(topic, &["Name"]))
                .or_else(|| {
                    session_info
                        .and_then(|topic| topic.pointer("/Meeting/Name"))
                        .and_then(value_string)
                }),
            meeting_name: session_info
                .and_then(|topic| topic.pointer("/Meeting/Name"))
                .and_then(value_string),
            country_code: session_info
                .and_then(|topic| topic.pointer("/Meeting/Country/Name"))
                .and_then(Value::as_str)
                .and_then(crate::domain::country::country_code),
            source_status: LiveStatus::Connected,
            source_mode: LiveSourceMode::Live,
            status_reason: None,
            session_type: session_info.and_then(|topic| first_string(topic, &["Name", "Type"])),
            session_status: self
                .topic("SessionStatus")
                .and_then(|topic| first_string(topic, &["Status"])),
            track_status,
            lap_count,
            total_laps: self
                .topic("LapCount")
                .and_then(|topic| value_i64(topic.get("TotalLaps"))),
            updated_at: self.last_data_updated_at.clone(),
            last_transport_at: Some(received_at.to_string()),
            drivers,
            race_control,
        }
    }

    fn apply_patch(&mut self, patch: &TopicPatch) {
        if patch.topic == "Heartbeat" {
            return;
        }
        if patch.topic == "SessionInfo" {
            let mut session = self
                .topics
                .get("SessionInfo")
                .cloned()
                .unwrap_or(Value::Null);
            deep_merge(&mut session, &patch.patch);
            let session_id = session
                .get("Key")
                .or_else(|| session.get("SessionKey"))
                .or_else(|| session.get("SessionId"))
                .and_then(value_string);
            if self.session_id.is_some() && session_id != self.session_id {
                self.topics.clear();
            }
            self.session_id = session_id;
            self.topics.insert(patch.topic.clone(), session);
            return;
        }
        deep_merge(
            self.topics
                .entry(patch.topic.clone())
                .or_insert(Value::Null),
            &patch.patch,
        );
    }

    fn topic(&self, topic: &str) -> Option<&Value> {
        self.topics.get(topic)
    }
}

fn indexed(value: &Value, index: usize) -> Option<&Value> {
    value.get(index).or_else(|| value.get(index.to_string()))
}

fn project_sectors(value: &Value) -> Vec<LiveSector> {
    (0..3)
        .map(|index| {
            let sector = indexed(value, index);
            let segments = sector.and_then(|sector| sector.get("Segments"));
            let count = segments
                .map(|value| {
                    value.as_array().map(Vec::len).unwrap_or_else(|| {
                        value
                            .as_object()
                            .into_iter()
                            .flat_map(|map| map.keys())
                            .filter_map(|key| key.parse::<usize>().ok())
                            .filter(|index| *index < 64)
                            .max()
                            .map(|index| index + 1)
                            .unwrap_or(0)
                    })
                })
                .unwrap_or(0)
                .min(64);
            LiveSector {
                value: sector
                    .and_then(|sector| sector.get("Value"))
                    .and_then(value_string),
                personal_fastest: sector
                    .and_then(|sector| sector.get("PersonalFastest"))
                    .and_then(Value::as_bool),
                overall_fastest: sector
                    .and_then(|sector| sector.get("OverallFastest"))
                    .and_then(Value::as_bool),
                segments: (0..count)
                    .map(|index| {
                        segments
                            .and_then(|segments| indexed(segments, index))
                            .and_then(|segment| value_i64(segment.get("Status")))
                    })
                    .collect(),
            }
        })
        .collect()
}

fn collect_patches(value: &Value, output: &mut Vec<TopicPatch>) {
    if let Some(object) = value.as_object() {
        for topic in LIVE_TOPICS {
            if topic != "Heartbeat"
                && let Some(patch) = object.get(topic)
            {
                output.push(TopicPatch {
                    topic: topic.to_string(),
                    patch: patch.clone(),
                    received_at: String::new(),
                });
            }
        }
        if let Some(heartbeat) = object.get("Heartbeat") {
            output.push(TopicPatch {
                topic: "Heartbeat".to_string(),
                patch: heartbeat.clone(),
                received_at: String::new(),
            });
        }
        return;
    }

    let Some(items) = value.as_array() else {
        return;
    };
    if items
        .first()
        .and_then(Value::as_str)
        .is_some_and(is_live_topic)
    {
        push_patch(items, output);
        return;
    }
    for item in items {
        if let Some(entry) = item.as_array() {
            push_patch(entry, output);
        }
    }
}

fn push_patch(items: &[Value], output: &mut Vec<TopicPatch>) {
    let Some(topic) = items.first().and_then(Value::as_str) else {
        return;
    };
    if items.len() < 2 || !is_live_topic(topic) {
        return;
    }
    output.push(TopicPatch {
        topic: topic.to_string(),
        patch: items[1].clone(),
        received_at: items.get(2).and_then(value_string).unwrap_or_default(),
    });
}

fn is_live_topic(topic: &str) -> bool {
    LIVE_TOPICS.contains(&topic)
}

fn value_string(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn value_i64(value: Option<&Value>) -> Option<i64> {
    value.and_then(|value| {
        value
            .as_i64()
            .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
    })
}

fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(value_string))
}

fn recent_messages(value: &Value) -> Vec<Value> {
    let mut messages = value
        .as_object()
        .map(|object| object.iter().collect::<Vec<_>>())
        .unwrap_or_default();
    messages.sort_by(|left, right| {
        left.0
            .parse::<u64>()
            .ok()
            .cmp(&right.0.parse::<u64>().ok())
            .then_with(|| left.0.cmp(right.0))
    });
    messages
        .into_iter()
        .rev()
        .take(20)
        .map(|(_, value)| value.clone())
        .collect()
}

pub fn is_patch_size_allowed(value: &Value) -> bool {
    serde_json::to_vec(value).is_ok_and(|bytes| bytes.len() <= 2 * 1024 * 1024)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_sprint_sparse_sectors_keep_other_times_and_ignore_metadata_keys() {
        let mut reducer = LiveTopicReducer::default();
        let initial = json!({
            "SessionInfo":{"Key":1,"Name":"Sprint","Type":"Race","Meeting":{"Name":"Singapore Grand Prix","Country":{"Name":"Singapore"}}},
            "DriverList":{"_kf":true,"1":{"FullName":"Max Verstappen"}},
            "TimingData":{"Lines":{"1":{"Line":0,"Position":"1","Sectors":[
                {"Value":"25.000","Segments":[{"Status":2048},{"Status":2049}]},
                {"Value":"30.000","PersonalFastest":true},{"Value":"22.000"}]}}},
            "LapCount":{"CurrentLap":4,"TotalLaps":19}
        });
        let snapshot = reducer.apply_batch(&initial, "now").unwrap().snapshot;
        assert_eq!(snapshot.session_type.as_deref(), Some("Sprint"));
        assert_eq!(snapshot.country_code.as_deref(), Some("SG"));
        assert_eq!(snapshot.total_laps, Some(19));
        assert_eq!(snapshot.drivers[0].position, Some(1));
        let delta = json!(["TimingData",{"Lines":{"1":{"Sectors":{"0":{"Segments":{"1":{"Status":2051}}}}}}},"now"]);
        let snapshot = reducer.apply_batch(&delta, "later").unwrap().snapshot;
        let sectors = snapshot.drivers[0].sectors.as_ref().unwrap();
        assert_eq!(sectors.len(), 3);
        assert_eq!(sectors[0].segments, vec![Some(2048), Some(2051)]);
        assert_eq!(sectors[1].value.as_deref(), Some("30.000"));
        assert_eq!(sectors[2].value.as_deref(), Some("22.000"));
        reducer.reset();
        let snapshot = reducer
            .apply_batch(
                &json!({"DriverList":{"_kf":true,"1":{"FullName":"Max Verstappen"}}}),
                "now",
            )
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.drivers.len(), 1);
        assert!(snapshot.drivers[0].sectors.is_none());
        assert_eq!(
            project_sectors(&json!({"1":{"Value":"29.000"}}))[0].value,
            None
        );
    }

    #[test]
    fn test_indexed_patches_merge_and_project_known_fields() {
        let mut reducer = LiveTopicReducer::default();
        let initial = json!({
            "SessionInfo": {"Key": 100, "Name": "Practice", "Type": "Practice", "Meeting": {"Name": "Austin"}},
            "DriverList": {"44": {"FullName": "Driver One", "TeamName": "Sample"}},
            "TimingData": {"Lines": {"44": {"Line": 1, "GapToLeader": "LEADER", "LastLapTime": {"Value": "1:30.000"}, "NumberOfLaps": 3}}},
            "LapCount": {"CurrentLap": {"Value": 3}},
            "TrackStatus": {"Status": "2"}
        });
        let snapshot = reducer
            .apply_batch(&initial, "2026-10-10T01:00:00Z")
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.session_id.as_deref(), Some("100"));
        assert_eq!(snapshot.session_name.as_deref(), Some("Practice"));
        assert_eq!(snapshot.session_status, None);
        assert_eq!(snapshot.lap_count, Some(3));
        assert_eq!(snapshot.track_status.as_deref(), Some("Yellow flag"));
        assert_eq!(snapshot.drivers[0].name.as_deref(), Some("Driver One"));
        assert_eq!(snapshot.drivers[0].last_lap.as_deref(), Some("1:30.000"));

        let delta = json!(["TimingData", {"Lines": {"44": {"IntervalToPositionAhead": {"Value": "0.4"}, "GapToLeader": null}}}, "16:00:00.000"]);
        let snapshot = reducer
            .apply_batch(&delta, "2026-10-10T01:00:15Z")
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.drivers[0].gap, None);
        assert_eq!(snapshot.drivers[0].interval.as_deref(), Some("0.4"));
    }

    #[test]
    fn test_session_change_clears_previous_session_topics() {
        let mut reducer = LiveTopicReducer::default();
        reducer.apply_batch(
            &json!({"SessionInfo": {"Key": "first"}, "TimingData": {"Lines": {"44": {"Line": 1}}}}),
            "2026-10-10T01:00:00Z",
        );
        let snapshot = reducer
            .apply_batch(
                &json!(["SessionInfo", {"Key": "second"}, "16:01:00.000"]),
                "2026-10-10T01:01:00Z",
            )
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.session_id.as_deref(), Some("second"));
        assert!(snapshot.drivers.is_empty());
    }

    #[test]
    fn test_unknown_topics_and_malformed_messages_are_ignored() {
        let mut reducer = LiveTopicReducer::default();
        assert!(
            reducer
                .apply_batch(&json!(["CarData.z", "compressed"]), "now")
                .is_none()
        );
        assert!(reducer.apply_batch(&json!(["TimingData"]), "now").is_none());
        assert!(reducer.apply_batch(&json!("not a feed"), "now").is_none());
    }

    #[test]
    fn test_heartbeat_updates_transport_without_refreshing_data_timestamp() {
        let mut reducer = LiveTopicReducer::default();
        let data = reducer
            .apply_batch(
                &json!(["LapCount", {"CurrentLap": 2}]),
                "2026-10-10T01:00:00Z",
            )
            .unwrap()
            .snapshot;
        assert_eq!(data.updated_at.as_deref(), Some("2026-10-10T01:00:00Z"));
        let heartbeat = reducer
            .apply_batch(&json!(["Heartbeat", {}]), "2026-10-10T01:01:00Z")
            .unwrap();
        assert_eq!(heartbeat.snapshot.updated_at, data.updated_at);
        assert_eq!(
            heartbeat.snapshot.last_transport_at.as_deref(),
            Some("2026-10-10T01:01:00Z")
        );
        assert!(!heartbeat.data_updated);
    }

    #[test]
    fn test_patch_size_is_bounded() {
        assert!(is_patch_size_allowed(&json!({"ok": true})));
        assert!(!is_patch_size_allowed(
            &json!({"payload": "x".repeat(2 * 1024 * 1024)})
        ));
    }
}
