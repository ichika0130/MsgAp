# Msgap — Project Reference

## Concept

A location-based "Message" (谏言) system inspired by Dark Souls. Users leave short text messages
at physical GPS coordinates. Other users can discover that a message *exists* nearby, but can only
read its content if they are physically within **50 metres** of the drop point. Beyond that radius
the content is masked (`null`) in the API response.

---

## Tech Stack

| Layer        | Technology                                      |
|--------------|-------------------------------------------------|
| Language     | Rust (edition 2021)                             |
| Web framework| Axum 0.7                                        |
| Async runtime| Tokio (full features)                           |
| Database     | PostgreSQL 16 + PostGIS 3.4                     |
| DB client    | SQLx 0.7 (compile-time verified queries)        |
| Serialization| Serde / serde_json                              |
| IDs          | UUID v4                                         |
| Timestamps   | chrono `DateTime<Utc>`                          |
| Observability| tracing + tracing-subscriber (EnvFilter)        |
| Middleware   | tower-http `TraceLayer`                         |
| Config       | dotenvy (`.env` file)                           |
| Infra        | Docker Compose (`postgis/postgis:16-3.4-alpine`)|

---

## Project Structure

```
MsgAp/
├── docker-compose.yml          # Postgres + PostGIS service
├── .env.example                # Required env vars template
├── Cargo.toml
├── migrations/
│   └── 001_create_messages.sql # Schema + GIST index (run automatically on boot)
└── src/
    ├── main.rs                 # Server boot, DB pool, migration runner, router
    ├── models.rs               # Request / response structs
    └── handlers.rs             # Endpoint logic (create_message, get_nearby_messages)
```

---

## Database Schema

```sql
CREATE TABLE messages (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    content    TEXT        NOT NULL,
    location   GEOMETRY(Point, 4326) NOT NULL,
    likes      INTEGER     NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_messages_location ON messages USING GIST (location);
```

Migrations are registered with SQLx's `migrate!("./migrations")` macro and run automatically
at server startup via `sqlx::migrate!().run(&pool).await`.

---

## Architectural Decisions

### PostGIS geometry type: `GEOMETRY(Point, 4326)`
The column is strictly typed as a 2D point with SRID 4326 (WGS84 — standard GPS lat/lon).
This lets PostGIS reject invalid geometry at the DB level and keeps the SRID explicit on every
row rather than relying on application-level convention.

### `::geography` cast for distance queries
All proximity queries cast `location` to the `geography` type before calling `ST_DWithin` and
`ST_Distance`. This is critical: operating on raw `geometry` computes distances in **degrees**,
which is meaningless for a metre-based radius. The `geography` cast makes PostGIS use a spheroid
model and return true distances in **metres**.

```sql
-- geometry  → distance in degrees (WRONG for "500 metres")
ST_DWithin(location, caller_point, 500)

-- geography → distance in metres (CORRECT)
ST_DWithin(location::geography, caller_point::geography, 500)
```

### `ST_MakePoint(longitude, latitude)` — x before y
PostGIS follows the mathematical (x, y) convention: **longitude first, latitude second**.
This is a common source of silent bugs. The code comments this explicitly at every call site.

### Content masking is done server-side, not client-side
The `is_readable` flag and content masking happen in Rust after the DB query returns. The
unmasked content is never transmitted to a client that is out of range — it is `None` before
serialization. This means there is no client-side trust assumption.

### `READABLE_RADIUS_METRES` constant in `handlers.rs`
The 50 m read threshold lives as a single named constant (`const READABLE_RADIUS_METRES: f64 = 50.0`).
It is intentionally separate from the user-supplied search `radius` query parameter, which controls
*discovery* range and is independent.

### SQLx compile-time query verification
`sqlx::query!` macros are verified against the live schema at compile time. This requires either:
- A running Postgres instance with `DATABASE_URL` set, **or**
- An offline cache: run `cargo sqlx prepare` once to generate `.sqlx/` and set `SQLX_OFFLINE=true`.

### Error responses
Handlers return `(StatusCode, String)` errors. The string currently surfaces raw SQLx error
messages — acceptable for development, needs replacement before production (see Pending Tasks).

