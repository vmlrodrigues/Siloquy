# Siloquy — Roadmap & Feature Ideas

A backlog of things we want to build into this fork, each with a short note on
the intended **approach** so the reasoning survives between sessions. Nothing
here is committed work. When an item ships, summarise it in `CHANGES.md` and
remove it (or tick it off) here.

---

## 1. Sync statistics & transcript history across machines (iCloud / CloudKit)

**Status:** proposed

**What:** Today only the dictionary (word replacements + custom vocabulary)
syncs via CloudKit. The dashboard **statistics** (`SessionMetric` — sessions
recorded, words dictated, time saved) and the **transcript history**
(`Transcription`) are local-only, so each Mac shows its own independent numbers
and its own history. Make both sync so totals and history combine across
devices.

**Why:** The "time saved / words dictated / sessions" figures look wrong when
split across two machines, and transcript history should follow you.

**Approach** — the mechanism is already proven by the dictionary store:
- In `Siloquy/VoiceInk.swift` (release branch, ~lines 215–243) there are three
  separate SwiftData stores. Flip the two that are currently `.none`:
  - the `"default"` store (`Transcription`) — `cloudKitDatabase: .none` (~line 220)
  - the `"stats"` store (`SessionMetric`) — `.none` (~line 243)
  - …to `.private("iCloud.com.victorrodrigues.siloquy")` in release and `.none`
    under `LOCAL_BUILD`, mirroring the `dictionaryCloudKit` pattern at ~lines
    224–234.
- **Deploy each store's CloudKit schema to Production** exactly as we did for the
  dictionary: run a plain dev build (CloudKit on, Development env) so SwiftData
  creates the `CD_Transcription` / `CD_SessionMetric` record types, then deploy
  Dev → Production in the CloudKit Console. Two schemas (one per store/zone),
  same container.
- **Models are already CloudKit-compatible** (audited): every property on both
  `Siloquy/Models/Transcription.swift` and `Siloquy/Models/SessionMetric.swift`
  is optional or has a default, there are no `@Attribute(.unique)` constraints,
  and no non-optional relationships. No model migration needed for sync itself.

**Decisions / gotchas to settle first:**
- **Audio won't sync.** `Transcription.audioFileURL` is a path *string*, and the
  audio files live on disk outside the store. Syncing the store carries the text
  + metadata only — on the other Mac that path won't resolve, so audio playback
  stays local to the machine that recorded it. Options: **(a)** accept text-only
  transcript sync (simplest — recommended); **(b)** move audio to
  `@Attribute(.externalStorage) Data` to sync the blobs (heavy — audio is large,
  eats iCloud quota). Recommend (a).
- **Privacy posture.** Transcripts are everything you've ever dictated; syncing
  uploads all of it to iCloud (private DB, but still). Stats are
  low-sensitivity, transcripts are not. Recommend making **transcript sync
  opt-in** via a Settings toggle, while **stats sync by default**. They're
  separate stores, so they can be gated independently.
- **Migration vs sync duplication.** `SessionMetricMigrationService` back-fills
  one `SessionMetric` per completed `Transcription`, guarded by a *per-machine*
  `UserDefaults` flag. Once transcripts sync, both Macs see the same transcripts
  and could each back-fill the same metrics → duplicates. The migration already
  skips transcripts that already have a `SessionMetric` (matched on
  `transcriptionId`), but cross-machine timing can still race. Add a
  dedup-by-`transcriptionId` safeguard before enabling transcript sync.

**Effort:** Small code change (config flip + a toggle), but two CloudKit schema
deploys and careful two-Mac testing. The dedup wrinkle is the only real design
work.

---

## 2. Multi-language dictation (Parakeet V3) with a language-switch shortcut

**Status:** proposed

**What:** Support multilingual transcription via the Parakeet **V3** model (V2
is English-only), and let the user switch the active recording language quickly
— a keyboard shortcut pressed around the time you start recording, plus a
settings picker.

**Why:** Dictate in more than one language without digging through settings each
time.

**Approach** — most of the engine is *already there*; this is mainly UI + a hotkey:
- **V3 is already defined.** `Siloquy/Models/TranscriptionModelRegistry.swift`
  (~lines 20–42) lists both `parakeet-tdt-0.6b-v2` (English) and
  `parakeet-tdt-0.6b-v3` (multilingual). `FluidAudioModel`
  (`Siloquy/Models/TranscriptionModel.swift`) carries `isMultilingualModel` +
  `supportedLanguages`, and `Siloquy/Models/LanguageDictionary.swift` (~lines
  109–117) holds the 25-language list plus `"auto"`.
- **Transcription already honours a language.**
  `Siloquy/Transcription/FluidAudio/FluidAudioTranscriptionService.swift`
  (`transcribe(...)`) already reads `UserDefaults "SelectedLanguage"`, converts
  it via `FluidAudioModelManager.languageHint()` (V3-only; returns `nil` for
  V2), and passes `language: languageHint` into `asrManager.transcribe(...)`.
  **So no transcription-path changes are needed** — the model just needs to be
  V3 and `SelectedLanguage` set.
