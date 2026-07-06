# Siloquy for iOS — Change Log

The iOS companion app. The macOS app's changelog lives in [CHANGES.md](../CHANGES.md).

---

### 0.1.2 — 2026-07-05

#### Fixed
- Action Button background dictation could intermittently fail to start recording
  (~1 in 4 presses), needing a re-press. The recorder now pre-arms the microphone
  and re-activates the audio session between retries, rather than retrying against
  the same half-ready session. Start failures now also record the audio route,
  permission, and hardware-ready state, to pinpoint any remaining cases.

---

### 0.1.1 — 2026-06-29

First complete TestFlight build of the Siloquy iOS companion app.

#### Added
- On-device dictation: record, transcribe with SpeechAnalyzer, refine with
  Apple Foundation Models, and copy the result — entirely on-device, no network.
- Action Button background dictation: start and stop a recording straight from
  the Action Button without launching the app, with a Dynamic Island Live
  Activity showing live status. The cleaned text lands on the clipboard via a
  companion Shortcut.
- Dictation history with tap-to-copy.
- First-run onboarding covering Action Button and Shortcut setup, plus a
  designed launch screen.

#### Requirements
- iPhone 15 Pro or later, iOS 26, with Apple Intelligence enabled.
