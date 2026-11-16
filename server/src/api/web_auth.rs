//! Browser access to the dashboard shell.
//!
//! The dashboard is part of the service, not a public document. When
//! `security.require_token` is set, the shell and its assets require a browser
//! session that the server issues itself: opening `/?token=<token>` exchanges
//! the deployment token for a derived, read-only cookie. The page never sees
//! or stores the bearer token, and the cookie is a different value that only
//! admits `GET`/`HEAD` requests, so it cannot be replayed against write
//! endpoints. Bearer callers keep full API access.

use axum::{
    body::Body,
    extract::{Request, State},
    http::{HeaderMap, HeaderValue, Method, StatusCode, header},
    middleware::Next,
    response::Response,
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use sha2::{Digest, Sha256};

use crate::app_state::AppState;

pub const WEB_COOKIE: &str = "pitpulse_web";

/// Domain separation for the derived cookie, so its value is never equal to
/// the deployment token even for short tokens.
const SESSION_LABEL: &[u8] = b"pitpulse-web-session-v1";
const SESSION_MAX_AGE_SECS: u64 = 30 * 24 * 60 * 60;
const SHELL_QUERY_TOKEN: &str = "token";

const UNAUTHORIZED_CSP: &str = "default-src 'none'; style-src 'unsafe-inline'; \
base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/// The cookie value for a token. Deterministic, so a restart does not log
/// browsers out, but distinct from the bearer token in both value and rights.
pub fn session_value(token: &str) -> String {
    URL_SAFE_NO_PAD.encode(hmac_sha256(token.as_bytes(), SESSION_LABEL))
}

pub fn bearer_matches(headers: &HeaderMap, expected: &str) -> bool {
    headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .is_some_and(|provided| constant_time_eq(provided.as_bytes(), expected.as_bytes()))
}

pub fn cookie_matches(headers: &HeaderMap, expected: &str) -> bool {
    cookie_value(headers, WEB_COOKIE).is_some_and(|provided| {
        constant_time_eq(provided.as_bytes(), session_value(expected).as_bytes())
    })
}

/// Guards the dashboard shell and its assets. Browser requests must carry the
/// session cookie, which is only issued by the `?token=` bootstrap below.
pub async fn require_web_access(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    if !state.config.security.require_token {
        return next.run(request).await;
    }

    let expected = state
        .config
        .security
        .token
        .as_ref()
        .expect("token checked during config validation");

    // Bootstrap: the operator opens a link carrying the deployment token and
    // the server issues its own browser credential. The token is compared in
    // constant time and never echoed back into the page.
    if request.uri().path() == "/"
        && let Some(provided) = query_value(request.uri().query(), SHELL_QUERY_TOKEN)
    {
        if constant_time_eq(provided.as_bytes(), expected.as_bytes()) {
            return bootstrap_response(expected, request.headers());
        }
        return unauthorized_page("访问令牌无效。请使用最新的访问链接重新打开。");
    }

    if bearer_matches(request.headers(), expected) || cookie_matches(request.headers(), expected) {
        return next.run(request).await;
    }

    unauthorized_page("此实例的仪表盘只对持有访问链接的浏览器开放。")
}

/// `303 See Other` back to `/` with the session cookie set. The token is
/// dropped from the URL the browser keeps, and no proxy may cache either hop.
fn bootstrap_response(token: &str, headers: &HeaderMap) -> Response {
    let cookie = session_cookie(token, forwarded_https(headers));
    let mut response = Response::new(Body::empty());
    *response.status_mut() = StatusCode::SEE_OTHER;
    let response_headers = response.headers_mut();
    response_headers.insert(header::LOCATION, HeaderValue::from_static("/"));
    response_headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response_headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("no-referrer"),
    );
    match HeaderValue::from_str(&cookie) {
        Ok(value) => {
            response_headers.insert(header::SET_COOKIE, value);
        }
        Err(_) => return unauthorized_page("无法建立浏览器会话，请稍后重试。"),
    }
    response
}

/// HttpOnly keeps the session away from page scripts. Lax (not Strict) so a
/// link opened from another app still arrives with the cookie on the 303 back
/// to `/`; the cookie cannot write, so the cross-site GET permission is safe.
fn session_cookie(token: &str, secure: bool) -> String {
    let value = session_value(token);
    let mut cookie = format!(
        "{WEB_COOKIE}={value}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_MAX_AGE_SECS}"
    );
    if secure {
        cookie.push_str("; Secure");
    }
    cookie
}

fn unauthorized_page(message: &str) -> Response {
    let body = format!(
        "<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\
<meta name=\"robots\" content=\"noindex\"><title>PitPulse · 需要访问权限</title>\
<style>body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#0e0e10;\
color:#f2f2f4;font:15px/1.7 -apple-system,BlinkMacSystemFont,\"PingFang SC\",sans-serif}}\
main{{max-width:32rem;padding:32px 24px}}h1{{margin:0 0 12px;font-size:20px}}p{{margin:0;color:#9a9aa2}}</style>\
</head><body><main><h1>需要访问权限</h1><p>{message}</p></main></body></html>"
    );
    let mut response = Response::new(Body::from(body));
    *response.status_mut() = StatusCode::UNAUTHORIZED;
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/html; charset=utf-8"),
    );
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("no-referrer"),
    );
    headers.insert(
        header::HeaderName::from_static("content-security-policy"),
        HeaderValue::from_static(UNAUTHORIZED_CSP),
    );
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::HeaderName::from_static("x-robots-tag"),
        HeaderValue::from_static("noindex"),
    );
    response
}

