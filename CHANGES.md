# Siloquy — Change Log

Changes made to this fork relative to upstream [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax.

---

### 0.11.0 — 2026-06-27

#### Added
- Recommended settings: onboarding now ends with a "One last thing" step that
  applies a set of sensible defaults in one click, and Settings → General has a
  new "Recommended Settings…" button that does the same any time. The default
  enhancement model is unchanged.
- The onboarding Keyboard Shortcuts step now also sets up the enhancement
  toggle, pre-assigned to Right Option (⌥). You still choose your own recording
  shortcut, and you can change or clear the enhancement shortcut.

#### Fixed
- On a fresh install, the Screen Recording onboarding step no longer opens
  System Settings at the same moment macOS shows its own permission dialog —
  the two were racing and left the dialog stuck. The dialog now appears on its
  own the first time; later attempts open System Settings instead.

---

### 0.10.5 — 2026-06-24

#### Added
- Gemma 4 E4B is now available as an optional local enhancement model —
  higher quality, especially for other languages, at a larger download
  (3.4 GB) and more memory than the default. Download it from
  Settings → AI Models. The default model stays Gemma 4 E2B.
- The local model picker now shows a short note on what each model is best
  for.

---

### 0.10.4 — 2026-06-23

#### Fixed
- iCloud sync of your dictionary (word replacements and custom vocabulary)
  across machines now works. v0.10.3 declared the iCloud entitlements but was
  missing `com.apple.application-identifier`, so CloudKit couldn't initialise
  the container and sync never started; this adds it.
- The in-app update window now shows clean, formatted release notes instead of
  rendering the GitHub release web page.

---

### 0.10.3 — 2026-06-19

#### Fixed
- iCloud sync of your dictionary (word replacements and custom vocabulary)
  across machines now works. CloudKit requires the Push Notifications
  entitlement for its change tracking, and the release build was missing it —
  so sync silently never started. Added the `aps-environment` entitlement and a
  provisioning profile that authorises it.

---

### 0.10.2 — 2026-06-14

#### Fixed
- When Siloquy launches at login, it now starts in the background with just the
  menu-bar icon — no Dock icon — like other startup menu-bar apps. Opening it
  manually still shows the window and Dock icon as before.

---

### 0.10.1 — 2026-06-14

#### Fixed
- Local AI enhancement no longer gets stuck after a long dictation. A long
  local enhancement could exceed the short default timeout; the timed-out
  generation left the on-device model engine wedged, so every later
  enhancement failed until the app was restarted. The engine now recovers on
  its own, the local timeout scales with the length of the dictation (so long
  ones aren't cut off mid-way), and only one enhancement runs at a time.

---

### 0.10.0 — 2026-06-14

#### Onboarding
- Onboarding now downloads both on-device models the app needs — the Parakeet
  V2 transcription model and the Gemma 4 E2B enhancement model — so dictation
  and AI cleanup both work offline as soon as setup finishes
- Removed the Input Monitoring step: Accessibility (required for pasting)
  already grants the input access the global shortcut needs, so the separate
  grant was redundant — and couldn't be auto-registered once Accessibility was
  on anyway
- Onboarding resumes where you left off after the macOS-forced restart that
  follows granting Screen Recording, instead of starting over
- "Skip Tour" relabelled "Skip Setup"
- Removed a spurious "keystroke receiving" prompt that appeared on the welcome
  screen before onboarding asked for it

#### Permissions
- Input Monitoring is now detected with a real event-tap probe, fixing a
  macOS 26 false positive where the app reported the permission as granted when
  it was not
- Opening the Input Monitoring permission now correctly registers Siloquy in
  System Settings so it can be enabled
- Clearer Input Monitoring help text

#### App launch & Dock
- Fixed a duplicate Dock icon in menu-bar-only mode, caused by switching the
  activation policy at launch
- First launch now defaults to menu-bar-only mode
- No stray focus ring on the first window at launch

#### Privacy — screen context is now opt-in
- Screen-context capture is off by default and runs only when explicitly
  enabled. Previously the app reached for ScreenCaptureKit on every recording
  whenever Screen Recording was granted, which triggered macOS's periodic
  "bypass the window picker" consent dialog

#### Enhancement
- Provider-aware prompt routing: local providers (Gemma, Ollama, Local CLI)
  receive a leaner prompt with worked self-correction examples tuned for small
  on-device models; cloud providers keep the existing detailed prompt; an
  explicit user prompt selection always overrides the automatic choice

#### Apple Silicon only
- Builds restricted to `arm64` (`LocalBuild.xcconfig` and the Makefile release
  target) — Intel Macs are not supported; the binary no longer contains an
  `x86_64` slice
- README and docs updated to state this as a hard requirement

#### Reliability
- Single-instance enforcement: the app terminates any existing instance with
  the same bundle ID at launch, preventing the duplicate paste that occurred
  when two copies both intercepted the global recording shortcut
- Parakeet download progress now advances by file count, so the bar moves
  steadily instead of sticking near the start and then jumping

#### Help & "Copy System Info"
- "Copy System Info" header corrected from `VOICEINK SYSTEM INFORMATION` to
  `SILOQUY SYSTEM INFORMATION`
- Help & Resources: removed the "Recommended Models" and "YouTube Videos &
  Guides" links; Documentation now points to `https://siloquy.jeunj.com` and
  Feedback to GitHub Issues

#### Docs site & deploy tooling
- New self-contained static site at `docs/index.html`
- `make deploy-docs` uploads the site via WebDAV; runs automatically at the
  end of `make release`
- `tools/deploy-docs.sh` supports `deploy`, `mount`, and `unmount`; upload
  failures are non-fatal

---

### 0.9.5 — 2026-06-08

- Sparkle auto-update enabled with signed appcast hosted on GitHub
- Download button added to README and docs site
- DMG filename simplified (version number dropped from filename)
- Input Monitoring permission added to onboarding flow

---

### 0.9.4 — 2026-06-08

- English variant setting added (Australian / British / Canadian / American)
  in the Enhancement gear panel — AI output uses the selected spelling

---

### 0.9.3 — 2026-06-08

- Local on-device AI enhancement via Google LiteRT-LM
- Two models available for in-app download: Qwen3 0.6B (497 MB) and
  Gemma 4 E2B (2.4 GB, recommended)
- Engine runs in-process via Metal (GPU), CPU fallback on failure
- No API key or server required

---

### 0.9.2 — 2026-06-08

- App renamed from VoiceInk to Siloquy throughout (bundle ID, display name,
  window titles, logger subsystems, file paths, export filenames)
- New app icon
- Bundle ID: `com.victorrodrigues.siloquy`
- In-app purchase requirement removed — app fully unlocked
- Attribution UI updated to credit Prakash Joshi Pax / VoiceInk

---

### 0.9.1 — 2026-06-08

- Initial private fork of VoiceInk
- Signing and build configuration updated for personal Apple Developer account
- whisper.cpp path updated to local directory structure
- Support email and issue links updated
