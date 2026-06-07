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

- [ ] Add LiteRT-LM Swift package
- [ ] Implement `GemmaService.swift` (Gemma 3 1B QAT local enhancement)
- [ ] Add `AIProvider.gemmaLocal` enum case
- [ ] Route in `AIEnhancementService`
- [ ] Enhancement settings UI for model download
- [ ] Add increased-memory-limit entitlement
