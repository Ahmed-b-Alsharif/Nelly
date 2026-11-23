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
Nelly does not download videos directly from TikTok. A pasted TikTok URL is only checked for guidance; it does not add a playable video to the child feed. If TikTok provides the Save Video option for a video, a parent can save it, then import that saved file into Nelly from Photos or Files. Some creators disable saving, and Nelly does not bypass those restrictions or use unofficial download services.

The child feed plays only enabled local video files. Web links are not opened in the child feed.

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
