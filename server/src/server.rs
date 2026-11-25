use anyhow::Context;
use axum::{Router, middleware, routing::get};
use tokio::net::TcpListener;

use crate::{
    api::{
        media,
        middleware::require_bearer_token,
        routes::{self, build_router},
        web_auth::issue_web_session,
    },
    app_state::AppState,
};

pub fn router(state: AppState) -> Router {
    let protected_router = build_router(state.clone()).route_layer(middleware::from_fn_with_state(
        state.clone(),
        require_bearer_token,
    ));

    // The dashboard shell is served directly at `/` and `/index`, and every
    // unknown browser path falls back to it so client-side routes such as
    // `/home` work as links. Serving the shell issues the derived read-only
    // session cookie the page uses for its data calls; writes still need the
    // bearer token.
    let shell = Router::new()
        .route("/", get(routes::index))
        .route("/index", get(routes::index))
        .route("/app.css", get(routes::app_css))
        .route("/app.js", get(routes::app_js))
        .route("/theme.js", get(routes::theme_js))
        .route("/manifest.webmanifest", get(routes::manifest))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            issue_web_session,
        ));

    let public_routes = Router::new()
        .route("/health", get(routes::health_public))
        .route("/apple-touch-icon.png", get(routes::apple_touch_icon))
        .route("/brand-mark.png", get(routes::brand_mark))
        .route("/icon-192.png", get(routes::icon_192))
        .route("/icon-512.png", get(routes::icon_512))
        .route("/favicon.ico", get(routes::favicon_ico))
        .route("/favicon.png", get(routes::favicon_png))
        .route("/motorsport/{*path}", get(routes::motorsport_asset))
        .route("/media/blob/{digest}", get(media::public_blob))
        .route("/media/web.js", get(media::web_index))
        .route("/media-worker.js", get(media::worker));

    protected_router
        .merge(shell)
        .merge(public_routes)
        .fallback(routes::spa_fallback)
        .with_state(state)
}

pub async fn serve(state: AppState) -> anyhow::Result<()> {
    let listener = TcpListener::bind(state.config.server.bind)
        .await
        .with_context(|| format!("failed to bind {}", state.config.server.bind))?;

    tracing::info!(addr = %state.config.server.bind, "HTTP server ready");
    tokio::spawn(crate::api::dashboard_cache::warm(state.clone()));
    axum::serve(listener, router(state))
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("HTTP server failed")?;
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::info!("shutdown signal received");
}
