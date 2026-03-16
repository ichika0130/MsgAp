# Msgap — Project Reference

## Concept

A location-based "Message" (谏言) system inspired by Dark Souls. Users leave short text messages
at physical GPS coordinates. Other users can discover that a message *exists* nearby, but can only
read its content if they are physically within **50 metres** of the drop point. Beyond that radius
the content is masked (`null`) in the API response.

---

## Current Status

**As of 2026-03-16** — active development, not yet in production.

- The **Rust/PostGIS backend** compiles cleanly, runs via `cargo run`, and has been manually
  verified against a live Docker Postgres instance.
- The **iOS frontend** (Xcode project `MsgAp`, minimum iOS 17) is scaffolded and connected to the
  local backend. The map renders, pins appear, and the "Leave Message" sheet posts successfully to
  `POST /v1/messages`.
- All **P0 backend tasks** (input validation, structured error responses, SQLx offline cache) are
  complete. The `.sqlx/` offline cache is committed; `SQLX_OFFLINE=true` is set in `.env`.

---

## Tech Stack

### Backend

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
| Config       | dotenvy (`.env` file), toml 0.8 (`strings.toml`)|
| Infra        | Docker Compose (`postgis/postgis:16-3.4-alpine`)|

### iOS Frontend

| Layer        | Technology                                      |
|--------------|-------------------------------------------------|
| Language     | Swift 5.9+                                      |
| UI framework | SwiftUI (iOS 17+)                               |
| Maps         | MapKit — `Map`, `MapUserLocationButton`, `MapCompass` |
| State        | `@Observable` (Swift Observation framework)     |
| Networking   | `URLSession` async/await                        |
| Xcode project| `MsgAp.xcodeproj` (PBXFileSystemSynchronizedRootGroup) |

---

## Project Structure

