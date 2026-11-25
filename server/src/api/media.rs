use std::{
    collections::{BTreeMap, BTreeSet},
    sync::LazyLock,
};

use axum::{
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Serialize;
use sha2::{Digest, Sha256};

use super::media_bindings::Bindings;
use super::routes::{MOTORSPORT_ASSETS, MOTORSPORT_LEGACY_ASSETS};
use crate::{app_state::AppState, error::ApiError};

include!(concat!(env!("OUT_DIR"), "/native_assets.rs"));

#[derive(Serialize)]
pub(super) struct Group {
    hash: String,
    pub(super) files: BTreeMap<&'static str, String>,
}

struct Catalog {
    bindings: Bindings,
    web_bindings: Bindings,
    groups: BTreeMap<&'static str, Group>,
    blobs: BTreeMap<String, (&'static [u8], &'static str)>,
    web_index: String,
    web_etag: String,
    public_blobs: BTreeSet<String>,
}

static CATALOG: LazyLock<Catalog> = LazyLock::new(Catalog::build);

const WEB_BRAND: &[(&str, &[u8])] = &[
    (
        "apple-touch-icon.png",
        include_bytes!("../../resources/web/apple-touch-icon.png"),
    ),
    (
        "brand-mark.png",
        include_bytes!("../../resources/web/brand-mark.png"),
    ),
    (
        "icon-192.png",
        include_bytes!("../../resources/web/icon-192.png"),
    ),
    (
        "icon-512.png",
        include_bytes!("../../resources/web/icon-512.png"),
    ),
    (
        "favicon.ico",
        include_bytes!("../../resources/branding/favicon.ico"),
    ),
    (
        "favicon.png",
        include_bytes!("../../resources/branding/favicon.png"),
    ),
];

fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

impl Catalog {
    fn build() -> Self {
        let mut files = BTreeMap::<_, BTreeMap<_, _>>::new();
        let mut blobs = BTreeMap::new();
        let mut add = |group, name: &'static str, bytes: &'static [u8]| {
            let digest = hash(bytes);
            let mime = if name.ends_with(".ico") {
                "image/x-icon"
            } else {
                "image/png"
            };
            blobs.insert(digest.clone(), (bytes, mime));
            files.entry(group).or_default().insert(name, digest);
        };
        for &(path, bytes) in MOTORSPORT_ASSETS.iter().chain(NATIVE_ASSETS) {
            let (group, name) = path.rsplit_once('/').expect("grouped media path");
            add(group, name, bytes);
        }
        for &(name, bytes) in MOTORSPORT_LEGACY_ASSETS {
            add("flags", name, bytes);
        }
        for &(name, bytes) in WEB_BRAND {
            add("web-brand", name, bytes);
        }
        let groups: BTreeMap<_, _> = files
            .into_iter()
            .map(|(group, files)| {
                let hash = hash(&serde_json::to_vec(&files).expect("serialize media files"));
                (group, Group { hash, files })
            })
            .collect();
        let bindings = Bindings::build(&groups, true);
        let web_bindings = Bindings::build(&groups, false);
        let mut web_files = BTreeMap::new();
        for (group, entry) in &groups {
            if group.starts_with("native-") {
                continue;
            }
            for (name, digest) in &entry.files {
                let path = match *group {
                    "flags" | "web-brand" => (*name).to_owned(),
                    _ => format!("{group}/{name}"),
                };
                web_files.insert(path, digest);
            }
        }
        let public_blobs = web_files.values().map(|digest| (*digest).clone()).collect();
        let web_index = format!(
            "window.PITPULSE_MEDIA={};\nwindow.PITPULSE_BINDINGS={};\n",
            serde_json::to_string(&web_files).expect("serialize web media"),
            serde_json::to_string(&web_bindings).expect("serialize web bindings"),
        );
        let web_etag = format!(r#""{}""#, hash(web_index.as_bytes()));
        Self {
            bindings,
            web_bindings,
            groups,
            blobs,
            web_index,
            web_etag,
            public_blobs,
        }
    }
}

async fn season_catalog(state: &AppState) -> Result<Vec<serde_json::Value>, ApiError> {
    Ok(state
        .database
        .racing_seasons_before(10_000)
        .await?
        .into_iter()
        .rev()
        .map(|year| {
            let prefix = format!("{year}/");
            let media_kinds: Vec<_> = CATALOG
                .groups
                .keys()
                .filter_map(|group| group.strip_prefix(&prefix))
                .collect();
            serde_json::json!({
                "year": year,
                "features": crate::services::engineering::features(year),
                "mediaKinds": media_kinds
            })
        })
        .collect())
}

pub async fn seasons(
    State(state): State<AppState>,
) -> Result<axum::Json<serde_json::Value>, ApiError> {
    Ok(axum::Json(
        serde_json::json!({ "data": season_catalog(&state).await? }),
    ))
}

pub(crate) fn public_bindings() -> &'static Bindings {
    &CATALOG.web_bindings
}

pub async fn driver_media(Path((year, id)): Path<(i64, String)>) -> axum::Json<serde_json::Value> {
    axum::Json(serde_json::json!({ "data": public_bindings().driver(year, &id) }))
}

pub async fn manifest(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, ApiError> {
    Ok(manifest_response(headers, &season_catalog(&state).await?))
}

fn manifest_response(headers: HeaderMap, seasons: &[serde_json::Value]) -> Response {
    let body = serde_json::to_vec(&serde_json::json!({
        "groups": CATALOG.groups,
        "bindings": CATALOG.bindings,
        "seasons": seasons,
    }))
    .expect("serialize media manifest");
    let etag = format!("\"{}\"", hash(&body));
    if headers
        .get(header::IF_NONE_MATCH)
        .is_some_and(|value| value == etag.as_str())
    {
        return (
            StatusCode::NOT_MODIFIED,
            [
                (header::ETAG, etag),
                (header::CACHE_CONTROL, "private, no-cache".to_owned()),
            ],
        )
            .into_response();
    }
    (
        [
            (header::CONTENT_TYPE, "application/json".to_owned()),
            (header::CACHE_CONTROL, "private, no-cache".to_owned()),
            (header::ETAG, etag),
        ],
        Body::from(body),
    )
        .into_response()
}

pub async fn public_blob(Path(digest): Path<String>) -> Response {
    if !CATALOG.public_blobs.contains(&digest) {
        return missing_blob();
    }
    blob(&digest, "public, max-age=31536000, immutable")
}

pub async fn native_blob(Path(digest): Path<String>) -> Response {
    blob(&digest, "private, max-age=31536000, immutable")
}

fn missing_blob() -> Response {
    (StatusCode::NOT_FOUND, [(header::CACHE_CONTROL, "no-store")]).into_response()
}

fn blob(digest: &str, cache_control: &'static str) -> Response {
    let Some(&(bytes, mime)) = CATALOG.blobs.get(digest) else {
        return missing_blob();
    };
    (
        [
            (header::CONTENT_TYPE, mime),
            (header::CACHE_CONTROL, cache_control),
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
        ],
        Body::from(bytes),
    )
        .into_response()
}

pub async fn web_index(headers: HeaderMap) -> Response {
    let etag = CATALOG.web_etag.as_str();
    if headers
        .get(header::IF_NONE_MATCH)
        .is_some_and(|value| value == etag)
    {
        return (
            StatusCode::NOT_MODIFIED,
            [(header::ETAG, etag), (header::CACHE_CONTROL, "no-cache")],
        )
            .into_response();
    }
    ([(header::ETAG, etag)], script(&CATALOG.web_index)).into_response()
}

pub async fn worker() -> Response {
    script(include_str!("../../resources/web/media-worker.js"))
}

fn script(body: &'static str) -> Response {
    (
        [
            (header::CONTENT_TYPE, "text/javascript; charset=utf-8"),
            (header::CACHE_CONTROL, "no-cache"),
        ],
        body,
    )
        .into_response()
}

pub fn version_web_brand(template: &str) -> String {
    CATALOG.groups["web-brand"]
        .files
        .iter()
        .fold(template.to_owned(), |html, (name, digest)| {
            html.replace(
                &format!("\"/{name}?v=2\""),
                &format!("\"/media/blob/{digest}\""),
            )
            .replace(
                &format!("\"/{name}\""),
                &format!("\"/media/blob/{digest}\""),
            )
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;

    #[tokio::test]
    async fn manifest_revalidates_and_every_file_matches_its_sha256() {
        let response = manifest_response(HeaderMap::new(), &[]);
        assert_eq!(response.status(), StatusCode::OK);
        let etag = response.headers()[header::ETAG].clone();
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(etag, format!("\"{}\"", hash(&body)));

        let mut request = HeaderMap::new();
        request.insert(header::IF_NONE_MATCH, etag);
        assert_eq!(
            manifest_response(request, &[]).status(),
            StatusCode::NOT_MODIFIED
        );

        for group in CATALOG.groups.values() {
            assert_eq!(group.hash, hash(&serde_json::to_vec(&group.files).unwrap()));
            for digest in group.files.values() {
                assert_eq!(hash(CATALOG.blobs[digest].0), *digest);
            }
        }
        let digest = &CATALOG.groups["native-2026/helmet"].files["helmet-leclerc-2026.png"];
        let response = native_blob(Path(digest.clone())).await;
        assert_eq!(
            public_blob(Path(digest.clone())).await.status(),
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            response.headers()[header::CACHE_CONTROL],
            "private, max-age=31536000, immutable"
        );
        assert_eq!(
            hash(&to_bytes(response.into_body(), usize::MAX).await.unwrap()),
            *digest
        );
        assert_eq!(
            native_blob(Path("missing".into())).await.status(),
            StatusCode::NOT_FOUND
        );
    }

    #[test]
    fn missing_helmet_never_binds_to_a_portrait_or_another_season() {
        for bindings in [&CATALOG.bindings, &CATALOG.web_bindings] {
            let unresolved = bindings.driver(2025, "max_verstappen");
            assert_eq!(unresolved["helmet"]["group"], "placeholders");
            assert_eq!(unresolved["helmet"]["file"], "helmet.png");
            assert_eq!(unresolved["helmet"]["isPlaceholder"], true);
            assert_eq!(unresolved["driverPhoto"]["group"], "2025/driver-photo");
            assert_eq!(
                bindings.driver(2026, "max_verstappen")["helmet"]["isPlaceholder"],
                false
            );
        }
    }

    #[test]
    fn web_index_includes_versioned_runtime_media_and_preserves_legacy_paths() {
        assert!(CATALOG.web_index.contains("\"2026/team-logo/ferrari.png\""));
        assert!(CATALOG.web_index.contains("\"flag-jp.png\""));
        assert!(!CATALOG.web_index.contains("private-local"));
        let brand = &CATALOG.groups["web-brand"].files["brand-mark.png"];
        let html = version_web_brand(include_str!("../../resources/web/index.html"));
        assert!(html.contains(&format!("\"/media/blob/{brand}\"")));
    }
}