- **What's actually missing:**
  1. **Language picker UI** in `Siloquy/Views/ModelSettingsView.swift` — there's
     already an `@AppStorage("SelectedLanguage")` with no control. Add a Picker
     populated from the selected model's `supportedLanguages` (incl. "auto"),
     shown only when a multilingual model is selected. Also let the user choose
     which languages belong to the quick-switch set.
  2. **Cycle-language shortcut** — add a `.cycleLanguage` case to
     `Siloquy/Shortcuts/ShortcutAction.swift`, register it like the other
     actions, and handle it in `RecordingShortcutManager.handleGlobalShortcut()`
     (~lines 275–298): advance `SelectedLanguage` through the user's enabled set
     and show a brief HUD/toast of the new language. Because the service reads
     `SelectedLanguage` at record time, switching it just before starting a
     recording takes effect immediately.
  3. Ensure V3 is downloadable/selectable, and that
     `TranscriptionModelManager.ensureSelectedLanguageIsSupported(by:)` (already
     exists) keeps the selection valid when switching models.

**UI design notes (the part that needs thought):**
- For "switch language with a key", the lowest-friction option is a **cycle**
  key (press to advance to the next enabled language) with a HUD showing the
  now-armed language. A "hold modifier + number" picker is more powerful but
  more to learn. Start with cycle + HUD.
- Surface the *current* language on the recorder HUD / menu bar so you can see
  which language is armed before you speak.

**Effort:** Smaller than it looks — the ASR plumbing is done. Mostly a Settings
picker, one new shortcut action, and a small HUD. Switching the default V2 → V3
is a model download + a default change.

---

## 3. Translate dictation into another language (e.g. English → Portuguese)

**Status:** proposed (researched — local is viable)

**What:** Dictate in one language (the one you're fastest in, e.g. English) and
have the result written in another (e.g. Portuguese). Distinct from #2: that one
transcribes *in* a chosen language; this one transcribes in language A and
**translates** to language B.

**Why:** You can dictate fluently in English but sometimes need the output in
Portuguese (or another language you write less confidently).

**Research findings (June 2026):**
- **Local is viable with the model we already ship.** The default enhancement
  model, **Gemma 4 E2B** (`litert-community/gemma-4-E2B-it`, ~2.59 GB, via
  LiteRT-LM), is strongly multilingual — ~35+ languages out of the box,
  pre-trained on 140+ (Portuguese is high-resource and well covered). A
  2.3B-effective-param instruction model translates EN→PT acceptably via
  prompting. So translation can run **fully offline, no API key**, reusing the
  model already on disk.
- If E2B quality disappoints, **Gemma 4 E4B** is the larger sibling in the same
  LiteRT-LM family — better multilingual quality, just a bigger download, **same
  runtime** (a trivial catalog addition).
- **Dedicated translation models** (higher quality per size): **NLLB-200**
  (Meta — 200 languages, 600M/1.3B distilled, the quality+coverage champion) or
  **Opus-MT** (~300 MB per pair, very fast, lower quality). Caveat: these run on
  **CTranslate2 / ONNX**, *not* LiteRT-LM — adopting one means a **second
  inference runtime** in the app (extra dependency, packaging, model
  management). A real lift; only worth it if the Gemma path proves inadequate.
- **Online fallback** (last resort): route translation to a configured cloud
  provider (the app already supports cloud AI providers with API keys in
  `Siloquy/Services/AIEnhancement/AIService.swift`). Best quality, but breaks the
  offline / no-API-key ethos and adds key management — keep it an explicit
  opt-in, never the default.

**Approach (recommended path):**
- **Translation is "just another prompt mode."** Siloquy's enhancement is
  provider-agnostic and prompt-driven (`CustomPrompt.swift`,
  `PredefinedPrompts.swift`, routed through `AIEnhancementService` →
  `GemmaService`). A translation feature is largely: a target-language choice + a
  prompt like *"Translate the following text to Portuguese. Output only the
  translation, no commentary."* (optionally folding in the existing grammar
  cleanup), run through the `GemmaService.enhance(...)` we already have. No new
  model, runtime, or network for v1.
- **v1:** add a "Translate to…" mode — a predefined prompt + a target-language
  picker in enhancement settings (reuse the language list from #2), defaulting to
  on-device Gemma 4 E2B, wired as a Power Mode so it's toggleable per context.
- **v2 (only if needed):** expose Gemma 4 E4B as a higher-quality local option;
  evaluate a dedicated NLLB path behind a feature flag for pro-grade quality.

**Open questions:** Does E2B's EN→PT quality clear the bar in practice? (Cheap to
check — run a few real dictations through a translate prompt *before* building
UI.) Should translation *replace* or *follow* grammar cleanup (one prompt vs two
passes)? This combines naturally with #2 — transcribe-language + output-language
together is the full pipeline.

**Effort:** v1 is **small** — a prompt + a language picker + Power Mode wiring on
the existing local model. The dedicated-model (NLLB / CTranslate2) path is the
expensive one and is deliberately deferred.

**Sources:** [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4),
[google/gemma-4-E2B-it](https://huggingface.co/google/gemma-4-E2B-it),
[Best Local LLMs for Translation](https://insiderllm.com/guides/best-local-llms-translation/),
[Picovoice: open-source translation for mobile/embedded](https://picovoice.ai/blog/open-source-translation/).
