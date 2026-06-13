<div align="center">
  <img src="Siloquy/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>Siloquy</h1>
  <p>Personal macOS dictation app — on-device speech-to-text with local AI enhancement</p>

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
  ![Architecture](https://img.shields.io/badge/arch-Apple%20Silicon%20only-orange)

  <a href="https://github.com/vmlrodrigues/Siloquy/releases/latest/download/Siloquy.dmg">
    <img src="https://img.shields.io/badge/Download_for_Mac-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac" height="40">
  </a>
</div>

---

Siloquy is a personal fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by [Prakash Joshi Pax](https://github.com/Beingpax). It transcribes speech to text on-device using whisper.cpp / Parakeet models, then passes the result through a local AI model to clean up grammar and remove disfluencies — no cloud, no API keys.

Pre-built releases are available on the [Releases](https://github.com/vmlrodrigues/Siloquy/releases) page. Or build from source — see below.

## Why this fork

[VoiceInk](https://github.com/Beingpax/VoiceInk) is an excellent app — Prakash built something genuinely useful and I'd been running it daily. But I wanted AI enhancement to run entirely in-process: no cloud API, no Ollama server to spin up, just a model that loads directly into the app and runs on Metal. VoiceInk's architecture didn't support that at the time, so I decided to build it myself.

That led me to [Google LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) and quantised Gemma and Qwen3 models. The results have been better than expected — enhancement on a typical dictation session takes 2–3 seconds and the quality is solid. Siloquy is the result of that experiment.

There's a support link in the app if you run into issues. I'm a sole developer working on this in my spare time, so I may not be able to respond to every request — bugs and pull requests via GitHub are more likely to get attention.

A big thank you to [Prakash Joshi Pax](https://github.com/Beingpax) for building VoiceInk and open-sourcing it under GPL. Without that foundation, none of this would exist.

## The name

**Siloquy** = *silicon* + *soliloquy* (with a nod to *silo*)

A speech you deliver to yourself, processed on local silicon, never leaving your machine. Triple meaning:

- **Silicon** — the hardware doing the work, entirely on-device
- **Soliloquy** — a speech addressed to no one else; what dictation really is
- **Silo** — data that stays contained, never shared with a cloud

Pronounced **SIL-oh-kwee** — like *soliloquy* with the *so-* swapped for *sil-*, landing the stress on the first syllable.

The logo concept: a single speech bubble drawn in circuit-board traces, floating in negative space.

## What's different from upstream VoiceInk

- App renamed to **Siloquy**, new icon, new bundle ID (`com.victorrodrigues.siloquy`)
- In-app purchase requirement removed — app is fully unlocked (source licence remains GPL v3)
- Sparkle auto-update and all payment/affiliate links removed
- Attribution UI updated to credit original developer
- Local on-device AI enhancement via [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) — runs in-process via Metal, no API key or server required
- English variant setting (Australian / British / Canadian / American) in the enhancement gear panel

See [CHANGES.md](CHANGES.md) for the full diff from upstream.

## Building from source

Requires macOS 14.0+, Xcode, and an Apple Developer certificate in your keychain.

whisper.cpp is expected at `~/Code/opensource/whisper.cpp`. If the XCFramework is not already built, `make local` will clone and build it automatically (takes ~10 minutes the first time).

### Local development build

```bash
make local   # → ~/Downloads/Siloquy.app
```

Builds with ad-hoc signing then re-signs with your Apple Development certificate. macOS preserves Accessibility, Microphone, and Input Monitoring permissions across rebuilds because the code identity stays stable.

### Distribution build

```bash
make release VERSION=1.0.0
```

Builds with the Developer ID Application certificate, packages as a DMG, submits to Apple for notarisation, staples the ticket, and creates a GitHub Release with the DMG attached.

Requires one-time setup before first use:
- A **Developer ID Application** certificate installed in your keychain
- An **App Store Connect API key** stored as a named keychain profile (`siloquy-notarization`)
- `create-dmg` installed (`brew install create-dmg`)

See `holding/DISTRIBUTION_SETUP.md` for step-by-step instructions.

### Docs deployment

The `docs/` directory is a self-contained static site. `make release` deploys it automatically via WebDAV at the end of the release process. To deploy manually: `make deploy-docs`. Credentials are read from a `.env` file at the repo root — copy `.env.example` to get started.

## Requirements

- macOS 14.0 (Sonoma) or later
- **Apple Silicon required** (M-series) — Intel Macs are not supported

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
