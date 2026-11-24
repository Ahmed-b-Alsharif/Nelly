CREATE TABLE IF NOT EXISTS families (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  device_name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_devices_family ON devices(family_id);

CREATE TABLE IF NOT EXISTS pairing_codes (
  code_hash TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE IF NOT EXISTS videos (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  enabled INTEGER NOT NULL DEFAULT 1,
  position INTEGER NOT NULL DEFAULT 0,
  byte_count INTEGER NOT NULL,
  chunk_count INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  relay_deleted INTEGER NOT NULL DEFAULT 0,
  upload_complete INTEGER NOT NULL DEFAULT 0,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_videos_family ON videos(family_id, created_at);

CREATE TABLE IF NOT EXISTS video_receipts (
  video_id TEXT NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  received_at INTEGER NOT NULL,
  PRIMARY KEY (video_id, device_id)
);

CREATE TABLE IF NOT EXISTS family_settings (
  family_id TEXT PRIMARY KEY REFERENCES families(id) ON DELETE CASCADE,
  daily_limit INTEGER NOT NULL DEFAULT 45,
  used_seconds INTEGER NOT NULL DEFAULT 0,
  usage_day TEXT NOT NULL DEFAULT '',
  settings_updated_at REAL NOT NULL DEFAULT 0,
  reset_at REAL NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS pair_attempts (
  ip_hash TEXT PRIMARY KEY,
  window_started_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0
);
