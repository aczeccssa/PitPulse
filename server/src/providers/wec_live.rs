//! FIA WEC live timing through the public Griiip "Second Screen" JSON API.
//!
//! `livetiming.fiawec.com` is a Griiip client; its data service is
//! `insights.griiip.com`. This adapter polls the public session bootstrap
//! document and maps the multi-class, time-based WEC session into the shared
//! `LiveSnapshot`. The endpoint is public but undocumented, so the supervisor
//! keeps the feature opt-in and degrades to `stale`/`disconnected`.

use std::collections::HashMap;
use std::time::Duration;

use serde_json::{Value, json};

use crate::domain::live::{
    LiveDriver, LiveSector, LiveSnapshot, LiveSourceMode, LiveStatus, LiveWeather,
};

pub const DEFAULT_BASE_URL: &str = "https://insights.griiip.com";
pub const WEC_SERIES_ID: i64 = 10;

#[derive(Debug, thiserror::Error)]
pub enum WecLiveError {
    #[error("WEC live request failed: {0}")]
    Request(#[from] reqwest::Error),
    #[error("WEC live upstream returned HTTP {0}")]
    Status(u16),
    #[error("WEC live payload is missing {0}")]
    Shape(&'static str),
}

impl WecLiveError {
    pub const fn is_gone(&self) -> bool {
        matches!(self, Self::Status(404 | 204))
    }
}

#[derive(Clone)]
pub struct WecLiveClient {
    client: reqwest::Client,
    base_url: String,
}

impl WecLiveClient {
    pub fn new(user_agent: &str) -> Result<Self, WecLiveError> {
        let client = reqwest::Client::builder()
            .user_agent(user_agent)
            .timeout(Duration::from_secs(15))
            .build()?;
        Ok(Self {
            client,
            base_url: DEFAULT_BASE_URL.to_string(),
        })
    }

    pub fn with_base_url(mut self, base_url: impl Into<String>) -> Self {
        self.base_url = base_url.into().trim_end_matches('/').to_string();
        self
    }

    pub async fn bootstrap(&self, session_id: i64) -> Result<Value, WecLiveError> {
        self.get(&format!(
            "/api/v2/public/live/session/{session_id}/bootstrap"
        ))
        .await
    }

    /// Pick the session of the currently live WEC event. `now` is an RFC 3339
    /// UTC timestamp; the schedule uses whole seconds and UTC, so the first 19
    /// characters compare chronologically.
    pub async fn discover_session(
        &self,
        series_id: i64,
        now: &str,
    ) -> Result<Option<i64>, WecLiveError> {
        let value = self
            .get(&format!("/meta/series/{series_id}/active-season-calendar"))
            .await?;
        Ok(discover_session_in(&value, series_id, now))
    }

    async fn get(&self, path: &str) -> Result<Value, WecLiveError> {
        let response = self
            .client
            .get(format!("{}{path}", self.base_url))
            .send()
            .await?;
        let status = response.status();
        if !status.is_success() {
            return Err(WecLiveError::Status(status.as_u16()));
        }
        Ok(response.json().await?)
    }
}

pub fn discover_session_in(value: &Value, series_id: i64, now: &str) -> Option<i64> {
    let now = time_key(now);
    for entry in value.as_array()? {
        if entry
            .get("seriesId")
            .and_then(Value::as_i64)
            .is_some_and(|id| id != series_id)
        {
            continue;
        }
        let events = entry.get("events").and_then(Value::as_array)?;
        let mut containing = Vec::new();
        let mut live_race = None;
        for event in events {
            if text(event, "status") != Some("Live") {
                continue;
            }
            for session in array(event, "sessions") {
                let Some(id) = integer(session, "id") else {
                    continue;
                };
                let is_race = text(session, "sessionType") == Some("Race");
                let start = text(session, "startTime").map(time_key);
                let end = text(session, "endTime").map(time_key);
                if start.as_deref().is_some_and(|start| start <= now.as_str())
                    && end.as_deref().is_some_and(|end| now.as_str() <= end)
                {
                    containing.push((is_race, id));
                }
                if is_race {
                    live_race.get_or_insert(id);
                }
            }
        }
        if let Some(id) = containing
            .iter()
            .find(|(is_race, _)| *is_race)
            .map(|(_, id)| *id)
            .or_else(|| containing.first().map(|(_, id)| *id))
        {
            return Some(id);
        }
        if let Some(id) = live_race {
            return Some(id);
        }
    }
    None
}

pub fn snapshot_from_bootstrap(
    value: &Value,
    received_at: &str,
) -> Result<LiveSnapshot, WecLiveError> {
    let session_info = value
        .get("sessionInfo")
        .ok_or(WecLiveError::Shape("sessionInfo"))?;
    let participants = value
        .get("participants")
        .and_then(Value::as_array)
        .ok_or(WecLiveError::Shape("participants"))?;
    let track_details = value.get("trackDetails").unwrap_or(&Value::Null);
    let session_clock = value.get("sessionClock").unwrap_or(&Value::Null);
    let limit = value.get("sessionLengthLimit").unwrap_or(&Value::Null);

    let ranks = map_by_pid(value, "ranks");
    let gaps = map_by_pid(value, "gaps");
    let best_laps = map_by_pid(value, "bestLaps");
    let statuses = map_by_pid(value, "runningStatuses");
    let locations = map_by_pid(value, "carLocations");
    let tires = map_by_pid(value, "tires");
    let energy = energy_by_pid(value);

    let (lap_count, last_laps) = lap_summary(value);
    let sector_count = integer(track_details, "sectorsCount")
        .filter(|count| *count > 0)
        .unwrap_or(3)
        .clamp(1, 6) as usize;

    let mut drivers = Vec::with_capacity(participants.len());
    for participant in participants {
        let Some(pid) = integer(participant, "pid") else {
            continue;
        };
        if ranks
            .get(&pid)
            .and_then(|rank| rank.get("isDeleted"))
            .and_then(Value::as_bool)
            == Some(true)
        {
            continue;
        }
        let rank = ranks.get(&pid);
        let gap = gaps.get(&pid);
        let position = rank.and_then(|value| integer(value, "overallPosition"));
        let class_position = rank.and_then(|value| integer(value, "position"));
        let class_id = text(participant, "classId").filter(|value| !value.is_empty());
        let car_number = text(participant, "carNumber").unwrap_or("").to_string();
        let (tire_compound, tire_age_laps) = tire_summary(tires.get(&pid).copied());

        drivers.push(LiveDriver {
            number: car_number.clone(),
            name: current_driver_name(participant),
            team: text(participant, "teamName")
                .or_else(|| text(participant, "displayName"))
                .map(str::to_string),
            position,
            gap: gap_text(position, gap),
            interval: interval_text(gap),
            lap_count: last_laps.get(&pid).map(|(lap, _)| *lap),
            last_lap: last_laps
                .get(&pid)
                .and_then(|(_, millis)| *millis)
                .map(format_lap_time),
            best_lap: best_laps
                .get(&pid)
                .and_then(|value| integer(value, "lapTimeMillis"))
                .map(format_lap_time),
            sectors: Some(sectors_for(value, pid, sector_count)),
            in_pit: locations
                .get(&pid)
                .and_then(|value| text(value, "carLocation"))
                .map(|location| location.to_ascii_lowercase().contains("pit")),
            retired: statuses
                .get(&pid)
                .and_then(|value| text(value, "status"))
                .and_then(is_retired),
            class_id: class_id.map(str::to_string),
            class_name: class_id.map(class_name),
            class_position,
            manufacturer: text(participant, "manufacturer").map(str::to_string),
            tire_compound,
            tire_age_laps,
            energy_percent: energy.get(&pid).copied(),
            ..LiveDriver::default()
        });
    }
    drivers.sort_by(|left, right| {
        left.position
            .unwrap_or(i64::MAX)
            .cmp(&right.position.unwrap_or(i64::MAX))
            .then_with(|| left.number.cmp(&right.number))
    });

    let start = text(session_clock, "startTime");
    let now = text(session_clock, "tsNow").or(Some(received_at));
    let elapsed_seconds = start
        .and_then(parse_rfc3339_seconds)
        .zip(now.and_then(parse_rfc3339_seconds))
        .map(|(start, now)| (now - start).max(0));
    let time_limit = integer(limit, "timeLimitSeconds").filter(|seconds| *seconds > 0);
    let time_remaining_seconds = time_limit
        .zip(elapsed_seconds)
        .map(|(limit, elapsed)| (limit - elapsed).max(0));
    let is_time_based = text(limit, "sessionLengthType")
        .is_some_and(|kind| kind.eq_ignore_ascii_case("timeonly"))
        || time_limit.is_some();
    let total_laps = integer(limit, "lapsLimit").filter(|laps| *laps > 0);

    let chequered = value
        .get("chequeredFlags")
        .and_then(Value::as_array)
        .is_some_and(|flags| !flags.is_empty())
        || session_info
            .get("hasSeenChequered")
            .and_then(Value::as_bool)
            == Some(true);
    let session_status = if chequered {
        "finished"
    } else if elapsed_seconds.is_some_and(|elapsed| elapsed > 0) {
        "started"
    } else {
        "scheduled"
    };

    let country_code =
        text(track_details, "country").and_then(crate::domain::country::country_code);
    let circuit_key = integer(session_info, "trackId")
        .zip(integer(track_details, "trackConfigId"))
        .map(|(track, config)| format!("wec:{track}:{config}"));

    Ok(LiveSnapshot {
        series: Some("wec".to_string()),
        circuit_key,
        circuit_name: text(session_info, "trackName").map(str::to_string),
        weather: live_weather(value, received_at),
        team_radio: Vec::new(),
        session_path: None,
        state_version: 0,
        session_id: integer(session_clock, "sid")
            .or_else(|| integer(session_info, "eventId"))
            .map(|session| format!("wec:{session}")),
        session_name: text(session_info, "sessionName")
            .or_else(|| text(session_info, "sessionType"))
            .map(str::to_string),
        meeting_name: text(session_info, "eventName").map(str::to_string),
        country_code,
        source_status: LiveStatus::Connected,
        source_mode: LiveSourceMode::Live,
        status_reason: None,
        session_type: text(session_info, "sessionType").map(str::to_string),
        session_status: Some(session_status.to_string()),
        track_status: current_flag(value).map(str::to_string),
        lap_count,
        total_laps,
        updated_at: Some(received_at.to_string()),
        last_transport_at: Some(received_at.to_string()),
        drivers,
        race_control: Some(race_log(value)),
        position_status: None,
        position_diagnostics: None,
        time_remaining_seconds,
        elapsed_seconds,
        is_time_based: Some(is_time_based),
        ..LiveSnapshot::default()
    })
}

fn map_by_pid<'a>(value: &'a Value, key: &str) -> HashMap<i64, &'a Value> {
    array(value, key)
        .iter()
        .filter_map(|item| integer(item, "pid").map(|pid| (pid, item)))
        .collect()
}

