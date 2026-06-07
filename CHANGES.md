# Siloquy — Change Log

Changes made to this fork relative to upstream [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax.

---

## Completed

### App Identity & Rename (2026-06-07)

**App renamed from VoiceInk to Siloquy throughout.**

#### Signing & Build (project.pbxproj)
- `DEVELOPMENT_TEAM`: `V6J6A3VWY2` → `BWSYTSDVGC` (Victor Rodrigues, Apple Developer)
- `PRODUCT_BUNDLE_IDENTIFIER` (main): `com.prakashjoshipax.VoiceInk` → `com.victorrodrigues.siloquy`
- `PRODUCT_BUNDLE_IDENTIFIER` (tests): `com.prakashjoshipax.VoiceInkTests` → `com.victorrodrigues.siloquy.tests`
- `PRODUCT_BUNDLE_IDENTIFIER` (UITests): `com.prakashjoshipax.VoiceInkUITests` → `com.victorrodrigues.siloquy.uitests`
- `PRODUCT_NAME`: `$(TARGET_NAME)` → `Siloquy` (main target only)
- `INFOPLIST_KEY_CFBundleDisplayName`: `VoiceInk` → `Siloquy`
- `TEST_HOST` updated to reference `Siloquy.app`

#### whisper.cpp Path (Makefile + project.pbxproj)
- Removed `~/VoiceInk-Dependencies` intermediary directory
- `WHISPER_CPP_DIR` now points directly to `$(HOME)/Code/opensource/whisper.cpp`
- XCFramework path in project file updated to match
- Note: you can now delete `~/VoiceInk-Dependencies` from your home directory

#### Info.plist
- Added `CFBundleDisplayName`: `Siloquy`
- Microphone, browser, and screen recording usage descriptions updated to say "Siloquy"
- Removed Sparkle auto-update feed (SUFeedURL, SUPublicEDKey — pointed to upstream beingpax server)
- Disabled Sparkle auto-update checks (`SUEnableAutomaticChecks = false`)

#### App Icon
- Source: `holding/Gemini_Generated_Image_ldydocldydocldyd.png` (2048×2048)
- Cropped gray border (original content occupied ~1574×1574 of the 2048 canvas)
- Generated all 7 sizes: 16, 32, 64, 128, 256, 512, 1024 px
- Replaced all images in `VoiceInk/Assets.xcassets/AppIcon.appiconset/`
- Trimmed source saved to `holding/icon_trimmed_source.png`

#### Bundle ID & Logger Subsystem (Swift — ~30 files)
- All `com.prakashjoshipax.voiceink` → `com.victorrodrigues.siloquy`
  (Logger subsystems, queue labels, NSUserInterfaceItemIdentifier values)
- All `com.prakashjoshipax.VoiceInk` → `com.victorrodrigues.siloquy`
  (file path components, CloudKit container ID: `iCloud.com.victorrodrigues.siloquy`)
- Window autosave names: `VoiceInkMainWindowFrame` / `VoiceInkHistoryWindowFrame` → `Siloquy*`

#### User-Visible Strings (Swift)
- Window titles: "VoiceInk" / "VoiceInk Onboarding" / "VoiceInk — Transcription History" → Siloquy
- Alert texts in `VoiceInk.swift`
- `AppIntents`: ToggleMiniRecorderIntent and DismissMiniRecorderIntent
- `PowerModeView`: "VoiceInk workflow" → "Siloquy workflow"
- `PermissionsView`: all VoiceInk → Siloquy in permission descriptions
- `MetricsContent`: "VoiceInk Insights", "VoiceInk sessions completed", etc.
- `ContentView`: sidebar label and navigation title
- `MenuBarView`: "Quit VoiceInk" → "Quit Siloquy"
- `DictionaryQuickAddPanel`: placeholder text
- `CustomSoundManager`: `VoiceInk/CustomSounds` → `Siloquy/CustomSounds` (file path)
- `VoiceInkCSVExportService`: export filename → `Siloquy-transcription.csv`
- `TranscriptionPipeline`: trial-expired message updated

#### EmailSupport.swift
- Support email: `support@tryvoiceink.com` → `support@jeunj.com`
- Subject: "VoiceInk Support Request" → "Siloquy Support Request"
- Common-issues link → GitHub issues

#### LicenseManagementView.swift (rewritten)
- Removed: "Upgrade to Pro" purchase button, BuyMeACoffee tip jar, Polar license portal
- Kept: License key activation (validates against original VoiceInk Pro licensing server)
- Added: Attribution section crediting Prakash Joshi Pax / VoiceInk with link to original repo

#### AnnouncementsService.swift
- Announcements URL updated (previously pointed to beingpax's GitHub Pages)
- `enableAnnouncements` default changed to `false` (no announcements server for this fork)

#### Test Files
- Copyright headers in `VoiceInkTests.swift`, `VoiceInkUITests.swift`, `VoiceInkUITestsLaunchTests.swift`:
  "Created by Prakash Joshi" → "Created by Victor Rodrigues"

### Local On-Device AI Enhancement via LiteRT-LM (2026-06-08)

Replaces the planned Gemma 3 1B QAT integration with a more capable
multi-model local provider using Google's LiteRT-LM Swift package.

#### New files
- `Siloquy/Services/AIEnhancement/GemmaService.swift` — owns the LiteRT-LM
  engine lifecycle, model catalogue, download/import/delete, and enhancement
- `Siloquy/Models/EnglishVariant.swift` — enum for English spelling variants

#### Swift Package (project.pbxproj)
- Added `google-ai-edge/LiteRT-LM` (pinned to `main` branch)
- `GIT_LFS_SKIP_SMUDGE=1` added to `make local` to skip Android LFS objects
  that are missing from GitHub's LFS server

#### Model catalogue (`GemmaService.swift`)
Two models available for in-app download:
- **Qwen3 0.6B** (497 MB, mixed int4) — `litert-community/Qwen3-0.6B`
- **Gemma 4 E2B** (2.4 GB) — `litert-community/gemma-4-E2B-it-litert-lm` — recommended

Models stored at `~/Library/Application Support/Siloquy/Models/`.
Each supports download with progress bar, local file import, and deletion.
HTTP status code validated on download — 4xx responses are rejected before
the file is saved to disk.

#### Engine lifecycle
- `Engine` actor initialised lazily; GPU (Metal) tried first, CPU fallback
  on failure (e.g. after a binary rebuild invalidates the Metal shader cache)
- Engine state surfaced in the settings UI: warming up / ready / error + retry
- Switching models tears down the old engine before initialising the new one

#### Qwen3 thinking mode fix
Qwen3 0.6B has chain-of-thought reasoning on by default. Added a
`messageSuffix` field to `LocalModel`; Qwen3 gets `" /no_think"` appended
to every user message to switch to direct-answer mode.

#### Provider & UI
- `AIProvider.gemmaLocal = "Local (On-device)"` added to `AIService.swift`
- Positioned between Ollama and Local CLI in the dropdown
- Routed in `AIEnhancementService.makeRequest()`
- Settings UI in `APIKeyManagementView.swift` (per-model download/import/delete,
  engine status banner, radio selection)

#### Entitlements
- `com.apple.developer.kernel.increased-memory-limit = true` added to
  `Siloquy/Siloquy.entitlements` (required for models ≥ ~500 MB; not applied
  to local/ad-hoc builds, which are unsandboxed and don't need it)

---

### English Variant Setting (2026-06-08)

- `EnglishVariant` enum (American / Australian / British / Canadian)
- `@Published var englishVariant` on `AIEnhancementService`, persisted to
  UserDefaults key `"englishVariant"`
- Injected as a `LANGUAGE:` instruction in `getSystemMessage(for:)`, covering
  all prompts in one place; American appends nothing (LLM default)
- Language picker added to `EnhancementSettingsPanel` (the gear panel) as a
  new "Language" section at the top

---

### UI & Branding Cleanup (2026-06-08)

- Sidebar item "Siloquy Pro" renamed to "About Siloquy"; `checkmark.seal.fill`
  icon replaced with `info.circle.fill`
- README: added name etymology section — silicon + soliloquy (+ silo), triple
  meaning, pronunciation SIL-oh-kwee

---

## Not Changed (intentional)

| Item | Reason |
|------|--------|
| Xcode target/scheme name ("VoiceInk") | Internal tooling only; no user impact |
| `.xcodeproj` filename | Would require Makefile and git history changes for no benefit |
| UserDefaults keys (`VoiceInkLicenseRequiresActivation`, etc.) | Changing breaks existing user preferences on upgrade |
| Internal Swift class names (`VoiceInkEngine`, `VoiceInkEngineError`, `VoiceInkButton`) | Structural refactor; no user impact |
| `tryvoiceink.com` "learn more" links | Original docs remain relevant; no Siloquy docs site |
| LicenseViewModel.swift Polar API endpoint | License validation still works against original server |

---

## Pending

Nothing currently tracked.
