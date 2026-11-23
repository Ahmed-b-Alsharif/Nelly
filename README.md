# Nelly

A private, parent-curated video player for a young child. Nelly targets iPhone and iOS 18.2.

## Included
- Full-screen, vertically paged feed of parent-approved local videos.
- Local video playback with looping and offline availability.
- Import video files from Photos or Files.
- First-launch parent PIN setup, PIN-protected admin, and temporary lockout after repeated incorrect attempts.
- Enable/disable, delete, rename, and reorder videos.
- Adjustable daily screen-time allowance (default 45 minutes).
- Watch history and light/dark appearance.
- Private on-device video storage in the app's Application Support folder.
- Pink butterfly app icon generated during the build.

## Adding TikTok videos
A parent can paste a TikTok video link into Admin and tap **Download video**. Nelly currently uses the independent TikWM service to resolve a public TikTok link, then downloads the returned MP4 into Nelly's private on-device library. The service is not affiliated with TikTok, can be unavailable or rate-limited, and may stop working if TikTok or the provider changes. Nelly shows an error when a link cannot be processed. Download only videos you have permission to save; this third-party service does not provide a reliable way for Nelly to verify the creator's download setting. TikTok photo slideshows are not supported by this video-only importer.

Parents can also import their own videos from Photos or Files. The child feed plays only enabled local video files; external web links are not opened in the child feed.

## Screen time and child safety
- The daily timer counts while Nelly is active in the foreground, and pauses when the app becomes inactive or a parent opens Admin.
- The first launch requires the parent to create a private 4–12 digit PIN. Choose a PIN the child cannot guess.
- Enable iOS Guided Access (Settings → Accessibility → Guided Access) to help prevent a child from leaving Nelly. Guided Access is an iOS feature and must be enabled by the parent.

## Privacy and storage
Nelly has no analytics, advertising SDKs, accounts, comments, public profiles, or recommendation feed. Video files and watch history are stored locally on the device. Imported videos are copied into the app's private Application Support storage and are not exposed as a shared Documents folder.

## Build an unsigned IPA with GitHub Actions
1. Open the Actions tab in this repository.
2. Select **Build unsigned Nelly IPA**.
3. Choose **Run workflow**.
4. When the workflow succeeds, open its run and download the **Nelly-unsigned-IPA** artifact.
5. Extract the downloaded ZIP; it contains Nelly-unsigned.ipa.

The IPA is deliberately unsigned. It must be signed with a valid Apple signing method before it can be installed on an iPhone. A successful build alone does not make an unsigned IPA directly installable.

## Local build on macOS
Install Xcode and XcodeGen, then run:

    brew install xcodegen
    xcodegen generate
    xcodebuild -project Nelly.xcodeproj -scheme Nelly -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
