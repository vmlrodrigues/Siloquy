# Siloquy — Project Context for Claude

## What This Project Is

**Siloquy** is a personal fork of [VoiceInk](https://github.com/Beingpax/VoiceInk), a macOS dictation app that uses on-device speech-to-text (via whisper.cpp / Parakeet models) and then passes the raw transcription through an AI model to clean up grammar and disfluencies.

The fork lives at: `https://github.com/vmlrodrigues/Siloquy`  
The upstream source: `https://github.com/Beingpax/VoiceInk`  
License: **GPL v3** — any distributed fork must also be GPL v3 and open source.

The goal of this fork is to integrate **Google's Gemma 3 1B QAT model** as a local, offline enhancement provider — no API key, no server process, no internet required. The upstream VoiceInk uses cloud providers (Claude, GPT, Gemini API) or a locally-running Ollama server for enhancement. We want the model running directly in-process via **Google LiteRT-LM**.

---

## Developer Account Details

See `DEVELOPER.local.md` (gitignored) for Apple ID, Team ID, signing cert, and support email.

- **Bundle ID:** `com.victorrodrigues.siloquy`

For notarized distribution (outside App Store), a **Developer ID Application** certificate is required and is installed (`Developer ID Application: Victor Rodrigues (9N354A3UZK)`); `make release` uses it to sign and notarize. The Apple Development cert is used separately for local builds (`make local`).

---

## Build Setup

**Project root:** `~/Code/personal/Siloquy/`

**whisper.cpp** is built and lives at `~/Code/opensource/whisper.cpp`. The Makefile and Xcode project reference it directly — no symlink needed.

**Build commands:**
```bash
make local    # builds ad-hoc, then re-signs with Apple Development cert → ~/Downloads/Siloquy.app
make build    # unsigned build to Xcode DerivedData
```

**Note on signing:** `make local` builds with ad-hoc signing (xcodebuild doesn't need the Apple ID logged in) and then immediately re-signs the copied app with `codesign` using the Apple Development cert from the keychain (see `DEVELOPER.local.md`). This gives a stable code identity so macOS preserves Accessibility, Microphone, and Input Monitoring permissions across rebuilds.

The `make local` build will skip whisper if the XCFramework is already built at:
```
~/Code/opensource/whisper.cpp/build-apple/whisper.xcframework
```

If it's missing, `make local` will clone and build it automatically (takes ~10 min).

**Note on Xcode internals:** The Xcode project file is `Siloquy.xcodeproj` and the scheme is `Siloquy.xcscheme`. However, the Xcode **target** is still internally named `VoiceInk` (as are `VoiceInkTests` and `VoiceInkUITests`) — these are internal Xcode target identifiers with no effect on the shipped app. Renaming targets requires editing `project.pbxproj` extensively and is not worth the risk.

---

## The Enhancement Feature (Existing Architecture)

Siloquy's enhancement system takes raw transcribed text and passes it through an AI model to clean up grammar and remove disfluencies. The pipeline is:

```
Audio → Whisper/Parakeet transcription → AI enhancement → paste result
```

The architecture is enum-based. Each AI provider is a case in `AIProvider` (in `AIService.swift`). The routing lives in `AIEnhancementService.makeRequest()`. Adding a new local model backend means:

1. A new service class (`GemmaService.swift`) — modelled on `OllamaService.swift`
2. A new enum case in `AIProvider`
3. One new `case` branch in the switch in `AIEnhancementService.swift`
4. A settings UI section for model download

**Key files for the enhancement feature:**
- `Siloquy/Services/AIEnhancement/AIEnhancementService.swift` — orchestration, routing, retries
- `Siloquy/Services/AIEnhancement/AIService.swift` — provider enum, model lists, API key management
- `Siloquy/Services/OllamaService.swift` — template to follow for a new local provider
- `Siloquy/Views/EnhancementSettingsView.swift` — settings UI
- `Siloquy/Models/CustomPrompt.swift` — prompt system (provider-agnostic, no changes needed)

---

## The Integration Goal: Gemma 3 1B QAT via LiteRT-LM

**Full research findings are in `GEMMA_INTEGRATION_FINDINGS.md` in this repo.** Read that file before writing any code.

### Model

`litert-community/Gemma3-1B-IT` — int4 QAT variant  
https://huggingface.co/litert-community/Gemma3-1B-IT  
Size: **529 MB** on disk  
Format: `.litertlm` (Google's LiteRT runtime format)

### Why this model

- Typical dictation in this project: **~100–160 words** (see the findings doc for context)
- Upper ceiling: **400–600 words** for long sessions
- At 600 words, total context needed is ~1,700 tokens — well within LiteRT-LM's default KV cache
- QAT means int4 quality matches full-precision BF16 — no quality degradation on short instruction tasks
- Expected enhancement time: **2–3 seconds** for typical sessions, **under 10 seconds** for the 600-word ceiling, on any M-series chip

### Framework

**Google LiteRT-LM**  
Swift Package: `https://github.com/google-ai-edge/LiteRT-LM`  
Minimum version: `0.13.1` (first stable macOS release)  
macOS minimum: 12.0 (Monterey)

**Important:** The Swift API is labelled "Early Preview" in the repo README. The underlying C++ engine is production-grade (powers Chrome, Pixel Watch). For personal use the API stability risk is acceptable — pin to a specific version tag and update deliberately.

**Known setup issue:** LiteRT-LM distributes its XCFramework via Git LFS. Xcode's package resolution fails if Git LFS is not installed. Run this once before adding the package:
```bash
brew install git-lfs && git lfs install
```

### The Swift API (what you'll be using)

```swift
import LiteRTLM

// 1. Configure — point at the .litertlm file on disk
let config = EngineConfig(modelPath: "/path/to/model.litertlm")
config.backend = .gpu  // Metal on macOS

// 2. Initialise once (takes 3–8 seconds on first call, then stays warm)
let engine = Engine(engineConfig: config)
try await engine.initialize()

// 3. Create a conversation with the system prompt
let convConfig = ConversationConfig(
    systemMessage: Message(.text("Fix grammar and remove disfluencies. Return only the corrected text."))
)
let conversation = try engine.createConversation(with: convConfig)

// 4. Send transcribed text, stream the enhanced result
for try await chunk in conversation.sendMessageStream(Message(transcribedText)) {
    // append chunk.text to result
}
```

System prompt is passed in `ConversationConfig.systemMessage`. Transcribed text is sent as the user message. The existing prompt system (`CustomPrompt.finalPromptText`) feeds directly into `systemMessage` unchanged.

---

## What Needs to Be Built

### 1. `GemmaService.swift`
New file at `Siloquy/Services/AIEnhancement/GemmaService.swift`.

Responsibilities:
- Own an `Engine` instance (LiteRT-LM actor)
- Lazy-initialise on first use (background task, show "warming up" state)
- Expose `enhance(_ text: String, withSystemPrompt: String, timeout: TimeInterval) async throws -> String`
- Expose `isModelDownloaded: Bool` computed from the expected file path
- Expose `downloadModel(progress: @escaping (Double) -> Void) async throws` for the first-run 529 MB download
- Store the model at `~/Library/Application Support/Siloquy/Models/gemma3-1b-it-int4-qat.litertlm` (inside sandbox container — no extra file entitlements needed)

Reference: `Siloquy/Services/OllamaService.swift` for the structural pattern.

### 2. `AIService.swift` — add the new provider

```swift
// In the AIProvider enum:
case gemmaLocal

// provider properties:
case .gemmaLocal:
    return "Gemma (Local)"           // displayName
    return false                      // requiresAPIKey
    return ["Gemma 3 1B (QAT)"]      // availableModels
```

### 3. `AIEnhancementService.swift` — add the routing case

In `makeRequest(text:mode:)`, add to the existing switch:
```swift
case .gemmaLocal:
    result = try await gemmaService.enhance(
        text,
        withSystemPrompt: systemMessage,
        timeout: timeout
    )
```

### 4. `EnhancementSettingsView.swift` — model download UI

Add a section for the Gemma Local provider that shows:
- "Not downloaded" / download button + progress bar (529 MB)
- "Ready" / model version once downloaded
- GPU/CPU backend toggle (optional)

### 5. Entitlements

Add to `Siloquy/Siloquy.entitlements`:
```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```
Required for models ≥ ~500 MB in sandboxed apps. Available on all paid Apple Developer accounts without a special request.

---

## Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description>

[optional body — explain what and why, not how]
```

**Types:**
| Type | Use for |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code restructure, no behaviour change |
| `chore` | Dependencies, config, tooling |
| `docs` | Documentation only |
| `style` | Formatting, whitespace |
| `perf` | Performance improvement |
| `test` | Adding or fixing tests |
| `revert` | Reverting a previous commit |
| `build` | Build system changes |
| `ci` | CI/CD changes |

**Rules:**
- Subject line ≤ 50 characters, capitalised, no trailing period
- Use imperative mood: "Add tests" not "Added tests"
- Blank line between subject and body
- Body lines wrap at 72 characters — use it to explain *why*, not *what*

**⚠️ NEVER push to remote without explicit user approval.**
Commit freely to the local repo. Before any `git push` (including force pushes and tag pushes), stop and ask the user to review. The user will decide when to squash, reorder, or push. Do not push as part of `make release` or any other automated step without first getting sign-off.

**Example:**
```
feat: Add Gemma local enhancement provider

Integrates Gemma 3 1B QAT via LiteRT-LM as an offline AI enhancement
option. No API key or Ollama required — model runs in-process via Metal.
```

---

## What Does NOT Need to Change

- The prompt system (`CustomPrompt.swift`, `AIPrompts.swift`, `PredefinedPrompts.swift`)
- Context capture (clipboard, screen content, selected text, vocabulary)
- Output filtering (`AIEnhancementOutputFilter.swift` — already strips `<thinking>` blocks)
- Retry and timeout logic (all in `AIEnhancementService`, provider-agnostic)
- The transcription pipeline (`TranscriptionPipeline.swift`)
- Word replacement and trigger word detection
