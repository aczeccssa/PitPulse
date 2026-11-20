use std::collections::BTreeMap;

use serde_json::Value;

use crate::{
    domain::live::{LiveDriver, LiveSector, LiveSnapshot, LiveSourceMode, LiveStatus},
    providers::f1_live::{models::TopicPatch, patches::deep_merge},
};

const RELAY_SOURCE: &str = "formula1dashboard_relay";
const RELAY_MAX_AGE_SECONDS: i64 = 30;

pub const LIVE_TOPICS: [&str; 16] = [
    "Heartbeat",
    "SessionInfo",
    "SessionStatus",
    "ExtrapolatedClock",
    "DriverList",
    "TimingData",
    "LapCount",
    "TrackStatus",
    "RaceControlMessages",
    "Position.z",
    "CarData.z",
    "WeatherData",
    "TeamRadio",
    "Stints",
    "TimingAppData",
    "TyreStintSeries",
];

#[derive(Debug, Default, Clone)]
pub struct LiveTopicReducer {
    topics: BTreeMap<String, Value>,
    session_id: Option<String>,
    last_data_updated_at: Option<String>,
    locations: BTreeMap<String, crate::domain::live::LiveLocation>,
    telemetry: BTreeMap<String, crate::domain::live::LiveTelemetry>,
    weather_updated_at: Option<String>,
    position_times: BTreeMap<String, String>,
    telemetry_times: BTreeMap<String, String>,
    position_received: usize,
    position_decoded: usize,
    position_decode_error: bool,
}

#[derive(Debug, Clone)]
pub struct ReducedLiveUpdate {
    pub snapshot: LiveSnapshot,
    pub data_updated: bool,
}

impl LiveTopicReducer {
    pub fn session_id(&self) -> Option<&str> {
        self.session_id.as_deref()
    }

    pub fn reset(&mut self) {
        self.topics.clear();
        self.session_id = None;
        self.last_data_updated_at = None;
        self.locations.clear();
        self.telemetry.clear();
        self.weather_updated_at = None;
        self.position_times.clear();
        self.telemetry_times.clear();
        self.position_received = 0;
        self.position_decoded = 0;
        self.position_decode_error = false;
    }

    pub fn apply_batch(&mut self, value: &Value, received_at: &str) -> Option<ReducedLiveUpdate> {
        self.apply_batch_with_freshness(value, received_at, true)
    }

    pub fn apply_initial_snapshot(
        &mut self,
        value: &Value,
        received_at: &str,
    ) -> Option<ReducedLiveUpdate> {
        self.apply_batch_with_freshness(value, received_at, false)
    }

    fn apply_batch_with_freshness(
        &mut self,
        value: &Value,
        received_at: &str,
        feed_sample: bool,
    ) -> Option<ReducedLiveUpdate> {
        let mut patches = Vec::new();
        collect_patches(value, &mut patches);
        if patches.is_empty() {
            return None;
        }

        let mut data_updated = false;
        let mut accepted = false;
        for patch in patches {
            if patch.topic == "Heartbeat" {
                accepted = true;
            }
            let previous_position_status = self.position_status();
            let changed = self.apply_patch(&patch, received_at, feed_sample);
            if changed && patch.topic != "Heartbeat" {
                data_updated = true;
                accepted = true;
            }
            if patch.topic == "Position.z" && previous_position_status != self.position_status() {
                accepted = true;
            }
        }
        if !accepted {
            return None;
        }
        if data_updated {
            self.last_data_updated_at = Some(received_at.to_string());
        }
        Some(ReducedLiveUpdate {
            snapshot: self.snapshot(received_at),
            data_updated,
        })
    }

    pub fn apply_relay_telemetry(
        &mut self,
        session_id: &str,
        value: &Value,
        received_at: &str,
    ) -> bool {
        if self.session_id.as_deref() != Some(session_id) {
            return false;
        }
        let Some(latest) = crate::scheduler::add_seconds(received_at, 5) else {
            return false;
        };
        let mut patches = Vec::new();
        collect_patches(value, &mut patches);
        let mut changed = false;
        for patch in patches
            .into_iter()
            .filter(|patch| matches!(patch.topic.as_str(), "CarData.z" | "Position.z"))
        {
            changed |= self.apply_compressed(&patch, received_at, true, Some(&latest));
        }
        changed
    }

    pub fn has_relay_telemetry(&self) -> bool {
        self.telemetry
            .values()
            .any(|sample| sample.source.as_deref() == Some(RELAY_SOURCE))
            || self
                .locations
                .values()
                .any(|sample| sample.source.as_deref() == Some(RELAY_SOURCE))
    }

    pub fn restore_relay_telemetry(&mut self, cached: &LiveSnapshot) {
        if self.session_id.is_none() || self.session_id != cached.session_id {
            return;
        }
        for driver in &cached.drivers {
            let number = &driver.number;
            if let Some(sample) = driver.telemetry.as_ref().filter(|sample| {
                sample.source.as_deref() == Some(RELAY_SOURCE)
                    && self
                        .telemetry_times
                        .get(number)
                        .is_none_or(|utc| utc < &sample.utc)
            }) {
                self.telemetry_times
                    .insert(number.clone(), sample.utc.clone());
                self.telemetry.insert(number.clone(), sample.clone());
            }
            if let Some(sample) = driver.location.as_ref().filter(|sample| {
                sample.source.as_deref() == Some(RELAY_SOURCE)
                    && self
                        .position_times
                        .get(number)
                        .is_none_or(|utc| utc < &sample.utc)
            }) {
                self.position_times
                    .insert(number.clone(), sample.utc.clone());
                self.locations.insert(number.clone(), sample.clone());
                self.position_decoded = self.locations.len();
                self.position_received = self.locations.len();
            }
        }
    }

