use axum::{
    extract::{Query, State},
    http::StatusCode,
    Json,
};
use sqlx::PgPool;
use tracing::instrument;

use crate::error::AppError;
use crate::models::{
    CreateMessageRequest, CreateMessageResponse, NearbyMessageResponse, NearbyQuery,
};

/// Messages closer than this threshold (in metres) are fully readable.
const READABLE_RADIUS_METRES: f64 = 50.0;

// ── POST /v1/messages ────────────────────────────────────────────────────────

#[instrument(skip(pool))]
pub async fn create_message(
    State(pool): State<PgPool>,
    Json(req): Json<CreateMessageRequest>,
) -> Result<(StatusCode, Json<CreateMessageResponse>), AppError> {
    req.validate()?;

    // ST_MakePoint expects (longitude, latitude) — i.e. (x, y)
    let row = sqlx::query!(
        r#"
        INSERT INTO messages (content, location)
        VALUES (
            $1,
            ST_SetSRID(ST_MakePoint($2, $3), 4326)
        )
        RETURNING
            id,
            content,
            ST_X(location) AS "longitude!: f64",
            ST_Y(location) AS "latitude!: f64",
            likes,
            created_at
        "#,
        req.content,
        req.longitude, // x
        req.latitude,  // y
    )
    .fetch_one(&pool)
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(CreateMessageResponse {
            id: row.id,
            content: row.content,
            latitude: row.latitude,
            longitude: row.longitude,
            likes: row.likes,
            created_at: row.created_at,
        }),
    ))
}

// ── GET /v1/messages/nearby ──────────────────────────────────────────────────

#[instrument(skip(pool))]
pub async fn get_nearby_messages(
    State(pool): State<PgPool>,
    Query(params): Query<NearbyQuery>,
) -> Result<Json<Vec<NearbyMessageResponse>>, AppError> {
    params.validate()?;

    // Cast both geometries to `geography` so that ST_DWithin / ST_Distance
    // operate in metres on a spheroid rather than in degrees.
    let rows = sqlx::query!(
        r#"
        SELECT
            id,
            content,
            ST_X(location)  AS "longitude!: f64",
            ST_Y(location)  AS "latitude!: f64",
            likes,
            created_at,
            ST_Distance(
                location::geography,
                ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
            ) AS "distance_meters!: f64"
        FROM messages
        WHERE ST_DWithin(
            location::geography,
            ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
            $3
        )
        ORDER BY 7 ASC  -- column 7 = distance_meters (alias contains SQLx annotation, can't reference by name)
        "#,
        params.latitude,  // $1 — y
        params.longitude, // $2 — x
        params.radius,    // $3 — metres
    )
    .fetch_all(&pool)
    .await?;

    let messages = rows
        .into_iter()
        .map(|row| {
            let is_readable = row.distance_meters <= READABLE_RADIUS_METRES;
            NearbyMessageResponse {
                id: row.id,
                // Mask the content when the caller is too far away
                content: if is_readable { Some(row.content) } else { None },
                latitude: row.latitude,
                longitude: row.longitude,
                likes: row.likes,
                is_readable,
                distance_meters: row.distance_meters,
                created_at: row.created_at,
            }
        })
        .collect();

    Ok(Json(messages))
}
