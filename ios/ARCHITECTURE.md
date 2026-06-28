# Siloquy for iOS — Architecture & Design Decisions

A reference for how the iOS app is built and *why* it's built that way. Companion
to [`README.md`](README.md) (how to run it) and GitHub issue
[#8](https://github.com/vmlrodrigues/Siloquy/issues/8) (the original feasibility
study). Status: **Phase 1 prototype** (TestFlight-bound, not yet shipped).

---

## 1. What it is

A deliberately tiny, fully on-device dictation app. One loop:

> **press Action Button → record → transcribe → clean up → copy to clipboard → save to history**

It is a companion to the macOS Siloquy app and reuses none of its code *yet* — the
shared `SiloquyCore` extraction is deferred to Phase 3 (see §8). The valuable thing
that will port is the cleanup **prompt**, not the engines.

---

## 2. Platform & runtime decisions (the big one)

The app runs entirely on **Apple's native iOS 26 frameworks** — no third-party
dependencies, no model downloads, no API keys:

| Job | Framework | Replaces (vs. the Mac app) |
|---|---|---|
| Transcription | **`SpeechAnalyzer` / `SpeechTranscriber`** (`Speech`) | Parakeet / FluidAudio |
| Cleanup LLM | **`FoundationModels`** | Gemma / LiteRT-LM |
| Trigger | **App Intent** bound to the Action Button | the global shortcut |
| History | **SwiftData** | SwiftData (same) |

**Why native, not a Parakeet + Gemma port:** Gemma 3n won't fit iOS's per-app
memory ceiling — Google's own E2B (3.0–3.7 GB) *crashes* on an 8 GB iPhone 16 Pro
Max, and E4B (4.3–4.9 GB) won't run on any shipping iPhone. Foundation Models
sidesteps the memory wall entirely (the model ships with the OS).

**The unifying constraint:** `SpeechTranscriber`, `FoundationModels`, Apple
Intelligence, *and* the Action Button all require the **same device set** —
**iPhone 15 Pro and later, iOS 26, A17 Pro / 8 GB+**. So one requirement unlocks
all three capabilities, and it's the same hardware that has the button. The app
checks `SystemLanguageModel.default.availability` at runtime and degrades to
"transcript only" on ineligible devices.

---

## 3. High-level architecture

```
                         ┌──────────────────────────┐
   Action Button  ─────▶ │  StartDictationIntent     │  (App Intent, app target)
                         │  → DictationLaunch.shared  │  bumps requestID
                         └─────────────┬──────────────┘
                                       │ (same process → shared singleton)
                                       ▼
   ┌───────────────────────────────────────────────────────────────────┐
   │  ContentView (SwiftUI)                                              │
   │   • on-screen Record button + Action-Button signal handling        │
   │   • live transcript, result, enhancement toggle, history link      │
   └─────────────┬─────────────────────────────────────────────────────┘
                 │ observes / drives
                 ▼
   ┌───────────────────────────────────────────────────────────────────┐
   │  DictationViewModel  (@MainActor, the orchestration loop)          │
   │   record → transcribe → (optional) clean → copy → save             │
   └───────┬───────────────────────────────────┬───────────────────────┘
           │                                   │
           ▼                                   ▼
 ┌──────────────────────────┐     ┌──────────────────────────────────┐
 │ SpeechTranscriptionService│     │ EnhancementService                │
 │  AVAudioEngine mic tap    │     │  FoundationModels guided gen      │
 │  → SpeechAnalyzer/Transcr.│     │  → cleaned text, with guardrail   │
 │  volatile + final text    │     │     → raw-transcript fallback     │
 └──────────────────────────┘     └──────────────────────────────────┘
           │                                   │
           └──────────────┬────────────────────┘
                          ▼
                ┌───────────────────────┐
                │ SwiftData: DictationEntry  (raw + enhanced + flag) │
                └───────────────────────┘
                          │
                          ▼
                 UIPasteboard.general  (auto-copy, foreground = silent)
```

Layering: **UI (SwiftUI) → ViewModel (orchestration) → Services (transcription,
enhancement) → Storage (SwiftData)**, with the App Intent as a side entry point
that feeds the same ViewModel.

---

## 4. Components

