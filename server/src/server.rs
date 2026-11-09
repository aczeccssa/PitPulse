use anyhow::Context;
use axum::{Router, middleware, routing::get};
use tokio::net::TcpListener;

use crate::{
    api::middleware::require_bearer_token, api::routes::build_router, app_state::AppState,
};

pub fn router(state: AppState) -> Router {
    let protected_router = build_router(state.clone()).route_layer(middleware::from_fn_with_state(
        state.clone(),
        require_bearer_token,
    ));

    // Browsers request icons without the API's Bearer header. Keep only these
    // static brand assets outside the authentication layer.
    protected_router
        .route("/favicon.ico", get(crate::api::routes::favicon_ico))
        .route("/favicon.png", get(crate::api::routes::favicon_png))
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
