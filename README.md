<div align="center">
  <img src="Siloquy/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>Siloquy</h1>
  <p>Personal macOS dictation app — on-device speech-to-text with local AI enhancement</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.4%2B-brightgreen)
</div>

---

Siloquy is a personal fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by [Prakash Joshi Pax](https://github.com/Beingpax). It transcribes speech to text on-device using whisper.cpp / Parakeet models, then passes the result through a local AI model to clean up grammar and remove disfluencies — no cloud, no API keys.

This fork is not distributed publicly. It is built and run locally via `make local`.

## What's different from upstream VoiceInk

- App renamed to **Siloquy**, new icon, new bundle ID (`com.victorrodrigues.siloquy`)
- License requirement removed (always treated as licensed)
- Sparkle auto-update and all payment/affiliate links removed
- Attribution UI updated to credit original developer
- Gemma 3 1B QAT local enhancement provider (in progress — see `GEMMA_INTEGRATION_FINDINGS.md`)

See [CHANGES.md](CHANGES.md) for the full diff from upstream.

## Building

Requires macOS 14.4+, Xcode, and an Apple Developer certificate in your keychain.

```bash
make local   # → ~/Downloads/Siloquy.app
```

whisper.cpp is expected at `~/Code/opensource/whisper.cpp`. If the XCFramework isn't built yet, `make local` will build it automatically (takes ~10 minutes the first time).

## Requirements

- macOS 14.4 or later
- Apple Silicon recommended (M-series) for on-device AI enhancement

## Acknowledgments

### Original Project
- [VoiceInk](https://github.com/Beingpax/VoiceInk) by [Prakash Joshi Pax](https://github.com/Beingpax) — the upstream app this fork is based on

### Core Technology
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — high-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet model implementation

### Dependencies
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — user-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) — launch at login functionality
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) — media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) — file compression utilities
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) — selected text capture
- [Swift Atomics](https://github.com/apple/swift-atomics) — thread-safe atomic operations

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE). As a GPL v3 fork, this project must remain open source under the same license.