| File | Responsibility | Key APIs |
|---|---|---|
| `SiloquyApp.swift` | App entry; installs the SwiftData container | `App`, `.modelContainer(for:)` |
| `ContentView.swift` | The one screen + `HistoryView`; routes Action-Button signals to the VM | `@Query`, `@StateObject`, `.task`/`.onChange` |
| `DictationViewModel.swift` | The loop: record → transcribe → clean → copy → save; re-publishes the transcription service's live updates | `ObservableObject`, `Combine` |
| `SpeechTranscriptionService.swift` | Mic capture + on-device transcription; publishes volatile (live) + finalized text; installs the speech model asset | `SpeechAnalyzer`, `SpeechTranscriber`, `AVAudioEngine`, `AssetInventory` |
| `EnhancementService.swift` | On-device cleanup via guided generation, with the always-degrade fallback | `LanguageModelSession`, `@Generable`, `SystemLanguageModel.availability` |
| `DictationEntry.swift` | SwiftData model: raw text, enhanced text, used-enhancement flag, timestamp | `@Model` |
| `StartDictationIntent.swift` | Action-Button/Shortcut entry; `DictationLaunch` shared toggle signal | `AppIntent`, `AppShortcutsProvider`, `openAppWhenRun` |
| `project.yml` | XcodeGen spec — source of truth for the `.xcodeproj` | — |

---

## 5. End-to-end data flow

1. **Press** the Action Button (or on-screen Record). The intent bumps
   `DictationLaunch.shared.requestID`; the app comes to the foreground.
2. `ContentView` sees a new `requestID` and calls `vm.toggle(...)`.
3. **Start:** request mic permission → configure `AVAudioSession(.playAndRecord)`
   → `SpeechAnalyzer.start(inputSequence:)` with a `SpeechTranscriber` module. The
   mic tap converts buffers to the analyzer's format and yields `AnalyzerInput`s.
4. Results stream back as **volatile** (live preview) and **final** segments; the
   UI shows them as you speak.
5. **Press again → Stop:** finalize the analyzer, commit any trailing volatile text.
6. If enhancement is on, `EnhancementService.enhance(raw)` returns cleaned text (or
   the raw text on any failure — see §6, DD5).
7. The result is **copied to the clipboard** and **saved** as a `DictationEntry`.

---

## 6. Design decisions & rationale

**DD1 — Standalone iOS project under `ios/`, separate from `Siloquy.xcodeproj`.**
The native stack needs zero third-party dependencies, so the iOS app is fully
self-contained. Adding an iOS target to the macOS project would mean fragile
`project.pbxproj` surgery (CLAUDE.md explicitly warns against that) and tangling
with the Mac app's many SPM deps (whisper, LiteRT-LM, FluidAudio, Sparkle…). Clean
isolation now; shared `SiloquyCore` later (Phase 3).

**DD2 — XcodeGen + `project.yml` as the source of truth.** The `.xcodeproj` is a
generated build artifact, regenerable with `xcodegen generate`. Keeps the project
definition reviewable and merge-friendly; nothing hand-edited in pbxproj.

