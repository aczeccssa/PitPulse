use super::resources::{Resource, ResourceCache};
use std::time::Duration;
#[derive(Clone)]
pub struct RadioProvider {
    cache: ResourceCache,
}
impl RadioProvider {
    pub fn new(agent: &str) -> Self {
        Self {
            cache: ResourceCache::new(agent, Duration::ZERO),
        }
    }
    pub async fn audio(
        &self,
        session: &str,
        capture: &str,
        now: &str,
    ) -> Result<Resource, &'static str> {
        let url = audio_url(session, capture).ok_or("invalid_audio_path")?;
        let resource = self
            .cache
            .get(&url, now, Duration::ZERO, 16 * 1024 * 1024)
            .await?;
        if !resource.content_type.starts_with("audio/")
            && resource.content_type != "application/octet-stream"
        {
            return Err("upstream_invalid_audio");
        }
        Ok(resource)
    }
}
pub fn audio_url(session: &str, capture: &str) -> Option<String> {
    fn safe(value: &str) -> bool {
        !value.is_empty()
            && !value.starts_with('/')
            && value.split('/').all(|p| p != ".." && p != ".")
            && value
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"/_-.".contains(&b))
    }
    if !safe(session)
        || !safe(capture)
        || !capture.ends_with(".mp3")
        || !capture.starts_with("TeamRadio/")
    {
        return None;
    }
    Some(format!(
        "https://livetiming.formula1.com/static/{}/{capture}",
        session.trim_end_matches('/')
    ))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_audio_path_never_accepts_remote_or_encoded_traversal() {
        for path in [
            "../x.mp3",
            "TeamRadio/%2e%2e/x.mp3",
            "//evil/x.mp3",
            "https://evil/x.mp3",
            "TeamRadio/../../x.mp3",
            "TeamRadio/x.mp3?x=1",
        ] {
            assert!(audio_url("2026/Race/", path).is_none());
        }
        assert_eq!(
            audio_url("2026/Race/", "TeamRadio/1.mp3").unwrap(),
            "https://livetiming.formula1.com/static/2026/Race/TeamRadio/1.mp3"
        );
    }
}
