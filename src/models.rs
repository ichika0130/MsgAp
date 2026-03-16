use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ── Inbound ──────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct CreateMessageRequest {
    pub content: String,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Deserialize)]
pub struct NearbyQuery {
    pub latitude: f64,
    pub longitude: f64,
    /// Search radius in metres (e.g. 500.0)
    pub radius: f64,
}

// ── Outbound ─────────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct CreateMessageResponse {
    pub id: Uuid,
    pub content: String,
    pub latitude: f64,
    pub longitude: f64,
    pub likes: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct NearbyMessageResponse {
    pub id: Uuid,
    /// `None` when the caller is further than `READABLE_RADIUS_METRES` away.
    pub content: Option<String>,
    pub latitude: f64,
    pub longitude: f64,
    pub likes: i32,
    /// `true` only when the caller is within 50 m of the message.
    pub is_readable: bool,
    /// Exact distance from the caller in metres.
    pub distance_meters: f64,
    pub created_at: DateTime<Utc>,
}