    pub fn relay_cache(snapshot: &LiveSnapshot) -> LiveSnapshot {
        let drivers = snapshot
            .drivers
            .iter()
            .filter_map(|driver| {
                let telemetry = driver
                    .telemetry
                    .as_ref()
                    .filter(|sample| sample.source.as_deref() == Some(RELAY_SOURCE))
                    .cloned();
                let location = driver
                    .location
                    .as_ref()
                    .filter(|sample| sample.source.as_deref() == Some(RELAY_SOURCE))
                    .cloned();
                (telemetry.is_some() || location.is_some()).then(|| LiveDriver {
                    number: driver.number.clone(),
                    telemetry,
                    location,
                    ..LiveDriver::default()
                })
            })
            .collect();
        LiveSnapshot {
            session_id: snapshot.session_id.clone(),
            drivers,
            ..LiveSnapshot::default()
        }
    }

    pub fn snapshot(&self, received_at: &str) -> LiveSnapshot {
        let session_info = self.topic("SessionInfo");
        let session_status = self
            .topic("SessionStatus")
            .and_then(|topic| first_string(topic, &["Status"]));
        let relay_window = session_status
            .as_deref()
            .filter(|status| super::telemetry_relay::is_active_status(status))
            .and_then(|_| relay_window(received_at));
        let location = |number| {
            self.locations.get(number).cloned().map(|mut sample| {
                sample.cached =
                    is_cached_sample(sample.source.as_deref(), &sample.utc, relay_window.as_ref());
                sample
            })
        };
        let telemetry = |number| {
            self.telemetry.get(number).cloned().map(|mut sample| {
                sample.cached =
                    is_cached_sample(sample.source.as_deref(), &sample.utc, relay_window.as_ref());
                sample
            })
        };
        let clock = self.topic("ExtrapolatedClock");
        let timing_lines = self
            .topic("TimingData")
            .and_then(|topic| topic.get("Lines"))
            .and_then(Value::as_object);
        let driver_list = self.topic("DriverList").and_then(Value::as_object);
        let stints = self.topic("Stints");
        let tyre_series = self
            .topic("TyreStintSeries")
            .and_then(|value| value.get("Stints"));
        let timing_app = self
            .topic("TimingAppData")
            .and_then(|value| value.get("Lines"));
        let mut drivers = timing_lines
            .into_iter()
            .flat_map(|lines| lines.iter())
            .filter(|(_, line)| line.is_object())
            .map(|(number, line)| {
                let metadata = driver_list.and_then(|list| list.get(number));
                let (tire_compound, tire_age_laps) =
                    stint_summary(stints, tyre_series, timing_app, number, line);
                LiveDriver {
                    location: location(number),
                    telemetry: telemetry(number),
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
                    tire_compound,
                    tire_age_laps,
                    ..LiveDriver::default()
                }
            })
            .collect::<Vec<_>>();
        if drivers.is_empty() {
            drivers = driver_list
                .into_iter()
                .flat_map(|list| list.iter())
                .filter(|(_, driver)| driver.is_object())
                .map(|(number, driver)| {
                    let (tire_compound, tire_age_laps) =
                        stint_summary(stints, tyre_series, timing_app, number, &Value::Null);
                    LiveDriver {
                        location: location(number),
                        telemetry: telemetry(number),
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
                        tire_compound,
                        tire_age_laps,
                        ..LiveDriver::default()
                    }
                })
                .collect();
        }
        let circuit_key = session_info
            .and_then(|t| t.pointer("/Meeting/Circuit/Key"))
            .and_then(value_string);
        for driver in &mut drivers {
            if let Some(location) = &mut driver.location {
                let utc = location.utc.clone();
                crate::services::circuits::locate(circuit_key.as_deref(), &utc, location);
            }
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

        let calibrated = drivers
            .iter()
            .filter(|driver| {
                driver.location.as_ref().is_some_and(|location| {
                    location.longitude.is_some() && location.latitude.is_some()
                })
            })
            .count();
        LiveSnapshot {
            schema_version: 1,
            series: Some("f1".to_string()),
            circuit_key: session_info
                .and_then(|t| t.pointer("/Meeting/Circuit/Key"))
                .and_then(value_string),
            circuit_name: session_info
                .and_then(|t| t.pointer("/Meeting/Circuit/ShortName"))
                .and_then(value_string),
            session_path: session_info
                .and_then(|t| t.get("Path"))
                .and_then(value_string),
            weather: self.project_weather(),
            team_radio: self.project_radio(),
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
            session_status,
            track_status,
            lap_count,
            total_laps: self
                .topic("LapCount")
                .and_then(|topic| value_i64(topic.get("TotalLaps"))),
            updated_at: self.last_data_updated_at.clone(),
            last_transport_at: Some(received_at.to_string()),
            drivers,
            race_control,
            position_status: Some(self.position_status_with_calibration(calibrated)),
            position_diagnostics: Some(crate::domain::live::LivePositionDiagnostics {
                received: self.position_received,
                decoded: self.position_decoded,
                calibrated,
            }),
            time_remaining_seconds: clock
                .and_then(|topic| topic.get("Remaining"))
                .and_then(Value::as_str)
                .and_then(clock_seconds),
            clock_sample_at: clock
                .and_then(|topic| topic.get("Utc"))
                .and_then(value_string),
            clock_running: clock
                .and_then(|topic| topic.get("Extrapolating"))
                .and_then(Value::as_bool),
            elapsed_seconds: None,
            is_time_based: None,
        }
    }

    fn position_status(&self) -> String {
        self.position_status_with_calibration(0)
    }

    fn position_status_with_calibration(&self, calibrated: usize) -> String {
        if self.position_decode_error || (self.position_received > 0 && self.position_decoded == 0)
        {
            "decode_error"
        } else if calibrated > 0 {
            "available"
        } else if self.position_decoded > 0 || !self.locations.is_empty() {
            "uncalibrated"
        } else {
            "waiting"
        }
        .to_string()
    }

    fn apply_patch(&mut self, patch: &TopicPatch, received_at: &str, feed_sample: bool) -> bool {
        if patch.topic.ends_with(".z") {
            return self.apply_compressed(patch, received_at, feed_sample, None);
        }
        if patch.topic == "WeatherData" {
            if !patch.patch.is_object() {
                return false;
            }
            let utc = canonical_utc(if patch.received_at.is_empty() {
                received_at
            } else {
                &patch.received_at
            });
            if let Some(utc) = utc {
                if self
                    .weather_updated_at
                    .as_ref()
                    .is_some_and(|old| old > &utc)
                {
                    return false;
                }
                self.weather_updated_at = Some(utc);
            } else {
                return false;
            }
        }
        if patch.topic == "Heartbeat" {
            return false;
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
                self.reset();
                session = patch.patch.clone();
            }
            self.session_id = session_id;
            self.topics.insert(patch.topic.clone(), session);
            return true;
        }
        deep_merge(
            self.topics
                .entry(patch.topic.clone())
                .or_insert(Value::Null),
            &patch.patch,
        );
        true
    }