```
MsgAp/
├── docker-compose.yml          # Postgres + PostGIS service
├── .env                        # Local env vars (not committed)
├── .env.example                # Required env vars template
├── strings.toml                # Dark Souls-style error messages (loaded at startup)
├── Info.plist                  # iOS ATS + location permission keys (INFOPLIST_FILE)
├── Cargo.toml
├── .sqlx/                      # SQLx offline query cache (committed — CI safe)
├── migrations/
│   └── 001_create_messages.sql # Schema + GIST index (run automatically on boot)
├── src/
│   ├── main.rs                 # Server boot, DB pool, migration runner, router
│   ├── config.rs               # OnceLock<Strings> — loads strings.toml once at startup
│   ├── error.rs                # AppError enum — IntoResponse with flavour text lookup
│   ├── models.rs               # Request / response structs + validate() methods
│   └── handlers.rs             # Endpoint logic (create_message, get_nearby_messages)
└── MsgAp/                      # iOS Xcode target source (auto-synced by Xcode)
    ├── MsgApApp.swift           # @main entry point
    ├── Models/
    │   ├── Message.swift        # Codable + Identifiable; CLLocationCoordinate2D computed prop
    │   └── MessageTemplates.swift  # KeywordCategory struct + static template/keyword data
    ├── Stores/
    │   └── MessageStore.swift   # @Observable; fetchNearby + submitMessage
    └── Views/
        ├── ContentView.swift    # Map + pins + Seek Echoes button + FAB
        └── LeaveMessageView.swift  # Souls-style message builder sheet
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

Migrations run automatically at server startup via `sqlx::migrate!().run(&pool).await`.

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

### `ORDER BY 7 ASC` in the nearby query
The distance alias uses a SQLx type annotation (`AS "distance_meters!: f64"`), which Postgres
stores as a quoted identifier including the `!: f64` suffix. Referencing `ORDER BY distance_meters`
fails at compile time. The workaround is `ORDER BY 7` (positional — column 7 in the SELECT list).

### Content masking is done server-side
The `is_readable` flag and content masking happen in Rust after the DB query returns. The
unmasked content is `None` before serialization, so it is never transmitted to an out-of-range
client. No client-side trust assumption.

### `READABLE_RADIUS_METRES` constant in `handlers.rs`
The 50 m read threshold lives as a single named constant. It is intentionally separate from the
user-supplied search `radius` query parameter, which controls *discovery* range independently.

### SQLx compile-time query verification
`sqlx::query!` macros require either a live `DATABASE_URL` or a committed `.sqlx/` offline cache.
The cache is generated with `cargo sqlx prepare` and checked in. `SQLX_OFFLINE=true` is set in
`.env` so `cargo build` works without a running database.

### `strings.toml` + `OnceLock<Strings>` for error flavour text
All user-visible error strings live in `strings.toml` at the project root. `config::init()` is
called once at server startup and stores the parsed result in a `OnceLock<Strings>`. Handlers
never read the file directly — they call `config::strings()` which is a pointer dereference.
Adding or changing error text requires only editing `strings.toml`, with no recompile.

### `AppError` + `IntoResponse`
`AppError` has three variants: `Validation(ValidationKind)`, `Database(sqlx::Error)`, `NotFound`.
`IntoResponse` looks up the flavour-text string from the loaded config and returns structured JSON
(`{"error": "..."}`). Raw SQLx errors are never exposed to the client.

### iOS map position: `.userLocation(fallback: .automatic)`
`MapCameraPosition` is initialised to `.userLocation(fallback: .automatic)` so the map follows
the user on launch. `mapCenter` is updated on every `onMapCameraChange` event and is used as
the coordinate for both `fetchNearby` and `submitMessage`, allowing the user to pan to a specific
location before dropping a message.

### iOS Info.plist placement
The `Info.plist` lives at the project root (not inside `MsgAp/`) to avoid a duplicate-output
build error caused by `PBXFileSystemSynchronizedRootGroup` treating any file inside `MsgAp/` as
a resource to copy *and* the build system also trying to process it as the info plist.
`INFOPLIST_FILE` build setting must be set to `Info.plist`.

---

## API Reference

### `POST /v1/messages`
Create a new message at a GPS coordinate.

**Request body:**
```json
{ "content": "Likely treasure", "latitude": 35.6812, "longitude": 139.7671 }
```

**Response `201 Created`:**
```json
{
  "id": "uuid",
  "content": "Likely treasure",
  "latitude": 35.6812,
  "longitude": 139.7671,
  "likes": 0,
  "created_at": "2026-03-16T12:00:00Z"
}
```

**Validation (400):** content empty, content > 500 chars, lat outside ±90, lon outside ±180.

---

### `GET /v1/messages/nearby`
Discover messages within a radius. Content is masked when distance > 50 m.

**Query params:** `latitude`, `longitude`, `radius` (metres, max 5000)

**Response `200 OK`:**
```json
[
  {
    "id": "uuid",
    "content": "Likely treasure",
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

# 2. Configure environment (already done — .env committed with SQLX_OFFLINE=true)
# Edit DATABASE_URL if your Postgres credentials differ from the defaults

# 3. Run (migrations execute automatically on first boot)
cargo run
```

Required env vars (see `.env.example`):
```
DATABASE_URL=postgres://msgap:msgap_secret@localhost:5432/msgap
RUST_LOG=info
SQLX_OFFLINE=true
```

To regenerate the SQLx offline cache after schema changes:
```bash
# Requires a running database and DATABASE_URL set in the shell
DATABASE_URL=postgres://msgap:msgap_secret@localhost:5432/msgap cargo sqlx prepare
```

---

## Pending Tasks

Priority order: items higher on the list are blockers or high-value before anything below them.

### P0 — Complete ✓

- [x] **Input validation** — lat/lon bounds, empty content, max 500 chars, max 5000 m radius
- [x] **Safe error responses** — `AppError` + `IntoResponse`; structured JSON; no raw DB leaks
- [x] **SQLx offline cache** — `.sqlx/` committed; `SQLX_OFFLINE=true` in `.env`

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

- [ ] **iOS: Like button in `MessageDetailView`**
  Wire up a like button that calls `POST /v1/messages/{id}/like` and updates the displayed
  count. Requires the backend endpoint above to exist first.

- [ ] **iOS: Refresh after posting**
  After `submitMessage` succeeds and the sheet dismisses, automatically call `fetchNearby`
  so the new pin appears on the map immediately without a manual "Seek Echoes" tap.

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

- [ ] **iOS: Offline draft queue**
  If the network request fails in `LeaveMessageView`, save the draft locally and retry
  when connectivity is restored.
