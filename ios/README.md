# Siloquy for iOS — Phase 1 (prototype)

A deliberately tiny, fully on-device dictation app:

**record → transcribe → clean up → copy to clipboard → save to history**

It uses only Apple's native iOS 26 stack — **no model downloads, no third-party
dependencies, no API keys**:

- **`SpeechTranscriber` / `SpeechAnalyzer`** (Speech framework) — on-device transcription
- **Foundation Models** — on-device text cleanup, with a guardrail fallback to the raw transcript
- **App Intent + App Shortcut** — so the **Action Button** can launch straight into recording

## Requirements

- **A physical iPhone 15 Pro or newer**, on **iOS 26** (Apple-Intelligence device — needed for both Foundation Models and SpeechTranscriber).
- **Xcode 26+** with the iOS 26 SDK.
- An Apple Developer account for on-device signing (free personal team works for development).

> The Simulator can run the UI and may run Foundation Models on an Apple-silicon
> Mac, but **transcription quality and the real experience should be validated on
> a physical device.**

## Run on your iPhone — without Xcode

Once signing is set up (below), the fastest dev loop needs no GUI:

```bash
cd ios
./run-device.sh              # build (Debug), install, and launch on the paired iPhone
./run-device.sh --console    # …and stream the app's logs to the terminal
```

Xcode.app must be *installed* (it holds `xcodebuild`/`devicectl`) but never has to
be open. Requires `testflight.config` (the App Store Connect API key — same file
`testflight.sh` uses) so provisioning refreshes headlessly. Keep the phone
unlocked and on the same Wi-Fi (or plugged in) so the install connection holds.

## Open & run in Xcode

```bash
cd ios
xcodegen generate      # creates Siloquy.xcodeproj (already generated; re-run after editing project.yml)
open Siloquy.xcodeproj
```

In Xcode:

1. Select the **Siloquy** target → **Signing & Capabilities** → set your **Team**
   (and adjust the bundle id `com.victorrodrigues.siloquy.ios` if needed).
2. Plug in your iPhone, select it as the run destination.
3. **Run** (⌘R). First launch will prompt for **microphone** permission; the speech
   model downloads on first use if it isn't already installed.

## Bind the Action Button

Once installed: **Settings → Action Button → Shortcut → choose the "Dictate"
shortcut** (vended by the app). Pressing the Action Button then opens Siloquy and
starts recording. iOS only allows the mic to *start* in the foreground, so a brief
app-launch flash is expected — that's the platform ceiling, not a bug.

There's also an on-screen Record button, so the app is fully usable without the
Action Button.

## What Phase 1 does / doesn't do

**Does:** one-screen record/stop, live (volatile) partial transcript, AI cleanup
toggle (default on), auto-copy to clipboard, basic SwiftData history (tap-to-copy,
swipe-to-delete), Action Button launch, graceful "not supported / cleanup off"
messaging on ineligible devices.

**Doesn't yet (later phases):** custom vocabulary (`contextualStrings`), language
selection, prompt styles, settings, polish/haptics, and extracting a shared
`SiloquyCore` package with the macOS app.

## Notes

- `Siloquy.xcodeproj` is **generated** from `project.yml` — treat `project.yml` as
  the source of truth. If you commit this later, consider gitignoring the
  generated `.xcodeproj` and build output.
- Swift language mode is **5.0** for a frictionless first build; tightening to
  Swift 6 strict concurrency is a later cleanup.