---

## API Reference

### `POST /v1/messages`
Create a new message at a GPS coordinate.

**Request body:**
```json
{ "content": "You were here", "latitude": 35.6812, "longitude": 139.7671 }
```

**Response `201 Created`:**
```json
{
  "id": "uuid",
  "content": "You were here",
  "latitude": 35.6812,
  "longitude": 139.7671,
  "likes": 0,
  "created_at": "2026-03-16T12:00:00Z"
}
```

---

### `GET /v1/messages/nearby`
Discover messages within a radius. Content is masked when distance > 50 m.

**Query params:** `latitude`, `longitude`, `radius` (metres)

**Response `200 OK`:**
```json
[
  {
    "id": "uuid",
    "content": "You were here",   // null when is_readable: false
    "latitude": 35.6812,
    "longitude": 139.7671,
    "likes": 0,
    "is_readable": true,
    "distance_meters": 12.4,
    "created_at": "2026-03-16T12:00:00Z"
  }
]
```

---

## Running Locally

```bash
# 1. Start the database
docker compose up -d

# 2. Configure environment
cp .env.example .env        # edit if needed

# 3. Run (migrations execute automatically on first boot)
cargo run
```

Required env vars (see `.env.example`):
```
DATABASE_URL=postgres://msgap:msgap_secret@localhost:5432/msgap
RUST_LOG=info
```

---

## Pending Tasks

Priority order: items higher on the list are blockers or high-value before anything below them.

### P0 — Must fix before any real usage

- [ ] **Input validation**
  Reject requests with out-of-range coordinates (`lat` outside ±90, `lon` outside ±180),
  empty `content`, content over a max length (e.g. 500 chars), and `radius` above a sane
  cap (e.g. 5000 m) to prevent full-table scans.

- [ ] **Safe error responses**
  Replace `(StatusCode, String)` with a proper `AppError` type (e.g. using `thiserror`) that
  returns structured JSON (`{ "error": "..." }`) and never leaks internal DB error strings
  to the client.

- [ ] **SQLx offline cache**
  Run `cargo sqlx prepare` and commit the generated `.sqlx/` directory so the project compiles
  in CI without a live database (`SQLX_OFFLINE=true`).

### P1 — Core feature gaps

- [ ] **`POST /v1/messages/{id}/like`**
  The `likes` column exists but there is no endpoint to increment it. Implement with
  `UPDATE messages SET likes = likes + 1 WHERE id = $1 RETURNING likes` to avoid races.

- [ ] **`GET /v1/messages/{id}`**
  Fetch a single message by UUID. Applies the same 50 m readability rule using a caller
  location passed as query params. Needed for deep-linking from notifications.

- [ ] **Pagination on `/v1/messages/nearby`**
  The nearby query is unbounded — a large radius could return thousands of rows. Add
  `limit` (default 50, max 200) and `offset` (or cursor) query parameters.

### P2 — Production readiness

- [ ] **User identity / authentication**
  All messages are currently anonymous. Decide on an auth strategy (JWT, session token,
  or anonymous device ID) so messages can be attributed and users can delete their own.

- [ ] **Rate limiting**
  Add per-IP or per-user rate limiting on `POST /v1/messages` using `tower-governor` or
  a similar middleware to prevent message spam.

- [ ] **Integration tests**
  Write `#[sqlx::test]` integration tests that spin up a real Postgres instance, run
  migrations, and exercise the full create → nearby → mask logic end-to-end.

- [ ] **`DELETE /v1/messages/{id}`**
  Allow message authors to delete their own messages (requires auth from P2).

### P3 — Future features

- [ ] **Message TTL / expiry**
  Add an optional `expires_at TIMESTAMPTZ` column and filter expired messages out of
  all queries. Adds a Dark Souls-like impermanence to the world.

- [ ] **Clustering for the discovery layer**
  When many messages are densely packed, return cluster summaries (count + centroid)
  instead of individual records at zoom levels above a threshold.

- [ ] **WebSocket / SSE push**
  Push nearby message arrival events to connected clients in real time instead of requiring
  polling on the nearby endpoint.