fn energy_by_pid(value: &Value) -> HashMap<i64, f64> {
    value
        .get("carsEnergyTanks")
        .and_then(|tanks| tanks.get("items"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| {
                    let pid = integer(item, "pid")?;
                    let energy = number(item, "e")?.clamp(0.0, 100.0);
                    Some((pid, energy))
                })
                .collect()
        })
        .unwrap_or_default()
}

fn tire_summary(entry: Option<&Value>) -> (Option<String>, Option<i64>) {
    let Some(tires) = entry
        .and_then(|entry| entry.get("tires"))
        .and_then(Value::as_array)
    else {
        return (None, None);
    };
    let front_left = tires
        .iter()
        .find(|tire| text(tire, "id") == Some("frontLeft"));
    let compound = front_left
        .and_then(|tire| text(tire, "compound"))
        .or_else(|| tires.iter().find_map(|tire| text(tire, "compound")))
        .filter(|compound| !compound.is_empty())
        .map(|compound| compound.to_ascii_uppercase());
    let age = front_left
        .and_then(|tire| integer(tire, "ageInLaps"))
        .or_else(|| {
            tires
                .iter()
                .filter_map(|tire| integer(tire, "ageInLaps"))
                .max()
        })
        .filter(|age| *age >= 0);
    (compound, age)
}

