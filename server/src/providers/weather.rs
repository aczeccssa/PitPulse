use super::resources::ResourceCache;
use crate::{api::dto::Meta, domain::calendar::Meeting, scheduler::parse_utc_seconds};
use serde_json::{Value, json};
use std::time::Duration;
#[derive(Clone)]
pub struct WeatherProvider {
    cache: ResourceCache,
}
impl WeatherProvider {
    pub fn new(agent: &str) -> Self {
        Self {
            cache: ResourceCache::new(agent, Duration::from_millis(200)),
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
            "https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m&forecast_days=16&timezone=GMT&timeformat=unixtime&wind_speed_unit=ms"
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
        let hours=forecast_hours(&json!({"hourly":{"time":[start-7200,start,start+3600,start+10800],"temperature_2m":[20,29,null,21],"precipitation_probability":[0,60]}}),start,start+3600).unwrap();
        assert_eq!(hours.len(), 2);
        assert_eq!(hours[0]["utc"], "2026-10-11T00:00:00Z");
        assert_eq!(hours[0]["airTemp"], 29);
        assert!(hours[1]["airTemp"].is_null() && hours[1]["precipitationProbability"].is_null());
        assert!(forecast_hours(&json!({}), start, start).is_err());
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
