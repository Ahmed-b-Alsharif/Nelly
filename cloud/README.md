# Nelly Sync service (first milestone)

This folder contains the first backend slice for pairing two parent iPhones and relaying a test video.

## What this milestone supports
- Create a family on the first phone and issue a one-time 10-character pairing code.
- Pair one second phone. A family is limited to two active devices.
- Store only a SHA-256 hash of each device bearer token and pairing code in D1.
- Upload a video to a private R2 bucket and let the other paired device download it.
- The uploading phone is recorded as having its local copy. Once both paired phones acknowledge a video, the relay object is deleted. The metadata remains so both devices can keep the shared library listing.

## Free-tier guardrails
- Per-family upload ceiling is 9 GiB (below the R2 free allowance, leaving headroom).
- Per-video request ceiling is 100 MiB in this first milestone.
- The service never creates a paid plan or enables billing.
- R2/D1/Workers are subject to Cloudflare's current free quotas and account limits. If a quota is reached, synchronization must pause rather than delete local files.

## Deploying
1. Create a Cloudflare account and enable Workers, D1, and R2 on the free plan.
2. Create a D1 database named `nelly-sync` and an R2 bucket named `nelly-video-relay`.
3. Copy `wrangler.toml.example` to `wrangler.toml`, then replace the D1 database ID with the ID shown in Cloudflare.
4. Apply `schema.sql` to the D1 database.
5. Deploy `worker.js` as a Worker named `nelly-sync` and bind the D1 database as `DB` and R2 bucket as `VIDEOS`.
6. Keep the Worker URL private until the iOS client pairing flow is ready.

Do not put a Cloudflare API token, account secret, or device token in this repository. Device tokens are returned once to the app and must be stored in the iOS Keychain.

## Important current limitations
This is deliberately only the first transport milestone. It does not yet synchronize rename/reorder/enable/disable/delete operations, screen-time usage, PIN changes, or backup restore. It also does not yet have the iOS client screens or a deployed Worker. Do not install a new IPA based on this backend source alone.

The temporary relay object is removed only after both devices acknowledge successful local receipt. If one phone remains offline, the relay copy stays available. If both phones later lose their local copies after the relay has been cleared, restore from the exported Nelly backup.
