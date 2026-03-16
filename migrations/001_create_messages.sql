-- Enable the PostGIS extension (idempotent)
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS messages (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    content     TEXT        NOT NULL,
    location    GEOMETRY(Point, 4326) NOT NULL,
    likes       INTEGER     NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Spatial index for fast proximity queries
CREATE INDEX IF NOT EXISTS idx_messages_location
    ON messages USING GIST (location);