type LapTimes = HashMap<i64, (i64, Option<i64>)>;

fn lap_summary(value: &Value) -> (Option<i64>, LapTimes) {
    let mut leader_lap = None;
    let mut last_laps: LapTimes = HashMap::new();
    for lap in array(value, "laps") {
        let Some(pid) = integer(lap, "pid") else {
            continue;
        };
        let Some(number) = integer(lap, "lapNumber") else {
            continue;
        };
        leader_lap = Some(leader_lap.map_or(number, |current: i64| current.max(number)));
        let millis = integer(lap, "lapTimeMillis").filter(|millis| *millis > 0);
        match last_laps.get(&pid) {
            Some((previous, _)) if *previous > number => {}
            Some((previous, previous_millis)) if *previous == number => {
                if previous_millis.is_none() {
                    last_laps.insert(pid, (number, millis));
                }
            }
            _ => {
                last_laps.insert(pid, (number, millis));
            }
        }
    }
    (leader_lap, last_laps)
}

fn sectors_for(value: &Value, pid: i64, count: usize) -> Vec<LiveSector> {
    let current = value
        .get("currentLapSectors")
        .and_then(|sectors| sectors.get(pid.to_string()))
        .and_then(Value::as_array)
        .filter(|sectors| sectors.len() >= count);
    let latest_lap = array(value, "sectors")
        .iter()
        .filter(|sector| integer(sector, "pid") == Some(pid))
        .filter_map(|sector| integer(sector, "lapNumber"))
        .max();
    let latest = latest_lap.map(|lap| {
        array(value, "sectors")
            .iter()
            .filter(|sector| {
                integer(sector, "pid") == Some(pid) && integer(sector, "lapNumber") == Some(lap)
            })
            .collect::<Vec<_>>()
    });
    let sectors: Option<Vec<&Value>> = current.map(|sectors| sectors.iter().collect()).or(latest);
    (0..count)
        .map(|index| {
            let sector = sectors.as_ref().and_then(|sectors| {
                sectors
                    .iter()
                    .find(|sector| integer(sector, "sectorNumber") == Some(index as i64 + 1))
            });
            let color = sector
                .and_then(|sector| text(sector, "color"))
                .unwrap_or("")
                .to_ascii_uppercase();
            LiveSector {
                value: sector
                    .and_then(|sector| integer(sector, "sectorTimeMillis"))
                    .filter(|millis| *millis > 0)
                    .map(format_lap_time),
                personal_fastest: (color == "GREEN").then_some(true),
                overall_fastest: (color == "PURPLE").then_some(true),
                segments: Vec::new(),
            }
        })
        .collect()
}