    fn apply_compressed(
        &mut self,
        patch: &TopicPatch,
        received_at: &str,
        feed_sample: bool,
        relay_latest: Option<&str>,
    ) -> bool {
        let value = if patch.patch.is_object() && relay_latest.is_some() {
            Some(patch.patch.clone())
        } else {
            super::compressed::decode(&patch.patch)
        };
        let Some(value) = value else {
            if patch.topic == "Position.z" && relay_latest.is_none() {
                self.position_received = 0;
                self.position_decoded = 0;
                self.position_decode_error = true;
            }
            return false;
        };
        let (key, time_key) = if patch.topic == "Position.z" {
            ("Position", "Timestamp")
        } else {
            ("Entries", "Utc")
        };
        let Some(frames) = value.get(key).and_then(Value::as_array) else {
            if patch.topic == "Position.z" && relay_latest.is_none() {
                self.position_received = 0;
                self.position_decoded = 0;
                self.position_decode_error = true;
            }
            return false;
        };
        if patch.topic == "Position.z" {
            self.position_decode_error = false;
        }
        let mut changed = false;
        for frame in frames {
            let Some(utc) = frame
                .get(time_key)
                .and_then(Value::as_str)
                .and_then(canonical_utc)
            else {
                continue;
            };
            if relay_latest.is_some_and(|latest| utc.get(..19) > latest.get(..19)) {
                continue;
            }
            let cars = frame
                .get(if key == "Position" { "Entries" } else { "Cars" })
                .and_then(Value::as_object);
            let mut frame_received = 0;
            let mut frame_decoded = 0;
            for (number, car) in cars.into_iter().flatten() {
                if number.parse::<u16>().is_err() {
                    continue;
                }
                if key == "Position" {
                    if self
                        .position_times
                        .get(number)
                        .is_some_and(|old| old >= &utc)
                    {
                        continue;
                    }
                    frame_received += 1;
                    self.position_times.insert(number.clone(), utc.clone());
                    let old = self.locations.get(number);
                    let sample_x = numeric(car.get("X"));
                    let sample_y = numeric(car.get("Y"));
                    if sample_x.is_none() && sample_y.is_none() {
                        continue;
                    }
                    let (Some(x), Some(y)) = (
                        sample_x.or_else(|| old.map(|location| location.x)),
                        sample_y.or_else(|| old.map(|location| location.y)),
                    ) else {
                        continue;
                    };
                    frame_decoded += 1;
                    self.locations.insert(
                        number.clone(),
                        crate::domain::live::LiveLocation {
                            x,
                            y,
                            utc: utc.clone(),
                            source: relay_latest.map(|_| RELAY_SOURCE.to_string()),
                            cached: false,
                            received_at: feed_sample.then(|| received_at.to_string()),
                            status: car
                                .get("Status")
                                .and_then(value_string)
                                .or_else(|| old.and_then(|o| o.status.clone())),
                            longitude: None,
                            latitude: None,
                        },
                    );
                    changed = true;
                } else {
                    if self
                        .telemetry_times
                        .get(number)
                        .is_some_and(|old| old >= &utc)
                    {
                        continue;
                    }
                    let Some(channels) = car.get("Channels") else {
                        continue;
                    };
                    let previous = self.telemetry.get(number).cloned();
                    let entry = self.telemetry.entry(number.clone()).or_default();
                    entry.utc = utc.clone();
                    entry.source = relay_latest.map(|_| RELAY_SOURCE.to_string());
                    entry.received_at = feed_sample.then(|| received_at.to_string());
                    self.telemetry_times.insert(number.clone(), utc.clone());
                    for (field, channel) in [
                        (&mut entry.rpm, "0"),
                        (&mut entry.speed, "2"),
                        (&mut entry.gear, "3"),
                        (&mut entry.throttle, "4"),
                        (&mut entry.brake, "5"),
                        (&mut entry.drs, "45"),
                    ] {
                        if channels.get(channel).is_some() {
                            *field = numeric(channels.get(channel));
                        }
                    }
                    changed |= previous.as_ref() != Some(entry);
                }
            }
            if key == "Position" && frame_received > 0 {
                self.position_received = frame_received;
                self.position_decoded = frame_decoded;
                self.position_decode_error = frame_decoded == 0;
            }
        }
        changed
    }