/// The web session is read-only. This is checked by the API middleware so a
/// stolen cookie cannot trigger refreshes or any other mutation.
pub fn allows_read_only(method: &Method) -> bool {
    matches!(*method, Method::GET | Method::HEAD)
}

fn cookie_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get_all(header::COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(';'))
        .filter_map(|pair| pair.trim().split_once('='))
        .find(|(key, _)| key.trim() == name)
        .map(|(_, value)| value.trim().to_string())
}

fn forwarded_https(headers: &HeaderMap) -> bool {
    let proto = headers
        .get("x-forwarded-proto")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.split(',').next().unwrap_or("").trim());
    if let Some(proto) = proto {
        return proto.eq_ignore_ascii_case("https");
    }
    headers
        .get("x-forwarded-ssl")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.trim().eq_ignore_ascii_case("on"))
}

fn query_value(query: Option<&str>, name: &str) -> Option<String> {
    query?
        .split('&')
        .filter_map(|pair| pair.split_once('='))
        .find(|(key, _)| *key == name)
        .map(|(_, value)| percent_decode(value))
}

fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            // `+` is a literal in a bootstrap link, not form-encoded space;
            // tokens may contain it, so only `%XX` escapes are decoded.
            b'%' if index + 2 < bytes.len() => {
                match (hex_digit(bytes[index + 1]), hex_digit(bytes[index + 2])) {
                    (Some(high), Some(low)) => {
                        out.push(high << 4 | low);
                        index += 3;
                    }
                    _ => {
                        out.push(b'%');
                        index += 1;
                    }
                }
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_digit(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter()
        .zip(b.iter())
        .fold(0u8, |diff, (left, right)| diff | (left ^ right))
        == 0
}

fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    const BLOCK_SIZE: usize = 64;

    let mut key_block = [0u8; BLOCK_SIZE];
    if key.len() > BLOCK_SIZE {
        key_block[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }

    let mut inner_pad = [0x36u8; BLOCK_SIZE];
    let mut outer_pad = [0x5cu8; BLOCK_SIZE];
    for index in 0..BLOCK_SIZE {
        inner_pad[index] ^= key_block[index];
        outer_pad[index] ^= key_block[index];
    }

    let mut inner = Sha256::new();
    inner.update(inner_pad);
    inner.update(message);
    let inner_digest = inner.finalize();

    let mut outer = Sha256::new();
    outer.update(outer_pad);
    outer.update(inner_digest);
    outer.finalize().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_matches_rfc4231_case_2() {
        let digest = hmac_sha256(b"Jefe", b"what do ya want for nothing?");
        let hex: String = digest.iter().map(|byte| format!("{byte:02x}")).collect();
        assert_eq!(
            hex,
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    #[test]
    fn session_value_is_derived_and_token_distinct() {
        let value = session_value("deployment-token");
        assert_ne!(value, "deployment-token");
        assert!(!value.contains("deployment"));
        assert_eq!(value, session_value("deployment-token"));
        assert_ne!(value, session_value("other-token"));
        // base64url of 32 bytes without padding
        assert_eq!(value.len(), 43);
    }

    #[test]
    fn cookie_lookup_handles_multiple_headers_and_spacing() {
        let mut headers = HeaderMap::new();
        headers.append(header::COOKIE, HeaderValue::from_static("a=1; b=2"));
        headers.append(
            header::COOKIE,
            HeaderValue::from_static(" pitpulse_web = value ; c=3"),
        );
        assert_eq!(
            cookie_value(&headers, WEB_COOKIE),
            Some("value".to_string())
        );
    }

    #[test]
    fn cookie_matches_only_the_derived_value() {
        let token = "deployment-token";
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            HeaderValue::from_str(&format!("{WEB_COOKIE}={}", session_value(token))).unwrap(),
        );
        assert!(cookie_matches(&headers, token));
        assert!(!cookie_matches(&headers, "other-token"));
        assert!(!cookie_matches(&HeaderMap::new(), token));
    }

    #[test]
    fn bootstrap_query_is_percent_decoded() {
        assert_eq!(
            query_value(Some("a=1&token=abc%2Bdef&z=2"), SHELL_QUERY_TOKEN),
            Some("abc+def".to_string())
        );
        assert_eq!(
            query_value(Some("token=abc+def"), SHELL_QUERY_TOKEN),
            Some("abc+def".to_string())
        );
        assert_eq!(query_value(Some("x=1"), SHELL_QUERY_TOKEN), None);
        assert_eq!(query_value(None, SHELL_QUERY_TOKEN), None);
    }

    #[test]
    fn web_session_cookie_is_read_only_and_hardened() {
        let cookie = session_cookie("deployment-token", true);
        assert!(cookie.starts_with(&format!("{WEB_COOKIE}=")));
        assert!(cookie.contains("; Path=/"));
        assert!(cookie.contains("; HttpOnly"));
        // Lax, not Strict: a link opened from another app is a cross-site
        // top-level navigation, and Strict would drop the cookie on the 303
        // back to `/` so the shell would refuse its own session.
        assert!(cookie.contains("; SameSite=Lax"));
        assert!(cookie.contains("; Max-Age="));
        assert!(cookie.ends_with("; Secure"));
        assert!(!session_cookie("deployment-token", false).contains("Secure"));
    }

    #[test]
    fn only_get_and_head_are_read_only() {
        assert!(allows_read_only(&Method::GET));
        assert!(allows_read_only(&Method::HEAD));
        assert!(!allows_read_only(&Method::POST));
        assert!(!allows_read_only(&Method::DELETE));
    }
}