fn current_driver_name(participant: &Value) -> Option<String> {
    let current = text(participant, "currentDriverId");
    let drivers = array(participant, "drivers");
    let driver = current
        .and_then(|current| {
            drivers.iter().find(|driver| {
                text(driver, "externalDriverID") == Some(current)
                    || integer(driver, "driverId").is_some_and(|id| id.to_string() == current)
            })
        })
        .or_else(|| drivers.first());
    driver
        .and_then(driver_name)
        .or_else(|| driver_name(participant))
}

fn driver_name(value: &Value) -> Option<String> {
    if let Some(display) = text(value, "displayName").filter(|name| !name.is_empty()) {
        return Some(display.to_string());
    }
    let first = text(value, "firstname").unwrap_or("");
    let last = text(value, "lastname").unwrap_or("");
    let name = format!("{first} {last}").trim().to_string();
    (!name.is_empty()).then_some(name)
}

fn gap_text(position: Option<i64>, gap: Option<&&Value>) -> Option<String> {
    if position == Some(1) {
        return Some("LEADER".to_string());
    }
    let gap = gap?;
    let laps = integer(gap, "gapToFirstLaps").unwrap_or(0);
    if laps > 0 {
        return Some(if laps == 1 {
            "+1 Lap".to_string()
        } else {
            format!("+{laps} Laps")
        });
    }
    integer(gap, "gapToFirstMillis")
        .filter(|millis| *millis >= 0)
        .map(format_gap)
}

fn interval_text(gap: Option<&&Value>) -> Option<String> {
    let gap = gap?;
    let laps = integer(gap, "gapToAheadLaps").unwrap_or(0);
    if laps > 0 {
        return Some(if laps == 1 {
            "+1 Lap".to_string()
        } else {
            format!("+{laps} Laps")
        });
    }
    integer(gap, "gapToAheadMillis")
        .filter(|millis| *millis >= 0)
        .map(format_gap)
}

fn format_gap(millis: i64) -> String {
    format!("+{:.3}", millis.max(0) as f64 / 1000.0)
}

