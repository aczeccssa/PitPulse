//! Cookie-aware SignalR Core transport for the observed affinity-cookie upgrade failure.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportDecision {
    SignalrClientAvailable,
    WebsocketFallbackRequired,
}

use std::time::Duration;

use axum::http::{Uri, header};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::sync::{mpsc, oneshot};
use tokio_websockets::{ClientBuilder, Limits, Message};

use super::{
    client::{F1LiveError, F1LiveUpdate, normalize_feed_arguments},
    reducer::{LIVE_TOPICS, is_patch_size_allowed},
};

// The pinned SignalR client drops negotiate affinity cookies before WebSocket upgrade.
pub(super) async fn run_cookie_transport(
    base: &str,
    token: Option<&str>,
    interface: Option<&str>,
    updates: mpsc::Sender<F1LiveUpdate>,
    stop: &mut oneshot::Receiver<()>,
) -> Result<(), F1LiveError> {
    let mut negotiate_builder = reqwest::Client::builder().timeout(Duration::from_secs(20));
    if let Some(interface) = interface {
        negotiate_builder = negotiate_builder.interface(interface);
    }
    let mut negotiate = negotiate_builder
        .build()
        .map_err(|_| F1LiveError::HandshakeFailed)?
        .post(format!(
            "{}/negotiate?negotiateVersion=1",
            base.trim_end_matches('/')
        ));
    if let Some(token) = token {
        negotiate = negotiate.bearer_auth(token);
    }
    let response = negotiate
        .send()
        .await
        .map_err(|_| F1LiveError::HandshakeFailed)?;
    match response.status().as_u16() {
        401 => return Err(F1LiveError::Unauthorized),
        403 => return Err(F1LiveError::Forbidden),
        200 => {}
        _ => return Err(F1LiveError::HandshakeFailed),
    }
    let cookies = response
        .headers()
        .get_all(header::SET_COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .filter_map(|value| value.split(';').next())
        .collect::<Vec<_>>()
        .join("; ");
    let body = response
        .bytes()
        .await
        .map_err(|_| F1LiveError::HandshakeFailed)?;
    if body.len() > 64 * 1024 {
        return Err(F1LiveError::SnapshotTooLarge);
    }
    let negotiation: Value =
        serde_json::from_slice(&body).map_err(|_| F1LiveError::HandshakeFailed)?;
    let id = negotiation
        .get("connectionToken")
        .or_else(|| negotiation.get("connectionId"))
        .and_then(Value::as_str)
        .ok_or(F1LiveError::HandshakeFailed)?;
    let mut endpoint = reqwest::Url::parse(base).map_err(|_| F1LiveError::HandshakeFailed)?;
    let scheme = "wss";
    #[cfg(test)]
    let scheme = if endpoint.scheme() == "http" && endpoint.host_str() == Some("127.0.0.1") {
        "ws"
    } else {
        scheme
    };
    endpoint
        .set_scheme(scheme)
        .map_err(|_| F1LiveError::HandshakeFailed)?;
    endpoint.query_pairs_mut().append_pair("id", id);
    let uri: Uri = endpoint
        .as_str()
        .parse()
        .map_err(|_| F1LiveError::HandshakeFailed)?;
    let mut builder = ClientBuilder::from_uri(uri)
        .limits(Limits::default().max_payload_len(Some(2 * 1024 * 1024)));
    if !cookies.is_empty() {
        builder = builder
            .add_header(
                header::COOKIE,
                cookies.parse().map_err(|_| F1LiveError::HandshakeFailed)?,
            )
            .map_err(|_| F1LiveError::HandshakeFailed)?;
    }
    if let Some(token) = token {
        builder = builder
            .add_header(
                header::AUTHORIZATION,
                format!("Bearer {token}")
                    .parse()
                    .map_err(|_| F1LiveError::HandshakeFailed)?,
            )
            .map_err(|_| F1LiveError::HandshakeFailed)?;
    }
    let connect = async {
        if let Some(interface) = interface {
            let host = endpoint
                .host_str()
                .ok_or(F1LiveError::HandshakeFailed)?
                .to_string();
            let port = endpoint.port_or_known_default().unwrap_or(443);
            let transport = connect_tcp_bound(&host, port, interface).await?;
            let connector =
                tokio_websockets::Connector::new().map_err(|_| F1LiveError::HandshakeFailed)?;
            let tls = connector
                .wrap(&host, transport)
                .await
                .map_err(|_| F1LiveError::HandshakeFailed)?;
            builder
                .connect_on(tls)
                .await
                .map_err(|_| F1LiveError::HandshakeFailed)
        } else {
            builder
                .connect()
                .await
                .map_err(|_| F1LiveError::HandshakeFailed)
        }
    };
    let (mut socket, _) = tokio::time::timeout(Duration::from_secs(20), connect)
        .await
        .map_err(|_| F1LiveError::ConnectTimeout)??;
    socket
        .send(Message::text("{\"protocol\":\"json\",\"version\":1}\u{1e}"))
        .await
        .map_err(|_| F1LiveError::Disconnected)?;
    tracing::info!(
        affinity_cookies = !cookies.is_empty(),
        "F1 Live cookie-aware WebSocket opened"
    );
    let deadline = tokio::time::sleep(Duration::from_secs(12));
    tokio::pin!(deadline);
    let mut handshake = false;
    let mut subscribed = false;
    let mut saw_transport_heartbeat = false;
    let mut ping = tokio::time::interval(Duration::from_secs(15));
    let mut pending = String::new();
    loop {
        tokio::select! {
            _ = &mut *stop => { let _ = socket.close().await; return Ok(()); }
            _ = &mut deadline, if !subscribed => return Err(F1LiveError::SubscribeTimeout),
            _ = ping.tick(), if handshake => {
                socket.send(Message::text("{\"type\":6}\u{1e}")).await.map_err(|_| F1LiveError::Disconnected)?;
            }
            message = socket.next() => {
                let message = message.ok_or(F1LiveError::Disconnected)?.map_err(|_| F1LiveError::Disconnected)?;
                if message.is_close() { return Err(F1LiveError::Disconnected); }
                let Some(text) = message.as_text() else { continue; };
                pending.push_str(text);
                if pending.len() > 2 * 1024 * 1024 { return Err(F1LiveError::SnapshotTooLarge); }
                while let Some(end) = pending.find('\u{1e}') {
                    let packet = pending.drain(..=end).collect::<String>();
                    let value: Value = serde_json::from_str(packet.trim_end_matches('\u{1e}')).map_err(|_| F1LiveError::HandshakeFailed)?;
                    if !handshake {
                        if value.get("error").is_some() { return Err(F1LiveError::HandshakeFailed); }
                        handshake = true;
                        let subscribe = json!({"type":1,"invocationId":"pitpulse-subscribe","target":"Subscribe","arguments":[LIVE_TOPICS]});
                        socket.send(Message::text(format!("{subscribe}\u{1e}"))).await.map_err(|_| F1LiveError::Disconnected)?;
                        continue;
                    }
                    if value.get("type").and_then(Value::as_u64) == Some(7) { return Err(F1LiveError::Disconnected); }
                    if let Some(update) = decode_packet(&value)? {
                        if matches!(update, F1LiveUpdate::InitialSnapshot(_)) { subscribed = true; }
                        if matches!(update, F1LiveUpdate::TransportHeartbeat) && !saw_transport_heartbeat {
                            saw_transport_heartbeat = true;
                            tracing::info!("F1 Live transport heartbeat received");
                        }
                        updates.send(update).await.map_err(|_| F1LiveError::ChannelClosed)?;
                    }
                }
            }
        }
    }
}

/// Opens a TCP connection bound to a specific network interface.
///
/// On macOS this uses `IP_BOUND_IF`/`IPV6_BOUND_IF` via socket2 so the socket
/// leaves through the named physical interface instead of a transparent
/// proxy/TUN default route.
async fn connect_tcp_bound(
    host: &str,
    port: u16,
    interface: &str,
) -> Result<tokio::net::TcpStream, F1LiveError> {
    use std::num::NonZeroU32;

    use socket2::{Domain, Protocol, Socket, Type};

    let name = std::ffi::CString::new(interface).map_err(|_| F1LiveError::HandshakeFailed)?;
    let index = unsafe { libc::if_nametoindex(name.as_ptr()) };
    let index = NonZeroU32::new(index).ok_or(F1LiveError::HandshakeFailed)?;
    let addrs = tokio::net::lookup_host((host, port))
        .await
        .map_err(|_| F1LiveError::HandshakeFailed)?;
    for addr in addrs {
        let domain = if addr.is_ipv4() {
            Domain::IPV4
        } else {
            Domain::IPV6
        };
        let Ok(socket) = Socket::new(domain, Type::STREAM, Some(Protocol::TCP)) else {
            continue;
        };
        let bound = match addr {
            std::net::SocketAddr::V4(_) => socket.bind_device_by_index_v4(Some(index)),
            std::net::SocketAddr::V6(_) => socket.bind_device_by_index_v6(Some(index)),
        };
        if bound.is_err() || socket.set_nonblocking(true).is_err() {
            continue;
        }
        match socket.connect(&addr.into()) {
            Ok(()) => {}
            Err(error)
                if error.raw_os_error() == Some(libc::EINPROGRESS)
                    || error.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(_) => continue,
        }
        let std_stream: std::net::TcpStream = socket.into();
        let Ok(stream) = tokio::net::TcpStream::from_std(std_stream) else {
            continue;
        };
        let writable = tokio::time::timeout(Duration::from_secs(15), stream.writable()).await;
        if !matches!(writable, Ok(Ok(()))) {
            continue;
        }
        match stream.take_error() {
            Ok(None) => return Ok(stream),
            _ => continue,
        }
    }
    Err(F1LiveError::HandshakeFailed)
}

fn decode_packet(packet: &Value) -> Result<Option<F1LiveUpdate>, F1LiveError> {
    match packet.get("type").and_then(Value::as_u64) {
        Some(6) => Ok(Some(F1LiveUpdate::TransportHeartbeat)),
        Some(3)
            if packet.get("invocationId").and_then(Value::as_str) == Some("pitpulse-subscribe") =>
        {
            let value = packet.get("result").ok_or(F1LiveError::HandshakeFailed)?;
            if !is_patch_size_allowed(value) {
                return Err(F1LiveError::SnapshotTooLarge);
            }
            Ok(Some(F1LiveUpdate::InitialSnapshot(value.clone())))
        }
        Some(1)
            if packet
                .get("target")
                .and_then(Value::as_str)
                .is_some_and(|name| name.eq_ignore_ascii_case("feed")) =>
        {
            let Some(args) = packet.get("arguments").and_then(Value::as_array) else {
                return Ok(None);
            };
            let Some(first) = args.first() else {
                return Ok(None);
            };
            let Some(value) =
                normalize_feed_arguments(first.clone(), args.get(1).cloned(), args.get(2).cloned())
            else {
                return Ok(None);
            };
            if !is_patch_size_allowed(&value) {
                return Err(F1LiveError::SnapshotTooLarge);
            }
            Ok(Some(F1LiveUpdate::Feed(value)))
        }
        _ => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn test_cookie_transport_negotiates_subscribes_decodes_and_closes() {
        use tokio::{
            io::{AsyncReadExt, AsyncWriteExt},
            net::TcpListener,
        };
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let peer = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = Vec::new();
            while !request.ends_with(b"\r\n\r\n") {
                request.push(stream.read_u8().await.unwrap());
                assert!(request.len() < 8192);
            }
            let request = String::from_utf8(request).unwrap();
            assert!(request.starts_with("POST /signalrcore/negotiate?negotiateVersion=1"));
            assert!(
                request
                    .to_lowercase()
                    .contains("authorization: bearer test-token")
            );
            let body = r#"{"connectionToken":"local-token"}"#;
            stream.write_all(format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nSet-Cookie: affinity=test; Path=/; HttpOnly\r\nConnection: close\r\n\r\n{body}",body.len()).as_bytes()).await.unwrap();
            drop(stream);
            let (stream, _) = listener.accept().await.unwrap();
            let (request, mut socket) = tokio_websockets::ServerBuilder::new()
                .accept(stream)
                .await
                .unwrap();
            assert_eq!(request.headers()[header::COOKIE], "affinity=test");
            assert_eq!(
                request.headers()[header::AUTHORIZATION],
                "Bearer test-token"
            );
            assert_eq!(request.uri().query(), Some("id=local-token"));
            let handshake = socket.next().await.unwrap().unwrap();
            assert!(
                handshake
                    .as_text()
                    .unwrap()
                    .contains("\"protocol\":\"json\"")
            );
            socket.send(Message::text("{")).await.unwrap();
            socket.send(Message::text("}\u{1e}")).await.unwrap();
            let subscribe = socket.next().await.unwrap().unwrap();
            let subscribe: Value =
                serde_json::from_str(subscribe.as_text().unwrap().trim_end_matches('\u{1e}'))
                    .unwrap();
            assert_eq!(subscribe["target"], "Subscribe");
            assert_eq!(subscribe["arguments"][0], json!(LIVE_TOPICS));
            socket.send(Message::text("{\"type\":3,\"invocationId\":\"pitpulse-subscribe\",\"result\":{\"SessionInfo\":{}}}\u{1e}{\"type\":1,\"target\":\"feed\",\"arguments\":[\"LapCount\",{\"CurrentLap\":8},\"now\"]}\u{1e}")).await.unwrap();
            while let Some(message) = socket.next().await {
                if message.unwrap().is_close() {
                    return;
                }
            }
        });
        let (updates, mut receiver) = mpsc::channel(8);
        let (stop, mut stopped) = oneshot::channel();
        let transport = tokio::spawn(async move {
            run_cookie_transport(
                &format!("http://{address}/signalrcore"),
                Some("test-token"),
                None,
                updates,
                &mut stopped,
            )
            .await
        });
        tokio::time::timeout(Duration::from_secs(5),async {
            assert!(matches!(receiver.recv().await,Some(F1LiveUpdate::InitialSnapshot(_))));
            assert!(matches!(receiver.recv().await,Some(F1LiveUpdate::Feed(value)) if value[1]["CurrentLap"] == 8));
            stop.send(()).unwrap();
            transport.await.unwrap().unwrap();
            peer.await.unwrap();
        }).await.unwrap();
    }

    #[test]
    fn test_core_feed_initial_completion_and_unknown_packets() {
        let feed = decode_packet(
            &json!({"type":1,"target":"feed","arguments":["TimingData",{"Lines":{}},"now"]}),
        )
        .unwrap();
        assert!(
            matches!(feed, Some(F1LiveUpdate::Feed(value)) if value[0] == "TimingData" && value[1]["Lines"].is_object())
        );
        assert!(matches!(
            decode_packet(
                &json!({"type":3,"invocationId":"pitpulse-subscribe","result":{"Heartbeat":{}}})
            )
            .unwrap(),
            Some(F1LiveUpdate::InitialSnapshot(_))
        ));
        assert!(matches!(
            decode_packet(&json!({"type":6})).unwrap(),
            Some(F1LiveUpdate::TransportHeartbeat)
        ));
        assert!(
            decode_packet(&json!({"type":1,"target":"feed","arguments":["TimingData"]}))
                .unwrap()
                .is_none()
        );
        assert!(
            decode_packet(&json!({"type":3,"invocationId":"pitpulse-subscribe","error":"denied"}))
                .is_err()
        );
    }
}