    fn project_weather(&self) -> Option<crate::domain::live::LiveWeather> {
        let w = self.topic("WeatherData")?;
        Some(crate::domain::live::LiveWeather {
            utc: self.weather_updated_at.clone()?,
            air_temp: numeric(w.get("AirTemp")),
            track_temp: numeric(w.get("TrackTemp")),
            humidity: numeric(w.get("Humidity")),
            pressure: numeric(w.get("Pressure")),
            wind_speed: numeric(w.get("WindSpeed")),
            wind_direction: numeric(w.get("WindDirection")),
            rainfall: numeric(w.get("Rainfall")).map(|n| n != 0.0),
        })
    }

    fn project_radio(&self) -> Vec<crate::domain::live::LiveRadio> {
        self.topic("TeamRadio")
            .and_then(|t| t.get("Captures"))
            .map(recent_messages)
            .unwrap_or_default()
            .into_iter()
            .filter_map(|v| {
                Some(crate::domain::live::LiveRadio {
                    id: v.get("id")?.as_str()?.to_string(),
                    utc: canonical_utc(v.get("Utc")?.as_str()?)?,
                    driver_number: v.get("RacingNumber").and_then(value_string)?,
                    path: v.get("Path")?.as_str()?.to_string(),
                })
            })
            .collect()
    }

    fn topic(&self, topic: &str) -> Option<&Value> {
        self.topics.get(topic)
    }
}

fn relay_window(received_at: &str) -> Option<(String, String)> {
    Some((
        crate::scheduler::add_seconds(received_at, -RELAY_MAX_AGE_SECONDS)?,
        crate::scheduler::add_seconds(received_at, 5)?,
    ))
}

fn is_cached_sample(source: Option<&str>, utc: &str, window: Option<&(String, String)>) -> bool {
    source == Some(RELAY_SOURCE) && !window.is_some_and(|window| relay_time_is_valid(utc, window))
}

fn relay_time_is_valid(utc: &str, (earliest, latest): &(String, String)) -> bool {
    utc.get(..19)
        .zip(earliest.get(..19))
        .zip(latest.get(..19))
        .is_some_and(|((utc, earliest), latest)| earliest <= utc && utc <= latest)
}

