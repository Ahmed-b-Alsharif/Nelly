# Nelly Sync service — KV relay test milestone

This service pairs two parent iPhones and temporarily relays parent-approved local videos through Cloudflare Workers KV. It does not use R2.

## Cloud resources used

- Cloudflare Worker: request handling and authentication.
- Cloudflare D1 database: family/device records, pairing codes, video manifests and receipt records.
- Cloudflare Workers KV namespace: temporary video chunks.
- No R2 bucket, paid plan, or paid subscription is configured by this project.

The deployment config uses the D1 database and KV namespace already created for Nelly.

## Video relay rules

- Each video is limited to 100 MiB for the first test.
- Videos are split into 4 MiB chunks so each KV value stays below the 25 MiB per-value ceiling.
- One family is capped at 512 MiB of outstanding relay data. This is a conservative app-level cap, not a promise of unlimited storage.
- Temporary chunks receive a 30-day expiry as a cleanup fallback. If both phones acknowledge the video sooner, Nelly deletes the chunks immediately.
- The uploader's local file is never deleted by sync. The receiver stores its own local copy before acknowledging.
- If storage or request limits are reached, sync stops and local files remain untouched.
- KV is eventually consistent. The receiver may need to retry while newly uploaded chunks become visible.

## Free-plan capacity and safety

Cloudflare's published Workers Free limits currently include 100,000 Worker requests per day. Workers KV currently includes 1 GB of storage, 100,000 key reads per day, 1,000 key writes per day, and 1,000 key deletes per day. These are account-level ceilings shared with other Cloudflare projects, not reserved capacity for Nelly. A 100 MiB video uses up to 25 KV chunk writes, up to 25 chunk reads on the receiving phone, and up to 25 deletes when the relay is cleared, in addition to metadata and verification operations. Smaller videos use fewer chunks.

On the Workers Free plan, Cloudflare documents that operations fail after a daily KV limit is reached; they do not become paid overage operations on that Free plan. D1 and Worker request limits also apply. Keep the account on the Free plan. If a limit is reached, Nelly must pause sync and keep both phones' local videos; do not upgrade or add billing to continue.

These published limits can change. Check Cloudflare's current [KV limits](https://developers.cloudflare.com/kv/platform/limits/), [KV pricing](https://developers.cloudflare.com/kv/platform/pricing/), and [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) before relying on a larger transfer workload.

## Deployment

1. Keep the Cloudflare account on the Free plan. Do not add an R2 subscription or enable a paid plan for Nelly.
2. The actual `wrangler.toml` in this folder binds D1 as `DB` and the existing KV namespace as `RELAY`.
3. Deploy this folder as Worker `nelly-sync` from the connected Git repository, with the root directory set to `cloud` and deploy command `npx wrangler deploy`.
4. The Worker automatically creates the required D1 tables on its first request; `schema.sql` is kept as the readable schema reference.
5. Confirm the Worker health endpoint returns `{"service":"Nelly Sync","status":"ok",...}`.
6. The iOS client is already configured for `https://nelly-sync.aalshari.workers.dev`; build the iOS app after the Worker deployment succeeds.

Do not put Cloudflare API tokens, account secrets, or device tokens in this repository.

## First test

1. Install the test build on both parent iPhones.
2. On the first iPhone, open Admin → Family sync → Create family and pairing code.
3. On the second iPhone, enter the one-time code under Join existing family.
4. Keep both phones online and open Nelly. Add one small test video on the first phone.
5. Open Nelly on the second phone. It should download the video into its own private local library.
6. Confirm the video plays offline on the second phone. Then check the KV namespace: temporary chunk keys should be removed after both devices acknowledge receipt.

## Current scope and limitations

This milestone implements pairing, temporary video transfer, shared video titles/enabled state/order/deletions, and shared daily screen-time settings. The iOS client syncs when Nelly opens, returns to the foreground, when the local library changes, and approximately every 30 seconds while open. It does not guarantee background transfer while the app is fully closed. The iOS app also supports merging a previously exported Nelly backup; duplicate IDs are skipped and existing files are not overwritten or deleted.

The parent PIN is still configured locally on each phone and is not automatically shared. Pairing-code guesses are limited to 10 attempts per IP per minute. Broader production abuse monitoring and rate limiting are not yet implemented. The app has not yet passed a real two-iPhone end-to-end test. Do not treat the service as production-ready until these items are addressed and the transfer, metadata, screen-time and restore flows are tested.

The 30-day TTL is a safety cleanup fallback: if the second phone remains offline longer than that, the temporary relay may expire. The original phone's local video remains safe.
