use super::resources::{Resource, ResourceCache};
use crate::api::dto::Meta;
use serde_json::{Value, json};
use std::time::Duration;
#[derive(Clone)]
pub struct RadarProvider {
    cache: ResourceCache,
}
fn past_frames(raw: &Value, now: &str) -> Result<Vec<Value>, &'static str> {
    let now = crate::scheduler::parse_utc_seconds(now).ok_or("invalid_time")?;
    let rows = raw
        .pointer("/radar/past")
        .and_then(Value::as_array)
        .ok_or("upstream_invalid_payload")?;
    let mut frames = rows
        .iter()
        .filter_map(|v| {
            let time = v["time"].as_u64()?;
            let path = v["path"].as_str()?;
            let suffix = path.strip_prefix("/v2/radar/")?;
            // Current upstream paths may be hashes instead of timestamps.
            (time <= now as u64
                && time >= now.saturating_sub(7500) as u64
                && !suffix.is_empty()
                && suffix.len() <= 64
                && suffix
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b)))
            .then_some((time, path))
        })
        .collect::<Vec<_>>();
    frames.sort_unstable_by_key(|(time, _)| *time);
    frames.dedup_by_key(|(time, _)| *time);
    Ok(frames.into_iter().map(|(time,path)| json!({"id":time,"utc":crate::scheduler::add_seconds("1970-01-01T00:00:00Z",time as i64),"path":path})).collect())
}

impl RadarProvider {
    pub fn new(agent: &str) -> Self {
        Self {
            cache: ResourceCache::new(agent, Duration::from_millis(650)),
        }
    }
    pub async fn frames(&self, now: &str) -> Result<(Value, Meta), &'static str> {
        let resource = self
            .cache
            .get(
                "https://api.rainviewer.com/public/weather-maps.json",
                now,
                Duration::from_secs(300),
                1024 * 1024,
            )
            .await?;
        let raw = resource.json()?;
        let frames = past_frames(&raw, now)?;
        Ok((
            json!({"frames":frames,"maxZoom":7,"source":"RainViewer"}),
            resource.meta("rainviewer"),
        ))
    }
    pub async fn tile(
        &self,
        frame: u64,
        z: u32,
        x: u32,
        y: u32,
        coverage: bool,
        now: &str,
    ) -> Result<Resource, &'static str> {
        if z > 7 || x >= 1 << z || y >= 1 << z {
            return Err("invalid_tile");
        }
        let path = if coverage {
            "coverage/0".to_string()
        } else {
            let (metadata, _) = self.frames(now).await?;
            let selected = metadata["frames"]
                .as_array()
                .and_then(|rows| rows.iter().find(|r| r["id"].as_u64() == Some(frame)))
                .ok_or("unknown_radar_frame")?;
            selected["path"]
                .as_str()
                .and_then(|p| p.strip_prefix("/v2/"))
                .ok_or("upstream_invalid_payload")?
                .to_string()
        };
        let color = if coverage { 0 } else { 2 };
        let url =
            format!("https://tilecache.rainviewer.com/v2/{path}/256/{z}/{x}/{y}/{color}/0_0.png");
        let r = self
            .cache
            .get(&url, now, Duration::from_secs(600), 1024 * 1024)
            .await?;
        if !r.content_type.starts_with("image/") {
            return Err("upstream_invalid_payload");
        }
        Ok(r)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_only_recent_past_frames_and_no_coverage_are_not_future_weather() {
        let now = "2026-10-11T00:00:00Z";
        let epoch = crate::scheduler::parse_utc_seconds(now).unwrap() as u64;
        let raw = json!({"radar":{"past":[
            {"time":epoch-600,"path":format!("/v2/radar/{}",epoch-600)},
            {"time":epoch+600,"path":format!("/v2/radar/{}",epoch+600)},
            {"time":epoch-9000,"path":format!("/v2/radar/{}",epoch-9000)},
            {"time":epoch,"path":"https://evil/tile"}],"nowcast":[{"time":epoch+1}]}});
        assert_eq!(
            past_frames(&raw, now).unwrap(),
            vec![
                json!({"id":epoch-600,"utc":"2026-10-10T23:50:00Z","path":format!("/v2/radar/{}",epoch-600)})
            ]
        );
        assert!(
            past_frames(&json!({"radar":{"past":[]}}), now)
                .unwrap()
                .is_empty()
        );
    }
    #[test]
    fn test_hashed_frame_paths_are_used_and_remote_traversal_is_rejected() {
        let now = "2026-10-11T00:00:00Z";
        let epoch = crate::scheduler::parse_utc_seconds(now).unwrap() as u64;
        let rows = past_frames(
            &json!({"radar":{"past":[{"time":epoch,"path":"/v2/radar/08703e84d1f3"}]}}),
            now,
        )
        .unwrap();
        assert_eq!(rows[0]["path"], "/v2/radar/08703e84d1f3");
        for path in [
            "/v2/radar/../x",
            "https://evil/x",
            "/v2/radar/%2e%2e",
            "/v2/radar/x?a=1",
        ] {
            assert!(
                past_frames(&json!({"radar":{"past":[{"time":epoch,"path":path}]}}), now)
                    .unwrap()
                    .is_empty()
            );
        }
    }
    #[tokio::test]
    async fn test_out_of_range_tiles_are_rejected_before_upstream() {
        let p = RadarProvider::new("test");
        for (z, x, y) in [(8, 0, 0), (7, 128, 0), (0, 0, 1)] {
            assert!(matches!(
                p.tile(0, z, x, y, false, "2026-10-11T00:00:00Z").await,
                Err("invalid_tile")
            ));
        }
    }
}
