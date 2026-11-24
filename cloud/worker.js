const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };
const MAX_VIDEO_BYTES = 100 * 1024 * 1024;
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
async function handle(request, env) {
  const url = new URL(request.url);
  if (request.method === "OPTIONS") return new Response(null, { status: 204 });
  if (url.pathname === "/health" && request.method === "GET") return json({ service: "Nelly Sync", status: "ok", version: 1 });

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
    const invite = await env.DB.prepare(
      "SELECT family_id FROM pairing_codes WHERE code_hash = ? AND expires_at >= ? AND used_at IS NULL"
    ).bind(await digest(code), now).first();
    if (!invite) return json({ error: "pairing_code_expired_or_used" }, 404);
    const count = await env.DB.prepare("SELECT COUNT(*) AS total FROM devices WHERE family_id = ? AND revoked = 0")
      .bind(invite.family_id).first();
    if ((count?.total || 0) >= 2) return json({ error: "family_already_has_two_devices" }, 409);
    const deviceId = crypto.randomUUID();
    const token = randomToken(32);
    const result = await env.DB.prepare(
      "UPDATE pairing_codes SET used_at = ? WHERE code_hash = ? AND used_at IS NULL"
    ).bind(now, await digest(code)).run();
    if (!result.meta?.changes) return json({ error: "pairing_code_already_used" }, 409);
    await env.DB.prepare(
      "INSERT INTO devices (id, family_id, device_name, token_hash, created_at) VALUES (?, ?, ?, ?, ?)"
    ).bind(deviceId, invite.family_id, deviceName, await digest(token), now).run();
    return json({ familyId: invite.family_id, deviceId, deviceToken: token }, 201);
  }

  const device = await authenticated(request, env);
  if (!device) return json({ error: "unauthorized" }, 401);

  if (url.pathname === "/v1/library" && request.method === "GET") {
    const rows = await env.DB.prepare(
      "SELECT id, file_name, title, byte_count, created_at FROM videos WHERE family_id = ? ORDER BY created_at, id"
    ).bind(device.family_id).all();
    return json({ familyId: device.family_id, deviceId: device.id, videos: rows.results || [] });
  }

  const videoMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})$/);
  if (videoMatch && request.method === "PUT") {
    const videoId = videoMatch[1];
    const length = Number(request.headers.get("content-length") || 0);
    if (!Number.isFinite(length) || length <= 0 || length > MAX_VIDEO_BYTES) {
      return json({ error: "video_size_out_of_range", maxBytes: MAX_VIDEO_BYTES }, 413);
    }
    const fileName = (request.headers.get("x-file-name") || "video.mp4").replace(/[\\/\0-\r\n]/g, "_").slice(0, 180);
    const title = (request.headers.get("x-video-title") || "").slice(0, 200);
    const existing = await env.DB.prepare("SELECT id FROM videos WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).first();
    if (existing) return json({ error: "video_id_already_exists" }, 409);
    const totals = await env.DB.prepare("SELECT COALESCE(SUM(byte_count), 0) AS used FROM videos WHERE family_id = ?")
      .bind(device.family_id).first();
    if ((totals?.used || 0) + length > 9 * 1024 * 1024 * 1024) {
      return json({ error: "family_free_storage_limit_reached" }, 507);
    }
    await env.VIDEOS.put(device.family_id + "/" + videoId, request.body, {
      httpMetadata: { contentType: request.headers.get("content-type") || "video/mp4" },
      customMetadata: { fileName, title, uploadedBy: device.id }
    });
    const now = Math.floor(Date.now() / 1000);
    await env.DB.batch([
      env.DB.prepare("INSERT INTO videos (id, family_id, file_name, title, byte_count, created_at, relay_deleted) VALUES (?, ?, ?, ?, ?, ?, 0)")
        .bind(videoId, device.family_id, fileName, title, length, now),
      env.DB.prepare("INSERT INTO video_receipts (video_id, device_id, received_at) VALUES (?, ?, ?)")
        .bind(videoId, device.id, now)
    ]);
    return json({ uploaded: true, videoId, byteCount: length }, 201);
  }

  if (videoMatch && request.method === "GET") {
    const videoId = videoMatch[1];
    const row = await env.DB.prepare("SELECT id FROM videos WHERE id = ? AND family_id = ?")
      .bind(videoId, device.family_id).first();
    if (!row) return json({ error: "video_not_found" }, 404);
    const object = await env.VIDEOS.get(device.family_id + "/" + videoId);
    if (!object) return json({ error: "temporary_video_copy_already_cleared" }, 410);
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("content-length", String(object.size));
    headers.set("cache-control", "private, no-store");
    return new Response(object.body, { headers });
  }

  const ackMatch = url.pathname.match(/^\/v1\/videos\/([0-9a-fA-F-]{36})\/ack$/);
  if (ackMatch && request.method === "POST") {
    const videoId = ackMatch[1];
    const row = await env.DB.prepare("SELECT id FROM videos WHERE id = ? AND family_id = ? AND relay_deleted = 0")
      .bind(videoId, device.family_id).first();
    if (!row) return json({ error: "video_not_found_or_already_acknowledged" }, 404);
    const now = Math.floor(Date.now() / 1000);
    await env.DB.prepare("INSERT OR IGNORE INTO video_receipts (video_id, device_id, received_at) VALUES (?, ?, ?)")
      .bind(videoId, device.id, now).run();
    const expected = await env.DB.prepare("SELECT COUNT(*) AS total FROM devices WHERE family_id = ? AND revoked = 0")
      .bind(device.family_id).first();
    const received = await env.DB.prepare("SELECT COUNT(*) AS total FROM video_receipts WHERE video_id = ?")
      .bind(videoId).first();
    if ((expected?.total || 0) >= 2 && (received?.total || 0) >= 2) {
      await env.VIDEOS.delete(device.family_id + "/" + videoId);
      await env.DB.prepare("UPDATE videos SET relay_deleted = 1 WHERE id = ?").bind(videoId).run();
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
    } catch (error) {
      return cors(json({ error: "server_error", message: "The sync service could not complete the request." }, 500), request);
    }
  }
};
