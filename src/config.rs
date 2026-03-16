use serde::Deserialize;
use std::sync::OnceLock;

static STRINGS: OnceLock<Strings> = OnceLock::new();

// ── TOML-mapped structs ───────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct Strings {
    pub errors: ErrorStrings,
}

#[derive(Debug, Deserialize)]
pub struct ErrorStrings {
    pub validation: ValidationStrings,
    pub database: DatabaseStrings,
}

#[derive(Debug, Deserialize)]
pub struct ValidationStrings {
    pub invalid_coords: String,
    pub content_empty: String,
    pub content_too_long: String,
    pub invalid_radius: String,
}

#[derive(Debug, Deserialize)]
pub struct DatabaseStrings {
    pub connection_lost: String,
    pub not_found: String,
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Reads `path` from disk, parses it as TOML, and stores the result in a
/// process-wide `OnceLock`. Must be called exactly once before serving requests.
pub fn init(path: &str) {
    let raw = std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("Failed to read {path}: {e}"));
    let parsed: Strings = toml::from_str(&raw)
        .unwrap_or_else(|e| panic!("Failed to parse {path}: {e}"));
    STRINGS
        .set(parsed)
        .expect("config::init called more than once");
}

/// Returns a reference to the loaded strings.
/// Panics if `config::init` has not been called first.
pub fn strings() -> &'static Strings {
    STRINGS.get().expect("config::init has not been called")
}
