use anyhow::Context;
use axum::{Router, middleware, routing::get};
use tokio::net::TcpListener;

use crate::{
    api::{
        middleware::require_bearer_token,
        routes::{self, build_router},
        web_auth::require_web_access,
    },
    app_state::AppState,
};

pub fn router(state: AppState) -> Router {
    let protected_router = build_router(state.clone()).route_layer(middleware::from_fn_with_state(
        state.clone(),
        require_bearer_token,
    ));

    // The dashboard is part of the service rather than a public document, so
    // when a token is required the shell is served only to a browser that
    // bootstrapped a session through `/?token=...`. Icons stay reachable
    // without credentials because browsers and the OS fetch them that way;
    // they contain no data.
    let shell = Router::new()
        .route("/", get(routes::index))
        .route("/app.css", get(routes::app_css))
        .route("/app.js", get(routes::app_js))
        .route("/theme.js", get(routes::theme_js))
        .route("/manifest.webmanifest", get(routes::manifest))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            require_web_access,
        ));

    let public_icons = Router::new()
        .route("/apple-touch-icon.png", get(routes::apple_touch_icon))
        .route("/brand-mark.png", get(routes::brand_mark))
        .route("/icon-192.png", get(routes::icon_192))
        .route("/icon-512.png", get(routes::icon_512))
        .route("/favicon.ico", get(routes::favicon_ico))
        .route("/favicon.png", get(routes::favicon_png))
        .route("/motorsport/{file}", get(routes::motorsport_asset));

    protected_router
        .merge(shell)
        .merge(public_icons)
        .with_state(state)
}

pub async fn serve(state: AppState) -> anyhow::Result<()> {
    let listener = TcpListener::bind(state.config.server.bind)
        .await
        .with_context(|| format!("failed to bind {}", state.config.server.bind))?;

    tracing::info!(addr = %state.config.server.bind, "HTTP server ready");
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
