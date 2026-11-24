const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const MAX_VIDEO_BYTES = 100 * 1024 * 1024;
const MAX_FAMILY_RELAY_BYTES = 512 * 1024 * 1024;
const CHUNK_BYTES = 4 * 1024 * 1024;
const MAX_CHUNKS = Math.ceil(MAX_VIDEO_BYTES / CHUNK_BYTES);
const RELAY_TTL_SECONDS = 30 * 24 * 60 * 60;
const INVITE_TTL_SECONDS = 15 * 60;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}
function randomToken(bytes = 32) {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return Array.from(value, b => b.toString(16).padStart(2, "0")).join("");
}
async function digest(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, "0")).join("");
}
function cors(response, request) {
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", request.headers.get("origin") || "*");
  headers.set("access-control-allow-methods", "GET,POST,PUT,OPTIONS");
  headers.set("access-control-allow-headers", "authorization,content-type,x-file-name,x-video-title");
  headers.set("access-control-max-age", "86400");
  return new Response(response.body, { status: response.status, headers });
}
async function bodyJSON(request) {
  try { return await request.json(); } catch { return null; }
}
async function authenticated(request, env) {
  const raw = request.headers.get("authorization") || "";
  if (!raw.startsWith("Bearer ")) return null;
  const tokenHash = await digest(raw.slice(7));
  return await env.DB.prepare(
    "SELECT id, family_id, device_name FROM devices WHERE token_hash = ? AND revoked = 0"
  ).bind(tokenHash).first();
}
function chunkKey(familyId, videoId, index) {
  return familyId + "/" + videoId + "/" + String(index).padStart(4, "0");
}
async function deleteRelay(env, familyId, videoId, chunkCount) {
  const keys = [];
  for (let i = 0; i < chunkCount; i++) keys.push(chunkKey(familyId, videoId, i));
  for (const key of keys) await env.RELAY.delete(key);
}
async function handle(request, env) {
  const url = new URL(request.url);
  if (request.method === "OPTIONS") return new Response(null, { status: 204 });
  if (url.pathname === "/health" && request.method === "GET") {
    return json({ service: "Nelly Sync", status: "ok", storage: "Cloudflare Workers KV chunks", version: 2 });
  }

  if (url.pathname === "/v1/families" && request.method === "POST") {
    const input = await bodyJSON(request);
    const deviceName = String(input?.deviceName || "Parent iPhone").slice(0, 60);
    const familyId = crypto.randomUUID();
    const deviceId = crypto.randomUUID();
    const token = randomToken(32);
    const inviteCode = randomToken(5).toUpperCase();
    const now = Math.floor(Date.now() / 1000);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO families (id, created_at) VALUES (?, ?)").bind(familyId, now),
      env.DB.prepare("INSERT INTO devices (id, family_id, device_name, token_hash, created_at) VALUES (?, ?, ?, ?, ?)")
        .bind(deviceId, familyId, deviceName, await digest(token), now),
      env.DB.prepare("INSERT INTO pairing_codes (code_hash, family_id, expires_at) VALUES (?, ?, ?)")
        .bind(await digest(inviteCode), familyId, now + INVITE_TTL_SECONDS)
    ]);
    return json({ familyId, deviceId, deviceToken: token, pairingCode: inviteCode, pairingCodeExpiresAt: now + INVITE_TTL_SECONDS }, 201);
  }

  if (url.pathname === "/v1/pair" && request.method === "POST") {
    const input = await bodyJSON(request);
    const code = String(input?.pairingCode || "").trim().toUpperCase();
    const deviceName = String(input?.deviceName || "Parent iPhone").slice(0, 60);
    if (!/^[A-F0-9]{10}$/.test(code)) return json({ error: "invalid_pairing_code" }, 400);
    const now = Math.floor(Date.now() / 1000);
    const codeHash = await digest(code);
    const invite = await env.DB.prepare(
      "SELECT family_id FROM pairing_codes WHERE code_hash = ? AND expires_at >= ? AND used_at IS NULL"
    ).bind(codeHash, now).first();
    if (!invite) return json({ error: "pairing_code_expired_or_used" }, 404);
    const count = await env.DB.prepare("SELECT COUNT(*) AS total FROM devices WHERE family_id = ? AND revoked = 0")
      .bind(invite.family_id).first();
    if ((count?.total || 0) >= 2) return json({ error: "family_already_has_two_devices" }, 409);
    const used = await env.DB.prepare("UPDATE pairing_codes SET used_at = ? WHERE code_hash = ? AND used_at IS NULL")
      .bind(now, codeHash).run();
    if (!used.meta?.changes) return json({ error: "pairing_code_already_used" }, 409);
    const deviceId = crypto.randomUUID();
    const token = randomToken(32);
    await env.DB.prepare(
      "INSERT INTO devices (id, family_id, device_name, token_hash, created_at) VALUES (?, ?, ?, ?, ?)"
    ).bind(deviceId, invite.family_id, deviceName, await digest(token), now).run();
    return json({ familyId: invite.family_id, deviceId, deviceToken: token }, 201);
  }

  const device = await authenticated(request, env);
  if (!device) return json({ error: "unauthorized" }, 401);

  if (url.pathname === "/v1/library" && request.method === "GET") {
    const rows = await env.DB.prepare(
      "SELECT v.id, v.file_name AS fileName, v.title, v.enabled, v.position, v.byte_count AS byteCount, v.chunk_count AS chunkCount, v.created_at AS createdAt, v.relay_deleted AS relayDeleted, v.upload_complete AS uploadComplete, v.deleted AS isDeleted, EXISTS(SELECT 1 FROM video_receipts r WHERE r.video_id = v.id AND r.device_id = ?) AS receivedByMe FROM videos v WHERE v.family_id = ? AND v.upload_complete = 1 ORDER BY v.position, v.created_at, v.id"
    ).bind(device.id, device.family_id).all();
    const videos = (rows.results || []).map(row => ({ ...row, enabled: Boolean(row.enabled), receivedByMe: Boolean(row.receivedByMe), relayDeleted: Boolean(row.relayDeleted), isDeleted: Boolean(row.isDeleted) }));
    return json({ familyId: device.family_id, deviceId: device.id, videos });
  }

  if (url.pathname === "/v1/settings" && request.method === "GET") {
    const row = await env.DB.prepare(
      "SELECT daily_limit AS dailyLimit, used_seconds AS usedSeconds, usage_day AS usageDay, settings_updated_at AS settingsUpdatedAt, reset_at AS resetAt FROM family_settings WHERE family_id = ?"
    ).bind(device.family_id).first();
    return json(row || { dailyLimit: 45, usedSeconds: 0, usageDay: "", settingsUpdatedAt: 0, resetAt: 0 });
  }

  if (url.pathname === "/v1/settings" && request.method === "PUT") {
    const input = await bodyJSON(request);
    const dailyLimit = Number(input?.dailyLimit);
    const usedSeconds = Number(input?.usedSeconds);
    const usageDay = String(input?.usageDay || "");
    const settingsUpdatedAt = Number(input?.settingsUpdatedAt || 0);
    const resetAt = Number(input?.resetAt || 0);
    if (!Number.isInteger(dailyLimit) || dailyLimit < 1 || dailyLimit > 240 ||
        !Number.isInteger(usedSeconds) || usedSeconds < 0 || usedSeconds > 14400 ||
        !/^\d{4}-\d{2}-\d{2}$/.test(usageDay) ||
        !Number.isFinite(settingsUpdatedAt) || !Number.isFinite(resetAt)) {
      return json({ error: "invalid_shared_settings" }, 400);
    }
    await env.DB.prepare(
      "INSERT INTO family_settings (family_id, daily_limit, used_seconds, usage_day, settings_updated_at, reset_at) VALUES (?, ?, ?, ?, ?, ?) " +
      "ON CONFLICT(family_id) DO UPDATE SET " +
      "daily_limit = CASE WHEN excluded.settings_updated_at >= family_settings.settings_updated_at THEN excluded.daily_limit ELSE family_settings.daily_limit END, " +
      "settings_updated_at = MAX(family_settings.settings_updated_at, excluded.settings_updated_at), " +
      "used_seconds = CASE WHEN excluded.usage_day > family_settings.usage_day THEN excluded.used_seconds WHEN excluded.usage_day < family_settings.usage_day THEN family_settings.used_seconds WHEN excluded.reset_at > family_settings.reset_at THEN excluded.used_seconds ELSE MAX(family_settings.used_seconds, excluded.used_seconds) END, " +
      "usage_day = MAX(family_settings.usage_day, excluded.usage_day), " +
      "reset_at = CASE WHEN excluded.usage_day > family_settings.usage_day OR excluded.reset_at > family_settings.reset_at THEN excluded.reset_at ELSE family_settings.reset_at END"
    ).bind(device.family_id, dailyLimit, usedSeconds, usageDay, settingsUpdatedAt, resetAt).run();
    const saved = await env.DB.prepare(
      "SELECT daily_limit AS dailyLimit, used_seconds AS usedSeconds, usage_day AS usageDay, settings_updated_at AS settingsUpdatedAt, reset_at AS resetAt FROM family_settings WHERE family_id = ?"
    ).bind(device.family_id).first();
    return json(saved);
  }

  const manifestMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/manifest$/);
  if (manifestMatch && request.method === "POST") {
    const videoId = manifestMatch[1];
    const input = await bodyJSON(request);
    const byteCount = Number(input?.byteCount);
    const chunkCount = Number(input?.chunkCount);
    if (!Number.isSafeInteger(byteCount) || byteCount < 1 || byteCount > MAX_VIDEO_BYTES ||
        !Number.isSafeInteger(chunkCount) || chunkCount < 1 || chunkCount > MAX_CHUNKS ||
        chunkCount !== Math.ceil(byteCount / CHUNK_BYTES)) {
      return json({ error: "invalid_video_manifest", maxBytes: MAX_VIDEO_BYTES, chunkBytes: CHUNK_BYTES }, 413);
    }
    const existing = await env.DB.prepare("SELECT chunk_count, upload_complete FROM videos WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).first();
    if (existing?.upload_complete) return json({ error: "video_id_already_exists" }, 409);
    if (existing) {
      // Recover an interrupted upload using the same stable local video ID.
      await deleteRelay(env, device.family_id, videoId, existing.chunk_count);
      await env.DB.batch([
        env.DB.prepare("DELETE FROM video_receipts WHERE video_id = ?").bind(videoId),
        env.DB.prepare("DELETE FROM videos WHERE id = ? AND family_id = ?").bind(videoId, device.family_id)
      ]);
    }
    const totals = await env.DB.prepare("SELECT COALESCE(SUM(byte_count), 0) AS used FROM videos WHERE family_id = ? AND relay_deleted = 0")
      .bind(device.family_id).first();
    if ((totals?.used || 0) + byteCount > MAX_FAMILY_RELAY_BYTES) {
      return json({ error: "family_kv_relay_limit_reached", maxBytes: MAX_FAMILY_RELAY_BYTES }, 507);
    }
    const fileName = String(input?.fileName || "video.mp4").replace(/[\\/\0-\r\n]/g, "_").slice(0, 180);
    const title = String(input?.title || "").slice(0, 200);
    const enabled = input?.enabled === false ? 0 : 1;
    const position = Number.isInteger(input?.position) ? Math.max(0, Math.min(10000, input.position)) : 0;
    const now = Math.floor(Date.now() / 1000);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO videos (id, family_id, file_name, title, enabled, position, byte_count, chunk_count, created_at, relay_deleted, upload_complete) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)")
        .bind(videoId, device.family_id, fileName, title, enabled, position, byteCount, chunkCount, now),
      env.DB.prepare("INSERT INTO video_receipts (video_id, device_id, received_at) VALUES (?, ?, ?)")
        .bind(videoId, device.id, now)
    ]);
    return json({ accepted: true, chunkBytes: CHUNK_BYTES, chunkCount }, 201);
  }

  const metaMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/meta$/);
  if (metaMatch && request.method === "PUT") {
    const videoId = metaMatch[1];
    const input = await bodyJSON(request);
    const title = String(input?.title || "").slice(0, 200);
    const enabled = input?.enabled === false ? 0 : 1;
    const position = Number(input?.position);
    if (!Number.isInteger(position) || position < 0 || position > 10000) {
      return json({ error: "invalid_video_position" }, 400);
    }
    const result = await env.DB.prepare(
      "UPDATE videos SET title = ?, enabled = ?, position = ? WHERE id = ? AND family_id = ? AND upload_complete = 1 AND deleted = 0"
    ).bind(title, enabled, position, videoId, device.family_id).run();
    if (!result.meta?.changes) return json({ error: "video_not_found" }, 404);
    return json({ updated: true });
  }

  const deleteMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/delete$/);
  if (deleteMatch && request.method === "POST") {
    const videoId = deleteMatch[1];
    const row = await env.DB.prepare("SELECT chunk_count FROM videos WHERE id = ? AND family_id = ? AND deleted = 0")
      .bind(videoId, device.family_id).first();
    if (!row) return json({ deleted: true });
    await deleteRelay(env, device.family_id, videoId, row.chunk_count || 0);
    await env.DB.prepare("UPDATE videos SET deleted = 1, relay_deleted = 1 WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).run();
    return json({ deleted: true });
  }

  const chunkMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/chunks\/(\d+)$/);
  if (chunkMatch && request.method === "PUT") {
    const videoId = chunkMatch[1];
    const index = Number(chunkMatch[2]);
    const row = await env.DB.prepare("SELECT byte_count, chunk_count, upload_complete, relay_deleted FROM videos WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).first();
    if (!row || row.relay_deleted || row.upload_complete || !Number.isInteger(index) || index < 0 || index >= row.chunk_count) {
      return json({ error: "invalid_chunk_target" }, 404);
    }
    const expected = index === row.chunk_count - 1 ? row.byte_count - (index * CHUNK_BYTES) : CHUNK_BYTES;
    const declared = Number(request.headers.get("content-length") || 0);
    if (declared !== expected) return json({ error: "invalid_chunk_size", expectedBytes: expected }, 413);
    const bytes = await request.arrayBuffer();
    if (bytes.byteLength !== expected) return json({ error: "incomplete_chunk" }, 400);
    await env.RELAY.put(chunkKey(device.family_id, videoId, index), bytes, {
      expirationTtl: RELAY_TTL_SECONDS,
      metadata: { familyId: device.family_id, videoId, index: String(index) }
    });
    return json({ stored: true, index });
  }

  const completeMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/complete$/);
  if (completeMatch && request.method === "POST") {
    const videoId = completeMatch[1];
    const row = await env.DB.prepare("SELECT chunk_count, upload_complete, relay_deleted FROM videos WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).first();
    if (!row || row.relay_deleted) return json({ error: "video_not_found" }, 404);
    if (row.upload_complete) return json({ complete: true });
    for (let i = 0; i < row.chunk_count; i++) {
      if (!(await env.RELAY.get(chunkKey(device.family_id, videoId, i), "arrayBuffer"))) {
        return json({ error: "chunk_not_visible_yet", missingChunk: i, retryAfterSeconds: 2 }, 425);
      }
    }
    await env.DB.prepare("UPDATE videos SET upload_complete = 1 WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).run();
    return json({ complete: true });
  }

  const videoMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})$/);
  if (videoMatch && request.method === "GET") {
    const videoId = videoMatch[1];
    const index = Number(url.searchParams.get("chunk"));
    const row = await env.DB.prepare("SELECT chunk_count, relay_deleted, upload_complete, deleted FROM videos WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).first();
    if (!row || !row.upload_complete || row.deleted) return json({ error: "video_not_found" }, 404);
    if (row.relay_deleted) return json({ error: "temporary_video_copy_already_cleared" }, 410);
    if (!Number.isInteger(index) || index < 0 || index >= row.chunk_count) return json({ error: "invalid_chunk_index" }, 400);
    const bytes = await env.RELAY.get(chunkKey(device.family_id, videoId, index), "arrayBuffer");
    if (!bytes) return json({ error: "chunk_not_visible_or_expired", retryAfterSeconds: 2 }, 404);
    return new Response(bytes, { headers: { "content-type": "application/octet-stream", "cache-control": "private, no-store" } });
  }

  const ackMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/ack$/);
  if (ackMatch && request.method === "POST") {
    const videoId = ackMatch[1];
    const row = await env.DB.prepare("SELECT chunk_count FROM videos WHERE id = ? AND family_id = ? AND relay_deleted = 0 AND upload_complete = 1 AND deleted = 0")
      .bind(videoId, device.family_id).first();
    if (!row) return json({ error: "video_not_found_or_already_cleared" }, 404);
    const now = Math.floor(Date.now() / 1000);
    await env.DB.prepare("INSERT OR IGNORE INTO video_receipts (video_id, device_id, received_at) VALUES (?, ?, ?)")
      .bind(videoId, device.id, now).run();
    const expected = await env.DB.prepare("SELECT COUNT(*) AS total FROM devices WHERE family_id = ? AND revoked = 0")
      .bind(device.family_id).first();
    const received = await env.DB.prepare("SELECT COUNT(*) AS total FROM video_receipts WHERE video_id = ?")
      .bind(videoId).first();
    if ((expected?.total || 0) === 2 && (received?.total || 0) === 2) {
      await deleteRelay(env, device.family_id, videoId, row.chunk_count);
      await env.DB.prepare("UPDATE videos SET relay_deleted = 1 WHERE id = ? AND family_id = ?")
        .bind(videoId, device.family_id).run();
      return json({ acknowledged: true, relayCopyDeleted: true });
    }
    return json({ acknowledged: true, relayCopyDeleted: false });
  }

  return json({ error: "not_found" }, 404);
}

export default {
  async fetch(request, env) {
    try {
      return cors(await handle(request, env), request);
    } catch {
      return cors(json({ error: "server_error", message: "The sync service could not complete the request." }, 500), request);
    }
  }
};
