# Nelly

A private, parent-curated video player for a young child. Nelly targets iPhone and iOS 18.2.

## Included in this starter build
- Full-screen, vertically paged video feed.
- Local video playback with looping.
- TikTok player URL integration and YouTube privacy-enhanced embeds.
- Add links and import videos from Photos and Files.
- Parent admin protected by a PIN.
- Enable/disable, delete and reorder videos.
- Adjustable daily screen-time allowance (default 45 minutes).
- Watch history and light/dark appearance.
- Local library metadata and copied video files persist on-device.
- Pink butterfly app icon generated during the build.

## Important limitations
- TikTok decides whether an individual video can be embedded or played in a third-party app. Some links, private videos, age-restricted videos, or region-restricted videos may not play. The fallback is to import a video file you have the right to use.
- Arbitrary website links are opened in an embedded web view; not every website exposes a playable video.
- This initial version stores video files locally. Cloud sync/remote storage is not configured; downloaded/imported local videos are available offline.
- The daily timer counts foreground viewing time while Nelly is open. Enable iOS Guided Access (Settings → Accessibility → Guided Access) to prevent a toddler from leaving the app.
- Change the initial admin PIN (2468) immediately in Admin. The starter PIN is not suitable for production.

## Build an unsigned IPA with GitHub Actions
1. Open the Actions tab in this repository.
2. Select Build unsigned Nelly IPA.
3. Choose Run workflow.
4. When the workflow succeeds, open its run and download the Nelly-unsigned-IPA artifact.
5. Extract the downloaded ZIP; it contains Nelly-unsigned.ipa.

The IPA is deliberately unsigned. Sign it using your own Apple signing method before installing it on your iPhone.

## Local build on macOS
Install Xcode and XcodeGen, then run:

    brew install xcodegen
    xcodegen generate
    xcodebuild -project Nelly.xcodeproj -scheme Nelly -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

## Privacy
Nelly includes no analytics, advertising SDKs, accounts, comments, public profiles, or recommendation feed. The library and watch history are stored locally on the device.
