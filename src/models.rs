use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{AppError, ValidationKind};

// ── Inbound ──────────────────────────────────────────────────────────────────

const MAX_CONTENT_LEN: usize = 500;
const MAX_RADIUS_METRES: f64 = 5_000.0;

#[derive(Debug, Deserialize)]
pub struct CreateMessageRequest {
    pub content: String,
    pub latitude: f64,
    pub longitude: f64,
}

impl CreateMessageRequest {
    pub fn validate(&self) -> Result<(), AppError> {
        if self.content.is_empty() {
            return Err(AppError::Validation(ValidationKind::ContentEmpty));
        }
        if self.content.len() > MAX_CONTENT_LEN {
            return Err(AppError::Validation(ValidationKind::ContentTooLong));
        }
        if !(-90.0..=90.0).contains(&self.latitude)
            || !(-180.0..=180.0).contains(&self.longitude)
        {
            return Err(AppError::Validation(ValidationKind::InvalidCoords));
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
pub struct NearbyQuery {
    pub latitude: f64,
    pub longitude: f64,
    /// Search radius in metres (e.g. 500.0)
    pub radius: f64,
}

impl NearbyQuery {
    pub fn validate(&self) -> Result<(), AppError> {
        if !(-90.0..=90.0).contains(&self.latitude)
            || !(-180.0..=180.0).contains(&self.longitude)
        {
            return Err(AppError::Validation(ValidationKind::InvalidCoords));
        }
        if self.radius <= 0.0 || self.radius > MAX_RADIUS_METRES {
            return Err(AppError::Validation(ValidationKind::InvalidRadius));
        }
        Ok(())
    }
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