fn format_lap_time(millis: i64) -> String {
    let millis = millis.max(0);
    if millis >= 60_000 {
        format!(
            "{}:{:06.3}",
            millis / 60_000,
            (millis % 60_000) as f64 / 1000.0
        )
    } else {
        format!("{:.3}", millis as f64 / 1000.0)
    }
}

fn is_retired(status: &str) -> Option<bool> {
    let status = status.to_ascii_lowercase();
    if status.contains("running") {
        Some(false)
    } else if status.contains("retir")
        || status.contains("stopped")
        || status.contains("withdraw")
        || status.contains("out")
    {
        Some(true)
    } else {
        None
    }
}

fn live_weather(value: &Value, received_at: &str) -> Option<LiveWeather> {
    let weather = value.get("weather").filter(|weather| weather.is_object())?;
    Some(LiveWeather {
        utc: text(weather, "ts").unwrap_or(received_at).to_string(),
        air_temp: number(weather, "temperature"),
        track_temp: number(weather, "trackTemperature"),
        humidity: number(weather, "humidity"),
        pressure: number(weather, "pressure"),
        wind_speed: number(weather, "windSpeedKph"),
        wind_direction: None,
        rainfall: text(weather, "sky").map(|sky| sky.to_ascii_lowercase().contains("rain")),
    })
}

fn current_flag(value: &Value) -> Option<&str> {
    if value
        .get("chequeredFlags")
        .and_then(Value::as_array)
        .is_some_and(|flags| !flags.is_empty())
    {
        return Some("Chequered");
    }
    // raceFlags is the full history for the session; the last flag is the current one.
    array(value, "raceFlags")
        .iter()
        .filter_map(|item| {
            let flag = text(item, "flag")?;
            let millis = integer(item, "elapsedTimeMillis").unwrap_or(-1);
            let ts = text(item, "ts").unwrap_or_default();
            Some((millis, ts, flag))
        })
        .max_by_key(|(millis, ts, _)| (*millis, ts.to_string()))
        .map(|(_, _, flag)| flag)
}

fn race_log(value: &Value) -> Vec<Value> {
    value
        .get("raceLogFirstPage")
        .and_then(|page| page.get("items"))
        .and_then(Value::as_array)
        .map(|items| items.iter().filter_map(race_log_item).take(40).collect())
        .unwrap_or_default()
}

fn race_log_item(item: &Value) -> Option<Value> {
    let kind = text(item, "type")?;
    let car = text(item, "carNumber").unwrap_or("");
    let message = text(item, "text")
        .map(str::to_string)
        .or_else(|| match kind {
            "RaceFlag" => text(item, "flag").map(|flag| format!("Flag: {flag}")),
            "PitIn" => Some(format!("Car {car} in pit")),
            "PitOut" => Some(format!("Car {car} pit out")),
            "ParticipantRetired" => Some(format!("Car {car} retired")),
            "DriverSwap" => Some(format!("Car {car} driver change")),
            "FastestLap" => integer(item, "lapTimeMillis")
                .map(|millis| format!("Fastest lap car {car} {}", format_lap_time(millis))),
            "Overtake" => Some(format!("Car {car} overtake")),
            "Battle" => Some(format!("Car {car} battle")),
            "SignificantTimeLoss" => Some(format!("Car {car} significant time loss")),
            "AttackMode" => Some(format!("Car {car} attack mode")),
            "WeatherUpdate" => Some("Weather update".to_string()),
            _ => Some(kind.to_string()),
        })?;
    Some(json!({
        "Id": text(item, "raceLogItemId").unwrap_or(""),
        "Utc": text(item, "ts").unwrap_or(""),
        "Category": kind,
        "Flag": text(item, "flag"),
        "Lap": integer(item, "lapNumber"),
        "RacingNumber": (!car.is_empty()).then_some(car),
        "Message": message,
    }))
}

fn text<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn integer(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(Value::as_i64)
}

fn number(value: &Value, key: &str) -> Option<f64> {
    value.get(key).and_then(Value::as_f64)
}

fn array<'a>(value: &'a Value, key: &str) -> &'a [Value] {
    value
        .get(key)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[])
}

fn class_name(class_id: &str) -> String {
    match class_id.to_ascii_uppercase().as_str() {
        "HYPERCAR" => "Hypercar".to_string(),
        other => other.to_string(),
    }
}