// Fixed precision makes mixed upstream fractional timestamps compare chronologically.
fn canonical_utc(raw: &str) -> Option<String> {
    let raw = raw
        .trim()
        .strip_suffix('Z')
        .or_else(|| raw.trim().strip_suffix("+00:00"))
        .unwrap_or(raw.trim());
    let (base, fraction) = raw.split_once('.').unwrap_or((raw, ""));
    if base.len() != 19 || !fraction.bytes().all(|c| c.is_ascii_digit()) || fraction.len() > 9 {
        return None;
    }
    let normalized = crate::scheduler::add_seconds(&format!("{base}Z"), 0)?;
    if normalized.get(..19)? != base {
        return None;
    }
    Some(format!("{base}.{fraction:0<9}Z"))
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
                    .and_then(value_string)
                    .filter(|value| !value.trim().is_empty()),
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

fn clock_seconds(value: &str) -> Option<i64> {
    let (hours, rest) = value.split_once(':')?;
    let (minutes, seconds) = rest.split_once(':')?;
    let hours: i64 = hours.parse().ok()?;
    let minutes: i64 = minutes.parse().ok()?;
    let seconds: i64 = seconds.split('.').next()?.parse().ok()?;
    if !(0..=24).contains(&hours) || !(0..60).contains(&minutes) || !(0..60).contains(&seconds) {
        return None;
    }
    Some(hours * 3600 + minutes * 60 + seconds)
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

fn numeric(value: Option<&Value>) -> Option<f64> {
    value
        .and_then(|v| v.as_f64().or_else(|| v.as_str()?.parse().ok()))
        .filter(|n| n.is_finite())
}

fn value_string(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

/// The upstream supplies both full stint arrays and sparse patches keyed by stint number.
fn latest_stint(stints: &Value) -> Option<&Value> {
    if let Some(rows) = stints.as_array() {
        return rows.iter().rev().find(|row| row.is_object());
    }
    stints
        .as_object()?
        .iter()
        .filter(|(_, row)| row.is_object())
        .filter_map(|(index, row)| index.parse::<u32>().ok().map(|index| (index, row)))
        .max_by_key(|(index, _)| *index)
        .map(|(_, row)| row)
}

fn stint_summary(
    stints: Option<&Value>,
    tyre_series: Option<&Value>,
    timing_app: Option<&Value>,
    number: &str,
    line: &Value,
) -> (Option<String>, Option<i64>) {
    let public_topics = [
        timing_app
            .and_then(|lines| lines.get(number))
            .and_then(|line| line.get("Stints")),
        tyre_series.and_then(|stints| stints.get(number)),
    ];
    let legacy = stints
        .and_then(|value| value.get("Stints").or(Some(value)))
        .and_then(|stints| stints.get(number));
    let compound = |entry: &Value| {
        first_string(entry, &["Compound", "TyreCompound", "Tyre"])
            .map(|value| value.trim().to_ascii_uppercase())
            .filter(|value| !value.is_empty() && value != "UNKNOWN")
    };
    let current = public_topics
        .into_iter()
        .flatten()
        .filter_map(latest_stint)
        .find_map(|stint| compound(stint).map(|name| (name, stint, false)))
        .or_else(|| {
            let stint = legacy.and_then(latest_stint)?;
            Some((compound(stint)?, stint, true))
        });
    if let Some((name, stint, legacy)) = current {
        let total = value_i64(stint.get("TotalLaps")).filter(|age| *age >= 0);
        let start = value_i64(stint.get("StartLaps")).filter(|age| *age >= 0);
        let age = match (legacy, total, start) {
            (true, Some(total), Some(start)) => total.checked_add(start),
            _ => total.or(start),
        };
        return (Some(name), age);
    }
    (compound(line), None)
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
    let array_object = value.as_array().map(|rows| {
        rows.iter()
            .enumerate()
            .map(|(i, v)| (i.to_string(), v.clone()))
            .collect::<serde_json::Map<String, Value>>()
    });
    let mut messages = value
        .as_object()
        .or(array_object.as_ref())
        .map(|object| object.iter().collect::<Vec<_>>())
        .unwrap_or_default();
    messages.sort_by(|left, right| {
        let utc = |v: &Value| v.get("Utc").and_then(Value::as_str).and_then(canonical_utc);
        utc(left.1)
            .cmp(&utc(right.1))
            .then_with(|| left.0.parse::<u64>().ok().cmp(&right.0.parse::<u64>().ok()))
            .then_with(|| left.0.cmp(right.0))
    });
    messages
        .into_iter()
        .rev()
        .take(20)
        .map(|(id, value)| {
            let mut value = value.clone();
            if let Some(o) = value.as_object_mut() {
                o.insert("id".into(), Value::String(id.clone()));
                for (wire, raw) in [
                    ("message", "Message"),
                    ("category", "Category"),
                    ("flag", "Flag"),
                    ("lap", "Lap"),
                    ("driverNumber", "RacingNumber"),
                    ("sector", "Sector"),
                    ("scope", "Scope"),
                ] {
                    if let Some(v) = o.get(raw).cloned() {
                        o.insert(wire.into(), v);
                    }
                }
                if let Some(utc) = o.get("Utc").and_then(Value::as_str).and_then(canonical_utc) {
                    o.insert("Utc".into(), Value::String(utc.clone()));
                    o.insert("utc".into(), Value::String(utc));
                }
            }
            value
        })
        .collect()
}

pub fn is_patch_size_allowed(value: &Value) -> bool {
    serde_json::to_vec(value).is_ok_and(|bytes| bytes.len() <= 2 * 1024 * 1024)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn zipped(value: Value) -> Value {
        use base64::Engine;
        use std::io::Write;
        let mut writer =
            flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::fast());
        writer
            .write_all(&serde_json::to_vec(&value).unwrap())
            .unwrap();
        json!(base64::engine::general_purpose::STANDARD.encode(writer.finish().unwrap()))
    }
    #[test]
    fn test_relay_keeps_same_session_car_data_and_position_and_labels_cached_samples() {
        let mut reducer = LiveTopicReducer::default();
        let now = "2026-11-20T01:25:08Z";
        let initial = json!({"SessionInfo":{"Key":11413,"Name":"Practice 1"},
            "SessionStatus":{"Status":"Started"},"DriverList":{"63":{"RacingNumber":"63"}},
            "TimingData":{"Lines":{"63":{"Position":5}}}});
        reducer.apply_initial_snapshot(&initial, now).unwrap();
        let stale = json!(["CarData.z",{"Entries":[
            {"Utc":"2026-11-20T01:24:00Z","Cars":{"63":{"Channels":{"2":999}}}}
        ]}]);
        assert!(reducer.apply_relay_telemetry("11413", &stale, now));
        assert!(
            reducer.snapshot(now).drivers[0]
                .telemetry
                .as_ref()
                .unwrap()
                .cached
        );
        let sample = json!({
            "TimingData":{"Lines":{"63":{"Position":1}}},"SessionStatus":{"Status":"Finished"},
            "CarData.z":{"Entries":[{"Utc":"2026-11-20T01:25:07Z","Cars":{"63":{"Channels":{"2":212,"3":5,"4":45,"5":0}}}}]},
            "Position.z":{"Position":[{"Timestamp":"2026-11-20T01:25:07Z","Entries":{"63":{"X":10,"Y":20}}}]}
        });
        assert!(!reducer.apply_relay_telemetry("11412", &sample, now));
        assert!(reducer.apply_relay_telemetry("11413", &sample, "2026-11-20T01:25:09Z"));
        let projected = reducer.snapshot("2026-11-20T01:25:09Z");
        assert_eq!(projected.updated_at.as_deref(), Some(now));
        assert_eq!(projected.session_status.as_deref(), Some("Started"));
        let driver = &projected.drivers[0];
        assert_eq!(driver.position, Some(5));
        assert_eq!(driver.telemetry.as_ref().unwrap().speed, Some(212.0));
        assert!(!driver.telemetry.as_ref().unwrap().cached);
        assert_eq!(
            driver.telemetry.as_ref().unwrap().source.as_deref(),
            Some(RELAY_SOURCE)
        );
        assert_eq!(driver.location.as_ref().unwrap().x, 10.0);
        assert!(!reducer.apply_relay_telemetry("11413", &sample, "2026-11-20T01:25:10Z"));
        let expired = reducer.snapshot("2026-11-20T01:25:40Z");
        assert_eq!(
            expired.drivers[0].telemetry.as_ref().unwrap().speed,
            Some(212.0)
        );
        assert!(expired.drivers[0].telemetry.as_ref().unwrap().cached);
        assert!(expired.drivers[0].location.as_ref().unwrap().cached);
        let finished = reducer
            .apply_batch(
                &json!(["SessionStatus", {"Status":"Finished"}]),
                "2026-11-20T01:25:11Z",
            )
            .unwrap()
            .snapshot;
        assert!(finished.drivers[0].telemetry.as_ref().unwrap().cached);
        assert!(finished.drivers[0].location.as_ref().unwrap().cached);
        let mut reconnected = LiveTopicReducer::default();
        reconnected.apply_initial_snapshot(&initial, now).unwrap();
        reconnected.restore_relay_telemetry(&finished);
        assert!(!reconnected.apply_relay_telemetry("11413", &stale, now));
        reconnected
            .apply_batch(&json!(["SessionInfo", {"Key":11414}]), now)
            .unwrap();
        reconnected.restore_relay_telemetry(&finished);
        assert!(!reconnected.has_relay_telemetry());
    }

    #[test]
    fn test_current_tyre_stint_from_live_topics_and_sparse_patches() {
        let mut reducer = LiveTopicReducer::default();
        let at = "2026-11-20T01:24:00Z";
        let snapshot = json!({"DriverList":{"44":{"RacingNumber":"44"}},
            "TimingData":{"Lines":{"44":{"Sectors":[{"Value":""},{"Value":"25.000"}]}}},
            "TimingAppData":{"Lines":{"44":{"Stints":[{"Compound":"SOFT","TotalLaps":3,"StartLaps":1}]}}}});
        let initial = reducer
            .apply_initial_snapshot(&snapshot, at)
            .unwrap()
            .snapshot;
        assert_eq!(initial.drivers[0].tire_compound.as_deref(), Some("SOFT"));
        assert_eq!(initial.drivers[0].tire_age_laps, Some(3));
        assert_eq!(initial.drivers[0].sectors.as_ref().unwrap()[0].value, None);
        let patch = json!(["TimingAppData",{"Lines":{"44":{"Stints":{"1":{"Compound":"MEDIUM","TotalLaps":0}}}}}]);
        let next = reducer.apply_batch(&patch, at).unwrap().snapshot;
        assert_eq!(next.drivers[0].tire_compound.as_deref(), Some("MEDIUM"));
        assert_eq!(next.drivers[0].tire_age_laps, Some(0));
        let mut reducer = LiveTopicReducer::default();
        let series = json!({"DriverList":{"44":{"RacingNumber":"44"}},
            "TyreStintSeries":{"Stints":{"44":{"2":{"Compound":"SOFT"},"10":{"Compound":"HARD"}}}}});
        let projected = reducer
            .apply_initial_snapshot(&series, at)
            .unwrap()
            .snapshot;
        assert_eq!(projected.drivers[0].tire_compound.as_deref(), Some("HARD"));
    }

    #[test]
    fn test_session_clock_projects_running_and_paused_samples() {
        let mut reducer = LiveTopicReducer::default();
        let at = "2026-11-20T16:30:00Z";
        let clock = json!({"SessionInfo":{"Key":1,"Name":"Practice 1"},
            "ExtrapolatedClock":{"Utc":at,"Remaining":"01:00:00","Extrapolating":true}});
        let running = reducer.apply_initial_snapshot(&clock, at).unwrap().snapshot;
        assert_eq!(running.time_remaining_seconds, Some(3600));
        assert_eq!(running.clock_sample_at.as_deref(), Some(at));
        assert_eq!(running.clock_running, Some(true));
        let paused = reducer
            .apply_batch(
                &json!(["ExtrapolatedClock",{
                    "Utc":"2026-11-20T16:31:00Z","Remaining":"00:59:00.000","Extrapolating":false
                }]),
                at,
            )
            .unwrap()
            .snapshot;
        assert_eq!(paused.time_remaining_seconds, Some(3540));
        assert_eq!(paused.clock_running, Some(false));
        assert_eq!(clock_seconds("00:60:00"), None);
    }

    #[test]
    fn test_compressed_multiframe_sparse_ordering_and_session_reset() {
        let mut r = LiveTopicReducer::default();
        r.apply_batch(
            &json!({"SessionInfo":{"Key":1,"Path":"2026/old/"},"DriverList":{"44":{"FullName":"Test"}}}),
            "2026-10-10T10:00:00Z",
        )
        .unwrap();
        let p = zipped(json!({"Position":[
            {"Timestamp":"2026-10-10T10:00:00Z","Entries":{"44":{"X":10,"Y":20,"Z":9000}}},
            {"Timestamp":"2026-10-10T10:00:00.2Z","Entries":{"44":{"X":12}}},
            {"Timestamp":"2026-10-10T10:00:00.1Z","Entries":{"44":{"X":999,"Y":999}}}
        ]}));
        let car = zipped(json!({"Entries":[
            {"Utc":"2026-10-10T10:00:00Z","Cars":{"44":{"Channels":{"0":11000,"2":290,"3":8,"4":100,"5":0,"45":12}}}},
            {"Utc":"2026-10-10T10:00:00.2Z","Cars":{"44":{"Channels":{"2":300}}}},
            {"Utc":"2026-10-10T10:00:00.1Z","Cars":{"44":{"Channels":{"2":999}}}}
        ]}));
        let s = r.apply_batch(&json!({"Position.z":p,"CarData.z":car,"WeatherData":{"AirTemp":"29.4","Rainfall":"1"}}), "2026-10-10T10:00:01Z").unwrap().snapshot;
        let d = &s.drivers[0];
        assert_eq!(
            (
                d.location.as_ref().unwrap().x,
                d.location.as_ref().unwrap().y
            ),
            (12., 20.)
        );
        assert_eq!(
            d.location.as_ref().unwrap().received_at.as_deref(),
            Some("2026-10-10T10:00:01Z")
        );
        assert!(d.location.as_ref().unwrap().longitude.is_none());
        assert_eq!(d.telemetry.as_ref().unwrap().speed, Some(300.));
        assert_eq!(
            d.telemetry.as_ref().unwrap().received_at.as_deref(),
            Some("2026-10-10T10:00:01Z")
        );
        assert_eq!(d.telemetry.as_ref().unwrap().rpm, Some(11000.));
        assert_eq!(s.weather.as_ref().unwrap().rainfall, Some(true));
        let before = s.weather.unwrap().utc;
        let s = r
            .apply_batch(
                &json!(["TimingData",{"Lines":{"44":{"Position":"1"}}}]),
                "2026-10-10T10:00:30Z",
            )
            .unwrap()
            .snapshot;
        assert_eq!(s.weather.unwrap().utc, before);
        assert!(
            r.apply_batch(
                &json!(["WeatherData",{"AirTemp":"0"},"2026-10-10T09:00:00Z"]),
                "2026-10-10T10:01:00Z"
            )
            .is_none()
        );
        let s = r
            .apply_batch(&json!({"SessionInfo":{"Key":2}}), "2026-10-10T11:00:00Z")
            .unwrap()
            .snapshot;
        assert!(s.drivers.is_empty() && s.team_radio.is_empty() && s.weather.is_none());
        assert!(s.session_path.is_none());
        assert_eq!(
            canonical_utc("2026-10-10T10:00:00.2Z"),
            Some("2026-10-10T10:00:00.200000000Z".into())
        );
        assert!(canonical_utc("2026-02-31T10:00:00Z").is_none());
    }
    #[test]
    fn test_radio_and_control_ids_sort_by_utc_keep_fields_and_hide_paths() {
        let mut r = LiveTopicReducer::default();
        let s = r.apply_batch(&json!({"SessionInfo":{"Key":1,"Path":"2026/Race/"},
            "RaceControlMessages":{"Messages":{"7":{"Utc":"2026-10-10T11:00:00Z","Message":"new","Lap":5,"Sector":2,"Flag":"YELLOW","RacingNumber":"44"},"8":{"Utc":"2026-10-10T10:00:00Z","Message":"old"}}},
            "TeamRadio":{"Captures":{"0":{"Utc":"2026-10-10T11:00:00Z","RacingNumber":"44","Path":"TeamRadio/a.mp3"}}}}), "2026-10-10T11:00:00Z").unwrap().snapshot;
        assert_eq!(s.race_control.as_ref().unwrap()[0]["id"], "7");
        assert_eq!(s.race_control.as_ref().unwrap()[0]["Sector"], 2);
        assert_eq!(s.team_radio[0].id, "0");
        let wire = serde_json::to_value(&s).unwrap();
        assert!(wire.get("sessionPath").is_none() && wire["teamRadio"][0].get("path").is_none());
        let again = r
            .apply_batch(
                &json!(["TeamRadio",{"Captures":{"0":{"RacingNumber":"44"}}}]),
                "2026-10-10T11:00:01Z",
            )
            .unwrap()
            .snapshot;
        assert_eq!(again.team_radio.len(), 1);
    }

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
    fn test_stints_topic_maps_current_compound_and_age() {
        let mut reducer = LiveTopicReducer::default();
        let initial = json!({
            "DriverList": {"44": {"FullName": "Driver One"}},
            "TimingData": {"Lines": {"44": {"Line": 1}}},
            "Stints": {"Stints": {"44": [
                {"Compound": "SOFT", "TotalLaps": 12, "StartLaps": 0},
                {"Compound": "hard", "TotalLaps": 7, "StartLaps": 2}
            ]}}
        });
        let snapshot = reducer.apply_batch(&initial, "now").unwrap().snapshot;
        assert_eq!(snapshot.drivers[0].tire_compound.as_deref(), Some("HARD"));
        assert_eq!(snapshot.drivers[0].tire_age_laps, Some(9));

        let delta = json!(["Stints", {"Stints": {"44": [
            {"Compound": "SOFT", "TotalLaps": 12, "StartLaps": 0},
            {"Compound": "HARD", "TotalLaps": 7, "StartLaps": 2},
            {"Compound": "INTERMEDIATE", "TotalLaps": 3, "StartLaps": 0}
        ]}}]);
        let snapshot = reducer.apply_batch(&delta, "later").unwrap().snapshot;
        assert_eq!(
            snapshot.drivers[0].tire_compound.as_deref(),
            Some("INTERMEDIATE")
        );
        assert_eq!(snapshot.drivers[0].tire_age_laps, Some(3));
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
    fn test_position_freshness_requires_new_valid_feed_samples() {
        let mut reducer = LiveTopicReducer::default();
        let initial = zipped(
            json!({"Position":[{"Timestamp":"2026-10-10T10:00:00Z","Entries":{"44":{"X":10,"Y":20}}}]}),
        );
        let snapshot = reducer
            .apply_initial_snapshot(
                &json!({"DriverList":{"44":{"RacingNumber":"44"}},"Position.z": initial}),
                "2026-10-10T10:00:01Z",
            )
            .unwrap()
            .snapshot;
        assert_eq!(
            snapshot.drivers[0].location.as_ref().unwrap().received_at,
            None
        );

        let feed = zipped(
            json!({"Position":[{"Timestamp":"2026-10-10T10:00:00.1Z","Entries":{"44":{"X":11,"Y":21}}}]}),
        );
        let snapshot = reducer
            .apply_batch(&json!({"Position.z": feed}), "2026-10-10T10:00:02Z")
            .unwrap()
            .snapshot;
        assert_eq!(
            snapshot.drivers[0]
                .location
                .as_ref()
                .unwrap()
                .received_at
                .as_deref(),
            Some("2026-10-10T10:00:02Z")
        );
        assert_eq!(snapshot.position_diagnostics.as_ref().unwrap().decoded, 1);

        let duplicate = zipped(
            json!({"Position":[{"Timestamp":"2026-10-10T10:00:00.1Z","Entries":{"44":{"X":12,"Y":22}}}]}),
        );
        assert!(
            reducer
                .apply_batch(&json!({"Position.z": duplicate}), "2026-10-10T10:00:03Z")
                .is_none()
        );
        assert_eq!(
            reducer.snapshot("2026-10-10T10:00:03Z").drivers[0]
                .location
                .as_ref()
                .unwrap()
                .x,
            11.
        );

        let telemetry = zipped(
            json!({"Entries":[{"Utc":"2026-10-10T10:00:01Z","Cars":{"44":{"Channels":{"2":300}}}}]}),
        );
        let snapshot = reducer
            .apply_batch(&json!({"CarData.z": telemetry}), "2026-10-10T10:00:12Z")
            .unwrap()
            .snapshot;
        assert_eq!(
            snapshot.drivers[0]
                .location
                .as_ref()
                .unwrap()
                .received_at
                .as_deref(),
            Some("2026-10-10T10:00:02Z")
        );
        assert_eq!(
            snapshot.drivers[0]
                .telemetry
                .as_ref()
                .unwrap()
                .received_at
                .as_deref(),
            Some("2026-10-10T10:00:12Z")
        );

        let broken = json!({"Position.z": "not-valid-compressed-data"});
        let snapshot = reducer
            .apply_batch(&broken, "2026-10-10T10:00:05Z")
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.position_status.as_deref(), Some("decode_error"));
        assert_eq!(
            snapshot.drivers[0]
                .location
                .as_ref()
                .unwrap()
                .received_at
                .as_deref(),
            Some("2026-10-10T10:00:02Z")
        );
    }

    #[test]
    fn test_uncalibrated_positions_are_reported_without_fabricating_geography() {
        let mut reducer = LiveTopicReducer::default();
        let positions = zipped(
            json!({"Position":[{"Timestamp":"2026-10-10T10:00:00Z","Entries":{"44":{"X":10,"Y":20}}}]}),
        );
        let snapshot = reducer
            .apply_batch(
                &json!({"SessionInfo":{"Key":1,"Meeting":{"Circuit":{"Key":9}}},"DriverList":{"44":{"RacingNumber":"44"}},"Position.z":positions}),
                "2026-10-10T10:00:01Z",
            )
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.position_status.as_deref(), Some("uncalibrated"));
        assert_eq!(snapshot.position_diagnostics.as_ref().unwrap().received, 1);
        assert_eq!(
            snapshot.position_diagnostics.as_ref().unwrap().calibrated,
            0
        );
        assert!(
            snapshot.drivers[0]
                .location
                .as_ref()
                .unwrap()
                .longitude
                .is_none()
        );
    }

    #[test]
    fn test_patch_size_is_bounded() {
        assert!(is_patch_size_allowed(&json!({"ok": true})));
        assert!(!is_patch_size_allowed(
            &json!({"payload": "x".repeat(2 * 1024 * 1024)})
        ));
    }
}