**DD3 — Native iOS 26 stack over the Parakeet + Gemma port.** See §2. The decisive
factor is the Gemma memory wall on iPhone; the native stack also means no GB-sized
downloads, no memory tuning, and a device floor that aligns perfectly with the
Action Button. The port remains a documented "Option B" fallback (issue #8) for
older-iOS or fully-uncensored needs.

**DD4 — Guided generation (`@Generable CleanedDictation`), not free-text.**
*Empirical:* free-text `respond(to:)` made the model behave like a chatbot — it
wrapped answers in "Sure, here's…", echoed the instructions, and under-cleaned.
Forcing a single `cleanedText` field via guided generation makes it return only the
cleaned text, no preamble. The `@Generable` type is file-scoped (the synthesized
conformance can't see a `private` nested type).

**DD5 — Enhancement always degrades; it never loses words or shows a refusal.**
Foundation Models' safety guardrail is a *system* filter we can't disable. Profane
or sensitive dictation can trip it in two ways: a **thrown** `GenerationError`, or
a **soft refusal** placed in the output ("I'm sorry, but as an AI…"). The service
handles both — it catches thrown errors *and* detects high-precision
assistant-refusal phrases — and falls back to the **raw, uncensored transcript**.
You keep your exact words; you never see an apology on your clipboard. *Finding:*
this is a genuine limitation of the native model and a real argument for the local
Gemma path (Option B) when clean-up of profane content matters.

**DD6 — Action Button is a toggle via an in-process App Intent + shared singleton.**
The Action Button always runs one shortcut, so the intent must *toggle* (start,
then stop). iOS only lets the mic **start in the foreground**, so the intent sets
`openAppWhenRun = true`. Because the intent is declared in the app target, it runs
in the app's process — so `DictationLaunch.shared` is the same instance the UI
observes. `ContentView` toggles on each `requestID` bump, covering both the
**cold-launch** press (handled in `.task`, since the bump precedes the view) and
the **warm** press while recording (handled in `.onChange`). An always-present
on-screen Record button exists too, because **you cannot restrict an app to
Action-Button devices** (no Info.plist key, no runtime API) — the button is an
accelerator, not a requirement.

**DD7 — Auto-copy to the clipboard on finish.** iOS has no "paste into the last
app" API, so the clipboard is the pragmatic hand-off. Foreground writes are silent
— no "Pasted from" banner, no permission dialog (those only fire on *reads*).

**DD8 — SwiftData for history.** First-party, zero-config local persistence.
`DictationEntry` stores raw + enhanced text + a `usedEnhancement` flag; `@Query`
drives the history list (tap-to-copy, swipe-to-delete).

**DD9 — The ViewModel forwards the transcription service's changes.** Nested
`ObservableObject`s don't propagate `objectWillChange` automatically, so the VM
subscribes to the service and re-emits, letting views observing the VM refresh as
partial transcription results stream in.

**DD10 — Swift 5 language mode (for now).** The realtime audio tap interacting with
the `SpeechAnalyzer` actor and `@MainActor` state trips Swift 6 strict-concurrency
checks. Swift 5 mode gives a frictionless first build; tightening to Swift 6 is a
deliberate later cleanup.

**DD11 — `en-US` hard-coded in Phase 1.** Language selection (and the
`contextualStrings` vocabulary control that replaces the Mac app's full custom
dictionary) is Phase 2.

---

## 7. Known limitations (Phase 1)

- **Guardrail on profane/sensitive input** → falls back to raw transcript (DD5).
- **No custom vocabulary** — `SpeechTranscriber` dropped full custom vocab; only
  `contextualStrings` (~100 phrase hints) is available, not yet wired up.
- **English only**, no settings, no language picker, minimal polish/haptics.
- **iOS 26 + Apple-Intelligence device required**; older devices get transcript-only
  (and would need the `DictationTranscriber` fallback, not yet added).
- The brief foreground flash on an Action-Button press is a **platform ceiling**,
  not a bug (the mic can't start in the background).

---

## 8. Roadmap

- **Phase 2:** `contextualStrings` vocabulary, language picker, prompt styles,
  settings, polish/haptics, `DictationTranscriber` fallback for older devices.
- **Phase 3:** extract a shared **`SiloquyCore`** Swift package — the cleanup
  prompts, predefined-prompt system, word-replacement/dictionary logic, output
  filtering, and history model — consumed by both the iOS and macOS apps. Engines
  and UI stay platform-specific.
- **Option B (deferred):** a Parakeet (FluidAudio) + Gemma (LiteRT-LM) path for
  older-iOS support or fully-uncensored cleanup; transcription is proven on iPhone,
  Gemma is the constraint (E2B only, at the memory edge).

---

## 9. Build & project layout

```
ios/
├── project.yml                 ← XcodeGen spec (source of truth)
├── README.md                   ← how to run on device
├── ARCHITECTURE.md             ← this file
└── Siloquy/                     ← all Swift sources + Assets.xcassets
```

- Regenerate the project: `cd ios && xcodegen generate`.
- The generated `Siloquy.xcodeproj` and build output are artifacts — consider
  gitignoring them if/when this is committed.
- Bundle id `com.victorrodrigues.siloquy.ios`; iOS 26 deployment target; iPhone-only.

---

## 10. References

- Feasibility study & sourced research: issue [#8](https://github.com/vmlrodrigues/Siloquy/issues/8)
- Apple: [SpeechAnalyzer (WWDC25 §277)](https://developer.apple.com/videos/play/wwdc2025/277/),
  [Foundation Models](https://developer.apple.com/documentation/FoundationModels),
  [App Intents `openAppWhenRun`](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)
- API surface was taken directly from the iOS 26.5 SDK `.swiftinterface` files to
  avoid guessing at these new frameworks.