fn time_key(value: &str) -> String {
    value.get(0..19).unwrap_or(value).to_string()
}

fn parse_rfc3339_seconds(value: &str) -> Option<i64> {
    if value.len() < 19 {
        return None;
    }
    let year: i64 = value.get(0..4)?.parse().ok()?;
    let month: u32 = value.get(5..7)?.parse().ok()?;
    let day: u32 = value.get(8..10)?.parse().ok()?;
    let hour: i64 = value.get(11..13)?.parse().ok()?;
    let minute: i64 = value.get(14..16)?.parse().ok()?;
    let second: i64 = value.get(17..19)?.parse().ok()?;
    let offset = match value.as_bytes().get(19) {
        Some(b'+') | Some(b'-') => {
            let sign = if value.as_bytes().get(19) == Some(&b'-') {
                -1
            } else {
                1
            };
            let hours: i64 = value.get(20..22)?.parse().ok()?;
            let minutes: i64 = value.get(23..25)?.parse().ok()?;
            sign * (hours * 3600 + minutes * 60)
        }
        _ => 0,
    };
    Some(days_from_civil(year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset)
}

const fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let month_prime = (month as i64 + 9) % 12;
    let day_of_year = (153 * month_prime + 2) / 5 + day as i64 - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bootstrap() -> Value {
        json!({
            "sessionInfo": {
                "seriesName": "FIA World Endurance Championship",
                "eventName": "FIA WEC - 6 Hours of Monza",
                "sessionName": "Race",
                "sessionType": "Race",
                "trackName": "Monza Circuit",
                "trackId": 22,
                "eventId": 999
            },
            "sessionClock": {
                "startTime": "2026-11-08T10:00:00Z",
                "tsNow": "2026-11-08T11:00:00Z"
            },
            "sessionLengthLimit": {
                "sessionLengthType": "TimeOnly",
                "timeLimitSeconds": 21600,
                "lapsLimit": -1
            },
            "trackDetails": {
                "trackConfigId": 15,
                "sectorsCount": 3,
                "country": "Italy"
            },
            "participants": [
                {
                    "pid": 1,
                    "carNumber": "7",
                    "classId": "HYPERCAR",
                    "teamName": "Toyota Gazoo Racing",
                    "manufacturer": "Toyota GR010 Hybrid",
                    "currentDriverId": "11",
                    "drivers": [
                        { "driverId": 101, "externalDriverID": "11", "displayName": "Kamui Kobayashi" },
                        { "driverId": 102, "externalDriverID": "12", "displayName": "Mike Conway" }
                    ]
                },
                {
                    "pid": 2,
                    "carNumber": "46",
                    "classId": "LMGT3",
                    "teamName": "Team WRT",
                    "currentDriverId": "21",
                    "drivers": [
                        { "driverId": 201, "externalDriverID": "21", "displayName": "Valentino Rossi" }
                    ]
                }
            ],
            "ranks": [
                { "pid": 1, "overallPosition": 1, "position": 1, "isDeleted": false },
                { "pid": 2, "overallPosition": 18, "position": 4, "isDeleted": false }
            ],
            "gaps": [
                { "pid": 1, "gapToFirstLaps": 0, "gapToFirstMillis": 0 },
                { "pid": 2, "gapToFirstLaps": 1, "gapToAheadMillis": 2400 }
            ],
            "laps": [
                { "pid": 1, "lapNumber": 12, "lapTimeMillis": 98629 },
                { "pid": 2, "lapNumber": 11, "lapTimeMillis": 101002 }
            ],
            "bestLaps": [
                { "pid": 1, "lapTimeMillis": 97500 },
                { "pid": 2, "lapTimeMillis": 100500 }
            ],
            "sectors": [
                { "pid": 1, "lapNumber": 12, "sectorNumber": 1, "sectorTimeMillis": 30702, "color": "PURPLE" },
                { "pid": 1, "lapNumber": 12, "sectorNumber": 2, "sectorTimeMillis": 35000, "color": "GREEN" },
                { "pid": 1, "lapNumber": 12, "sectorNumber": 3, "sectorTimeMillis": 32927, "color": "Gray" }
            ],
            "currentLapSectors": {
                "1": [
                    { "pid": 1, "lapNumber": 13, "sectorNumber": 1, "sectorTimeMillis": 31000, "color": "Gray" }
                ]
            },
            "runningStatuses": [
                { "pid": 1, "status": "Running" },
                { "pid": 2, "status": "Retired" }
            ],
            "carLocations": [
                { "pid": 1, "carLocation": "Track" },
                { "pid": 2, "carLocation": "Pit" }
            ],
            "tires": [
                { "pid": 1, "tires": [
                    { "id": "frontLeft", "compound": "MEDIUM", "ageInLaps": 8 },
                    { "id": "frontRight", "compound": "MEDIUM", "ageInLaps": 8 },
                    { "id": "rearLeft", "compound": "MEDIUM", "ageInLaps": 8 },
                    { "id": "rearRight", "compound": "MEDIUM", "ageInLaps": 8 }
                ] },
                { "pid": 2, "tires": [
                    { "id": "frontLeft", "compound": "soft", "ageInLaps": 12 },
                    { "id": "frontRight", "compound": "soft", "ageInLaps": 12 }
                ] }
            ],
            "carsEnergyTanks": {
                "items": [
                    { "pid": 1, "e": 82 },
                    { "pid": 2, "e": 41.5 }
                ]
            },
            "weather": {
                "temperature": 11.5,
                "trackTemperature": 12.5,
                "humidity": 71,
                "pressure": 1006.2,
                "windSpeedKph": 7,
                "sky": "Clear",
                "ts": "2026-11-08T10:59:00Z"
            },
            "raceFlags": [
                { "flag": "Green", "ts": "2026-11-08T10:01:00Z" },
                { "flag": "FCY", "ts": "2026-11-08T10:30:00Z" }
            ],
            "raceLogFirstPage": {
                "items": [
                    {
                        "type": "RCMessage",
                        "text": "CAR 88 CAR 34 - UNDER INVESTIGATION",
                        "raceLogItemId": "17",
                        "lapNumber": 8,
                        "ts": "2026-11-08T10:20:00Z",
                        "carNumber": ""
                    }
                ]
            }
        })
    }

    #[test]
    fn test_bootstrap_maps_classes_time_limit_and_race_log() {
        let snapshot = snapshot_from_bootstrap(&bootstrap(), "2026-11-08T11:00:01Z").unwrap();
        assert_eq!(snapshot.series.as_deref(), Some("wec"));
        assert_eq!(snapshot.session_name.as_deref(), Some("Race"));
        assert_eq!(snapshot.circuit_name.as_deref(), Some("Monza Circuit"));
        assert_eq!(snapshot.country_code.as_deref(), Some("IT"));
        assert_eq!(snapshot.lap_count, Some(12));
        assert_eq!(snapshot.time_remaining_seconds, Some(18_000));
        assert_eq!(snapshot.is_time_based, Some(true));
        assert_eq!(snapshot.track_status.as_deref(), Some("FCY"));
        assert_eq!(snapshot.session_status.as_deref(), Some("started"));
        assert_eq!(snapshot.drivers.len(), 2);

        let leader = &snapshot.drivers[0];
        assert_eq!(leader.number, "7");
        assert_eq!(leader.name.as_deref(), Some("Kamui Kobayashi"));
        assert_eq!(leader.position, Some(1));
        assert_eq!(leader.gap.as_deref(), Some("LEADER"));
        assert_eq!(leader.class_id.as_deref(), Some("HYPERCAR"));
        assert_eq!(leader.class_position, Some(1));
        assert_eq!(leader.last_lap.as_deref(), Some("1:38.629"));
        assert_eq!(leader.best_lap.as_deref(), Some("1:37.500"));
        assert_eq!(leader.manufacturer.as_deref(), Some("Toyota GR010 Hybrid"));
        assert_eq!(leader.tire_compound.as_deref(), Some("MEDIUM"));
        assert_eq!(leader.tire_age_laps, Some(8));
        assert_eq!(leader.energy_percent, Some(82.0));
        assert_eq!(
            leader.sectors.as_ref().unwrap()[0].value.as_deref(),
            Some("30.702")
        );
        assert_eq!(
            leader.sectors.as_ref().unwrap()[0].overall_fastest,
            Some(true)
        );
        assert_eq!(
            leader.sectors.as_ref().unwrap()[1].personal_fastest,
            Some(true)
        );
        assert_eq!(
            leader.sectors.as_ref().unwrap()[2].value.as_deref(),
            Some("32.927")
        );

        let gt = &snapshot.drivers[1];
        assert_eq!(gt.name.as_deref(), Some("Valentino Rossi"));
        assert_eq!(gt.gap.as_deref(), Some("+1 Lap"));
        assert_eq!(gt.class_id.as_deref(), Some("LMGT3"));
        assert_eq!(gt.class_position, Some(4));
        assert_eq!(gt.in_pit, Some(true));
        assert_eq!(gt.retired, Some(true));
        assert_eq!(gt.tire_compound.as_deref(), Some("SOFT"));
        assert_eq!(gt.tire_age_laps, Some(12));
        assert_eq!(gt.energy_percent, Some(41.5));

        let weather = snapshot.weather.as_ref().unwrap();
        assert_eq!(weather.air_temp, Some(11.5));
        assert_eq!(weather.track_temp, Some(12.5));
        assert_eq!(weather.rainfall, Some(false));

        let messages = snapshot.race_control.as_ref().unwrap();
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0]["Category"], "RCMessage");
        assert_eq!(
            messages[0]["Message"],
            "CAR 88 CAR 34 - UNDER INVESTIGATION"
        );
    }

    #[test]
    fn test_partial_current_lap_keeps_the_last_completed_sector_set() {
        let mut value = bootstrap();
        value["currentLapSectors"] = json!({});
        let snapshot = snapshot_from_bootstrap(&value, "2026-11-08T11:00:01Z").unwrap();
        let sectors = snapshot.drivers[0].sectors.as_ref().unwrap();
        assert_eq!(sectors[0].overall_fastest, Some(true));
        assert_eq!(sectors[1].personal_fastest, Some(true));
        assert_eq!(sectors[2].value.as_deref(), Some("32.927"));
    }

    #[test]
    fn test_current_flag_uses_the_latest_entry_not_the_most_severe_history() {
        let value = json!({
            "raceFlags": [
                { "flag": "SafetyCar", "ts": "2026-11-08T12:15:43Z", "elapsedTimeMillis": 8130000 },
                { "flag": "Green", "ts": "2026-11-08T12:28:11Z", "elapsedTimeMillis": 8870000 },
                { "flag": "Yellow", "ts": "2026-11-08T12:37:16Z", "elapsedTimeMillis": 9410000 }
            ]
        });
        assert_eq!(current_flag(&value), Some("Yellow"));
        let mut value = value;
        value["raceFlags"] = json!([
            { "flag": "SafetyCar", "ts": "2026-11-08T12:15:43Z" },
            { "flag": "Green", "ts": "2026-11-08T12:28:11Z" }
        ]);
        assert_eq!(current_flag(&value), Some("Green"));
    }

    #[test]
    fn test_discover_prefers_a_live_race_over_practice() {
        let value = json!([{
            "seriesId": 10,
            "events": [{
                "status": "Live",
                "sessions": [
                    { "id": 10, "sessionType": "Practice", "startTime": "2026-11-08T09:00:00Z", "endTime": "2026-11-08T10:00:00Z" },
                    { "id": 11, "sessionType": "Race", "startTime": "2026-11-08T10:00:00Z", "endTime": "2026-11-08T16:00:00Z" }
                ]
            }]
        }]);
        assert_eq!(
            discover_session_in(&value, WEC_SERIES_ID, "2026-11-08T11:00:00Z"),
            Some(11)
        );
        assert_eq!(
            discover_session_in(&value, WEC_SERIES_ID, "2026-11-08T08:00:00Z"),
            Some(11)
        );
        assert_eq!(
            discover_session_in(&value, 99, "2026-11-08T11:00:00Z"),
            None
        );
    }

    #[test]
    fn test_rfc3339_parser_handles_offsets_and_remaining_time() {
        assert_eq!(parse_rfc3339_seconds("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(
            parse_rfc3339_seconds("2026-11-08T11:00:00+00:00"),
            parse_rfc3339_seconds("2026-11-08T11:00:00Z")
        );
        assert_eq!(
            parse_rfc3339_seconds("2026-11-08T12:00:00+01:00"),
            parse_rfc3339_seconds("2026-11-08T11:00:00Z")
        );
    }
}
