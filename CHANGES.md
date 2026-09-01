# Siloquy — Change Log

Changes made to this fork relative to upstream [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax.

> **This is the macOS app's changelog.** The iOS app has its own at
> [ios/CHANGELOG.md](ios/CHANGELOG.md).

---

### 0.14.3 — 2026-09-01

#### Fixed
- **Assistant can act on what you have selected, or on your screen.** Its
  instructions referred to a section the app never sends, so the sentence
  telling it to work on your clipboard, window or selection pointed at
  nothing — asking it to summarise what was in front of you tended to hand
  back your own words. It now names the sections it is actually given,
  including the selected text, which no prompt had ever mentioned. (#58)

---

### 0.14.2 — 2026-09-01

#### Fixed
- **A single modifier key can be assigned as a shortcut again.** Setting Right ⌥
  to toggle AI enhancement — or any bare modifier to anything other than starting
  a recording — silently failed in 0.14.1. The key appeared as you pressed it,
  then vanished on release with no explanation. The same gate discarded
  onboarding's pre-assignment of Right ⌥ to the enhancement toggle on every fresh
  install, and dropped that shortcut when restoring from a backup. Combinations
  like ⌥⌘E remain enterable, and abandoning one now leaves the recorder waiting
  rather than closing on a guess. (#59)

#### Added
- **Each prompt can say what context it receives.** Clipboard and current-window
  context were single switches applied to every prompt, but a clean-up prompt
  reads context as a spelling reference while Assistant reads it as the thing you
  are asking about. Each prompt now chooses for itself, or follows the global
  switch as before; Assistant asks for both. Screen context is only captured when
  the armed prompt wants it, so a quick grammar fix no longer pays for an OCR pass
  it never uses. (#55)

---

### 0.14.1 — 2026-08-30

#### Added
- **Dictate in another language, with a keystroke.** Set up the languages you
  speak in Dictation Models, give each one a shortcut, and pressing it switches
  everything at once: the transcription model, the clean-up prompt, and the set
  of translation tiles. Nothing to configure per session — ⌘1 still means
  "clean this up properly" whatever you are speaking. (#3)
- **A model per language.** English keeps Parakeet v2, which is English-only
  but the strongest on English; other languages use Apple Speech, which ships a
  separately tuned asset per locale and tells European Portuguese apart from
  Brazilian. Dutch uses Parakeet v3, since Apple has no Dutch model. You can
  override the choice for any language. (#3)
- **Clean-up prompts written in the language you are speaking**, not translated
  into it. Portuguese (Portugal and Brazil), Spanish, French, German, Italian
  and Dutch each get a prompt that states its own conventions for numbers,
  currency, dates and times — so "quatro mil e quinhentos euros" becomes
  "4500 €" rather than something an English prompt guessed at. (#3)
- **A permanent ⌘ key for every translation.** Translation tiles are generated
  from the languages you dictate in, so the two can no longer disagree, and each
  destination keeps the same key whichever language you are speaking. The tile
  for the language you are currently speaking is shown inert — there is nothing
  to translate into the language you are already using. (#3, #25)
- **The live text preview now works with Apple Speech.** It only ever worked in
  English before, because Parakeet v2 was the one model with a streaming path.
  Apple Speech now streams too, which also means the final transcript arrives
  while you are still speaking rather than being produced from the file
  afterwards. (#49)
- **The active language is visible when Siloquy is not in front** — the notch
  flashes it on a switch, and the menu bar icon shows it. Neither appears if you
  only dictate in one language. (#3)
- Dutch, in place of Mexican Spanish. (#3)

#### Changed
- **The prompt strip has a fixed order.** Drag-and-drop assigned the shortcuts
  before, which meant a stray drag could undo the one guarantee the language
  switch is built to make. ⌘1 is always the clean-up prompt. (#3)
- Dictation Languages live in Dictation Models rather than Settings, next to
  the models they choose between. (#3)
- The "Local Model Default" prompt is retired. Since 0.13.0 the on-device
  provider picks its prompt per model, so choosing it and choosing Default
  produced identical output. (#48, #22)
- Translation prompts stored by 0.13.x are removed on first launch. Translation
  tiles are generated from your dictation languages now, so a stored one cannot
  be edited or regenerated. Re-add a destination by enabling that language.
  (#53)

#### Fixed
- **Switching dictation language now says so, even with Siloquy in front.** The
  flash under the notch was suppressed whenever the app was frontmost, on the
  assumption you could see the change in the window. That only held on the
  Dictation Models section — from Dashboard, History or AI Enhancement the
  switch happened silently. One indication now, whatever has focus. (#54)
- **Downloading one Apple Speech language no longer uninstalls the others.** A
  reservation is what stops macOS reclaiming an installed locale, and the
  download released every one of them before claiming its own — so fetching
  Spanish could silently cost you Portuguese. Harmless when there was a single
  language; not any more. (#50)
- The Apple Speech card no longer claims to be downloaded when the language you
  are about to speak is not. Download state is shown per language. (#3)
- Switching language mid-dictation is refused rather than half-applied, and the
  rows now look clickable because they are. (#3)
- Removing a dictation language asks first, and a shortcut can use any modifier
  combination — ⌥⌘E and friends were rejected before. (#3)

#### Performance
- The prompt strip and model readiness are cached rather than rebuilt on every
  keystroke and settings change, which kept Keychain lookups off the dictation
  path. (#51)

#### Internal
- A language is defined in one place instead of three. Its clean-up prompt is a
  required field on the language itself, so a new language cannot be added
  without deciding what its prompt is. (#52)
- The enhancement pipeline is documented in `docs/enhancement-pipeline.md`:
  which model a language selects, which prompt each key sends, and every prompt
  verbatim.

---

### 0.13.3 — 2026-08-16

#### Fixed
- **A selected local model that isn't downloaded now says so.** Choosing a model
  filled its radio button and looked settled, while AI enhancement quietly did
  nothing — the only clue was a Download button in the same row. The row now
  states plainly that enhancement is off, and names another model if one is
  already downloaded and ready. Selecting a model still never starts a download
  on its own. (#46)
- The app now ships the complete GNU GPL v3 text rather than only its preamble
  and a link. No change to the licence — Siloquy was and remains GPL v3. (#45)

---

### 0.13.2 — 2026-08-16

#### Fixed
- **Archiving a Mac no longer erases its history from your totals.** Retiring a
  machine used to wipe its whole contribution from the dashboard — hours, words
  and sessions all vanished, in one case dropping Time Saved from 98 hours to 52.
  Nothing was ever deleted, but a lifetime total that falls when you replace a
  laptop isn't measuring a lifetime. Archived Macs now keep counting. (#41)

#### Changed
- **Archived Macs fold out of the way.** They collapse into a single row that
  names them, expanding in place when you want it, so the device list shows the
  Macs you actually use — and un-archiving one stays on the same screen. (#41)
- **Deleting a Mac's history is now its own action**, sitting beside Restore on
  an archived machine. It asks first, naming the exact sessions and words it will
  erase. Use it for a test rig or a loaner whose dictation was never really
  yours; for a Mac you've simply replaced, leave it archived and keep the
  hours. (#41)

---

### 0.13.1 — 2026-07-17

#### Changed
- **A fresh app icon** — a cleaner, more premium take on the microphone,
  keeping the warm copper identity. (#35)

#### Fixed
- The recorder's prompt icon now greys out when enhancement is off for a
  dictation, so a translation flag no longer looks active when it isn't. (#32)
- The update dialog renders bold text in the release notes, and now shows the
  cumulative changes since your installed version — not just the newest
  release's notes. (#7, #31)

---

### 0.13.0 — 2026-07-17

#### Added
- **Translation.** Dictate in English and get the text back in another
  language. Translation prompts now sit alongside your enhancement prompts,
  each with its country flag. European Portuguese is ready out of the box; add
  Spanish, German, Italian, Dutch, or Mandarin Chinese in one tap from the
  ＋ menu. Each translation is a first-class prompt, so it takes a ⌘-number
  shortcut like any other and can be reordered, and the recorder shows the
  flag and a "Translating" status while it runs. It all runs on-device on
  Gemma 4 E4B. (#25)
- **Shortcut hints on prompts.** Every prompt tile shows its ⌘-number badge
  (⌘1 through ⌘0), and the hint now says you can drag tiles to reorder — which
  is what assigns the shortcut. (#25)

#### Changed
- **The on-device default prompt now adapts to the model you pick.** Gemma 4
  E4B gets the full polishing prompt; the smaller Gemma 4 E2B gets a lighter
  one it handles more reliably — automatically, with nothing to configure.
  (#22)
- **Gemma 4 E4B is now the recommended on-device model**, and the one a new
  install downloads during onboarding. The picker is reworded to match: E4B for
  quality, E2B as a lighter low-RAM fallback. (#21, #26)
- The Recommended dictation models list is simplified to a single obvious
  choice, Parakeet v2; the rest remain under Local, Cloud, and Custom. (#28)
- The sidebar is clearer: "AI Models" is now "Dictation Models" and
  "Enhancement" is now "AI Enhancement". (#29)

#### Fixed
- The transcription-model download no longer looks stuck on the large model
  file — a live spinner shows it's working, and the progress bar advances
  instead of freezing on the file count. (#27)
- Cancelling an on-device model download now actually stops it, instead of
  quietly running to completion. (#30)
- History now records the on-device model that actually produced the
  enhancement, instead of always showing the provider default. (#19)
- Power Modes can now switch the on-device model; the choice was previously
  ignored for the local provider. (#20)

#### Removed
- Qwen3 0.6B is no longer offered as an on-device model — it proved unreliable
  for enhancement in testing. If you had it selected, you're moved to the
  recommended model automatically. (#23)

---

### 0.12.0 — 2026-07-09

#### Added
- **Your statistics now sync across your Macs.** Sessions, words,
  words-per-minute, and keystrokes saved sync over iCloud and combine across
  every Mac you dictate on. The dashboard gains a Devices section: a per-device
  split on each metric, each Mac's own words-per-minute, and an
  "All devices / This Mac" scope toggle. A machine you've switched off can be
  archived — and later restored — so it drops out of your combined totals
  without losing its history. None of this appears on a single-Mac setup, so
  nothing changes unless you actually use more than one Mac. (#2)

#### Changed
- Enhancement now has a single "New dictations start" control — **Enhanced**
  (stays on until you turn it off) or **Raw** (each dictation starts
  un-enhanced; opt in per dictation with the ⌥ shortcut) — replacing the old
  sticky global toggle. Power Mode and trigger words still take precedence.
  (#14)

#### Fixed
- Removed the dead "Learn more" links from info tips that pointed at the
  upstream author's documentation, which doesn't apply to this fork. (#15)

---

### 0.11.2 — 2026-07-05

#### Fixed
- With "Hide Dock Icon" and "Launch at Login" both enabled, the app could come
  up with a visible Dock icon after a reboot. Menu-bar-only mode now starts
  hidden no matter how the app was launched; a normal double-click launch still
  opens the window, focused, as before. (#10)

---

### 0.11.1 — 2026-06-27

#### Changed
- The "Recommended Settings…" sheet now shows which settings will actually
  change versus the ones that already match your current setup, with a count
  in the header. Apply is disabled when everything already matches.

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
