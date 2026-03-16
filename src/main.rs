mod config;
mod error;
mod handlers;
mod models;

use axum::{
    routing::{get, post},
    Router,
};
use sqlx::postgres::PgPoolOptions;
use tower_http::trace::TraceLayer;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load .env before anything else (fails silently if missing)
    let _ = dotenvy::dotenv();

    // Load flavour-text / error strings from disk once at startup
    config::init("strings.toml");

    // Tracing — default to INFO, override via RUST_LOG env var
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Database connection pool
    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set");

    let pool = PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await?;

    info!("Running database migrations…");
    sqlx::migrate!("./migrations").run(&pool).await?;
    info!("Migrations complete.");

    // Router
    let app = Router::new()
        .route("/v1/messages",        post(handlers::create_message))
        .route("/v1/messages/nearby", get(handlers::get_nearby_messages))
        .with_state(pool)
        .layer(TraceLayer::new_for_http());

    let addr = "0.0.0.0:3000";
    info!("Listening on http://{addr}");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
