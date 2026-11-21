use super::resources::ResourceCache;
use crate::{api::dto::Meta, domain::calendar::Meeting, scheduler::parse_utc_seconds};
use serde_json::{Value, json};
use std::time::Duration;
#[derive(Clone)]
pub struct WeatherProvider {
    cache: ResourceCache,
    observations: ResourceCache,
}
impl WeatherProvider {
    pub fn new(agent: &str) -> Self {
        Self {
            cache: ResourceCache::new(agent, Duration::from_millis(200)),
            // OpenF1 allows fewer requests per second than Open-Meteo.
            observations: ResourceCache::new(agent, Duration::from_millis(400)),
        }
    }
    pub async fn forecast(
        &self,
        meeting: &Meeting,
        now: &str,
    ) -> Result<(Value, Meta), &'static str> {
        let current = parse_utc_seconds(now).ok_or("invalid_time")?;
        let end = meeting
            .sessions
            .iter()
            .filter_map(|s| {
                let start = parse_utc_seconds(&s.start_time)?;
                Some(
                    s.end_time
                        .as_deref()
                        .and_then(parse_utc_seconds)
                        .unwrap_or(start + 7200),
                )
            })
            .max()
            .unwrap_or(parse_utc_seconds(&meeting.end_date).ok_or("invalid_time")?);
        let start = parse_utc_seconds(&meeting.start_date).ok_or("invalid_time")?;
        if end < current {
            return Ok((json!({"status":"past_event","hours":[]}), Meta::empty()));
        }
        if start >= current.div_euclid(86400) * 86400 + 16 * 86400 {
            return Ok((
                json!({"status":"outside_forecast_window","hours":[]}),
                Meta::empty(),
            ));
        }
        let circuit = meeting.circuit.as_ref().ok_or("location_unavailable")?;
        let lat = circuit["latitude"].as_f64().ok_or("location_unavailable")?;
        let lon = circuit["longitude"]
            .as_f64()
            .ok_or("location_unavailable")?;
        if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
            return Err("location_unavailable");
        }
        let url = format!(
            "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,visibility&forecast_days=16&timezone=GMT&timeformat=unixtime&wind_speed_unit=ms"
        );
        let r = self
            .cache
            .get(&url, now, Duration::from_secs(1800), 2 * 1024 * 1024)
            .await?;
        let value = r.json()?;
        let hours = forecast_hours(&value, start, end)?;
        Ok((
            json!({"status":if hours.is_empty() { "outside_forecast_window" } else { "available" },"hours":hours}),
            r.meta("open-meteo"),
        ))
    }

    /// Measured weather for a completed session. Observations do not change
    /// after the session ends, so they are cached for the rest of the weekend
    /// instead of being re-fetched for every client.
    pub async fn observations(
        &self,
        session_key: i64,
        session_id: &str,
        now: &str,
    ) -> Result<(Vec<Value>, Meta), &'static str> {
        let url = format!("https://api.openf1.org/v1/weather?session_key={session_key}");
        let r = self
            .observations
            .get(&url, now, Duration::from_secs(6 * 60 * 60), 4 * 1024 * 1024)
            .await?;
        let value = r.json()?;
        let rows = value.as_array().ok_or("upstream_invalid_payload")?;
        let hours = rows
            .iter()
            .filter_map(|sample| observed_hour(sample, session_id))
            .collect();
        Ok((hours, r.meta("openf1")))
    }
}

fn observed_hour(sample: &Value, session_id: &str) -> Option<Value> {
    let utc = crate::services::analysis::normalize_date(sample["date"].as_str()?)?;
    Some(json!({
        "utc": utc,
        "sessionId": session_id,
        "airTemp": sample["air_temperature"],
        "trackTemp": sample["track_temperature"],
        "humidity": sample["humidity"],
        "rainfall": sample["rainfall"],
        "windSpeed": sample["wind_speed"],
        "windDirection": sample["wind_direction"],
        "pressure": sample["pressure"]
    }))
}

fn forecast_hours(value: &Value, start: i64, end: i64) -> Result<Vec<Value>, &'static str> {
    let times = value
        .pointer("/hourly/time")
        .and_then(Value::as_array)
        .ok_or("upstream_invalid_payload")?;
    let mut hours = Vec::new();
    for (i, time) in times.iter().enumerate() {
        let Some(time) = time.as_i64() else {
            continue;
        };
        if time < start - 3600 || time > end + 3600 {
            continue;
        }
        let mut hour = json!({"utc":crate::scheduler::add_seconds("1970-01-01T00:00:00Z", time)});
        for (key, field) in [
            ("temperature_2m", "airTemp"),
            ("precipitation_probability", "precipitationProbability"),
            ("precipitation", "precipitation"),
            ("weather_code", "weatherCode"),
            ("wind_speed_10m", "windSpeed"),
            ("visibility", "visibilityMeters"),
        ] {
            hour[field] = value
                .pointer(&format!("/hourly/{key}"))
                .and_then(|a| a.get(i))
                .filter(|v| v.is_number())
                .cloned()
                .unwrap_or(Value::Null);
        }
        hours.push(hour);
    }
    Ok(hours)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_forecast_normalizes_utc_and_preserves_missing_values() {
        let start = parse_utc_seconds("2026-10-11T00:00:00Z").unwrap();
        let hours = forecast_hours(
            &json!({"hourly":{"time":[start-7200,start,start+3600,start+10800],"temperature_2m":[20,29,null,21],"precipitation_probability":[0,60],"visibility":[null,10000]}}),
            start,
            start + 3600,
        ).unwrap();
        assert_eq!(hours.len(), 2);
        assert_eq!(hours[0]["utc"], "2026-10-11T00:00:00Z");
        assert_eq!(hours[0]["airTemp"], 29);
        assert_eq!(hours[0]["visibilityMeters"], 10000);
        assert!(hours[1]["visibilityMeters"].is_null());
        assert!(hours[1]["airTemp"].is_null() && hours[1]["precipitationProbability"].is_null());
        assert!(forecast_hours(&json!({}), start, start).is_err());
    }
    #[test]
    fn test_observed_weather_maps_openf1_samples_with_session_id() {
        let hour = observed_hour(
            &json!({"date":"2026-11-21T17:01:02.500Z","air_temperature":27.5,"track_temperature":42,"humidity":31,"rainfall":0,"wind_speed":2.1,"wind_direction":180,"pressure":1012.4}),
            "2026:22:qualifying",
        )
        .unwrap();
        assert_eq!(hour["utc"], "2026-11-21T17:01:02Z");
        assert_eq!(hour["sessionId"], "2026:22:qualifying");
        assert_eq!(hour["airTemp"], 27.5);
        assert_eq!(hour["rainfall"], 0);
        assert!(observed_hour(&json!({"date":"invalid"}), "session").is_none());
    }

    #[tokio::test]
    async fn test_past_and_distant_events_never_request_current_weather() {
        let raw: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-alpha-2026-australia.json"
        ))
        .unwrap();
        let meeting = crate::providers::jolpica::decode_alpha_schedule(&raw)
            .unwrap()
            .remove(0);
        let p = WeatherProvider::new("test");
        assert_eq!(
            p.forecast(&meeting, "2026-10-11T00:00:00Z")
                .await
                .unwrap()
                .0["status"],
            "past_event"
        );
        assert_eq!(
            p.forecast(&meeting, "2026-02-01T00:00:00Z")
                .await
                .unwrap()
                .0["status"],
            "outside_forecast_window"
        );
        assert!(matches!(
            p.forecast(&meeting, "2026-03-05T00:00:00Z").await,
            Err("location_unavailable")
        ));
    }
}
