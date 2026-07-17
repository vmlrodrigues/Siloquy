import Foundation
import SwiftUI
import LiteRTLM
import os

// MARK: - Local Model Catalogue

struct LocalModel: Identifiable {
    let id: String
    let displayName: String
    let detail: String          // shown below the name (compact metadata)
    let blurb: String           // one-line "what it's good for", shown in the picker
    let filename: String        // stored filename on disk
    let downloadURL: URL
    let fileSizeBytes: Int64
    /// Appended verbatim to every user message (e.g. " /no_think" for Qwen3).
    let messageSuffix: String?

    init(id: String, displayName: String, detail: String, blurb: String = "", filename: String,
         downloadURL: URL, fileSizeBytes: Int64, messageSuffix: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.blurb = blurb
        self.filename = filename
        self.downloadURL = downloadURL
        self.fileSizeBytes = fileSizeBytes
        self.messageSuffix = messageSuffix
    }

    var formattedSize: String {
        let gb = Double(fileSizeBytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(fileSizeBytes) / 1_048_576)
    }
}

// MARK: - Per-model download state

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(Double)    // 0–1
    case downloaded
    case error(String)

    static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloading(let a), .downloading(let b)): return abs(a - b) < 0.001
        case (.downloaded, .downloaded): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Engine state (applies to the active/selected model)

enum EngineState: Equatable {
    case notReady
    case initializing
    case ready
    case error(String)
}

// MARK: - GemmaService

@MainActor
class GemmaService: ObservableObject {

    // MARK: - Catalogue

    nonisolated static let catalog: [LocalModel] = [
        LocalModel(
            id: "gemma4-e4b",
            displayName: "Gemma 4 E4B",
            detail: "3.4 GB · Google · recommended",
            blurb: "The recommended model — clearly the strongest dictation cleanup in our testing. Needs ~4 GB of free memory; best on Macs with 16 GB or more.",
            filename: "gemma4-e4b-it.litertlm",
            downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm")!,
            fileSizeBytes: 3_659_530_240
        ),
        LocalModel(
            id: "gemma4-e2b",
            displayName: "Gemma 4 E2B",
            detail: "2.4 GB · Google · low-RAM fallback",
            blurb: "Lighter and faster for lower-memory Macs. Less reliable than E4B — give its output a quick glance, and pair it with a simple prompt.",
            filename: "gemma4-e2b-it.litertlm",
            downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")!,
            fileSizeBytes: 2_588_147_712
        ),
        LocalModel(
            id: "qwen3-0.6b-int4",
            displayName: "Qwen3 0.6B",
            detail: "497 MB · not recommended",
            blurb: "Smallest and fastest, but unreliable in our testing — it can drop, garble, or invent text. Only for severely memory-constrained Macs; check every output.",
            filename: "qwen3_0_6b_mixed_int4.litertlm",
            downloadURL: URL(string: "https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm")!,
            fileSizeBytes: 497_664_000,
            messageSuffix: " /no_think"   // disable Qwen3's chain-of-thought mode
        ),
    ]

    /// Selected local model id, readable from any isolation context —
    /// UserDefaults-backed so nonisolated callers (history recording #19,
    /// prompt resolution #22) see the engine's real selection.
    nonisolated static var currentSelectedModelID: String {
        UserDefaults.standard.string(forKey: "localModelSelectedID") ?? catalog.first!.id
    }

    // MARK: - Published state

    /// Download state for each model, keyed by LocalModel.id
    @Published var downloadStates: [String: DownloadState] = [:]

    /// Which model is selected (will be used for enhancement)
    @Published var selectedModelID: String

    /// Engine state for the currently selected model
    @Published var engineState: EngineState = .notReady

    // MARK: - Private

    private var engine: Engine?
    private var engineModelID: String?          // model the current engine was built from
    private var downloadTasks: [String: Task<Void, Error>] = [:]
    private var isGenerating = false            // single-flight: the engine runs one generation at a time
    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "GemmaService")

    // MARK: - Computed helpers (called from non-actor contexts too)

    nonisolated var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Siloquy/Models", isDirectory: true)
    }

    nonisolated func modelPath(for model: LocalModel) -> URL {
        modelDirectory.appendingPathComponent(model.filename)
    }

    nonisolated func isDownloaded(_ model: LocalModel) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    var selectedModel: LocalModel? {
        Self.catalog.first { $0.id == selectedModelID }
    }

    /// True when the selected model's file is present on disk.
    nonisolated var isModelDownloaded: Bool {
        guard let id = UserDefaults.standard.string(forKey: "localModelSelectedID"),
              let model = GemmaService.catalog.first(where: { $0.id == id })
        else {
            // Fall back to first model
            return GemmaService.catalog.first.map {
                FileManager.default.fileExists(atPath:
                    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Siloquy/Models/\($0.filename)").path)
            } ?? false
        }
        return FileManager.default.fileExists(atPath:
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Siloquy/Models/\(model.filename)").path)
    }

    // MARK: - Init

    nonisolated init() {
        let savedID = UserDefaults.standard.string(forKey: "localModelSelectedID")
                      ?? Self.catalog.first?.id
                      ?? "gemma4-e2b"
        _selectedModelID = Published(initialValue: savedID)

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Seed download states from disk
            for model in Self.catalog {
                self.downloadStates[model.id] = self.isDownloaded(model) ? .downloaded : .notDownloaded
            }
            // Auto-init engine if the selected model is already downloaded
            if let selected = self.selectedModel, self.isDownloaded(selected) {
                await self.initializeEngine()
            }
        }
    }

    // MARK: - Selection

    func selectModel(_ model: LocalModel) async {
        guard model.id != selectedModelID else { return }
        selectedModelID = model.id
        UserDefaults.standard.set(model.id, forKey: "localModelSelectedID")

        // Tear down engine if it was built for a different model
        if engineModelID != model.id {
            engine = nil
            engineModelID = nil
            engineState = .notReady
        }

        if isDownloaded(model) {
            await initializeEngine()
        }
    }

    // MARK: - Download

    func startDownload(for model: LocalModel) {
        guard downloadStates[model.id] != .downloaded else { return }
        downloadTasks[model.id]?.cancel()

        downloadTasks[model.id] = Task {
            do {
                try await performDownload(for: model)
            } catch is CancellationError {
                self.downloadStates[model.id] = .notDownloaded
            } catch {
                self.downloadStates[model.id] = .error(error.localizedDescription)
            }
        }
    }

    func cancelDownload(for model: LocalModel) {
        downloadTasks[model.id]?.cancel()
        downloadTasks[model.id] = nil
        downloadStates[model.id] = .notDownloaded
    }

    private func performDownload(for model: LocalModel) async throws {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        downloadStates[model.id] = .downloading(0)

        let downloadedURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let delegate = ModelDownloadDelegate(
                continuation: continuation,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadStates[model.id] = .downloading(progress)
                    }
                }
            )
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 3600
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.downloadTask(with: model.downloadURL).resume()
        }

        try Task.checkCancellation()

        let dest = modelPath(for: model)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: dest)
        downloadStates[model.id] = .downloaded

        // Auto-init engine if this became the selected model
        if model.id == selectedModelID {
            await initializeEngine()
        }
    }

    // MARK: - Import

    func importModel(from sourceURL: URL, as model: LocalModel) {
        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            let dest = modelPath(for: model)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            downloadStates[model.id] = .downloaded
            if model.id == selectedModelID {
                Task { await self.initializeEngine() }
            }
        } catch {
            downloadStates[model.id] = .error("Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    func deleteModel(_ model: LocalModel) {
        if engineModelID == model.id {
            engine = nil
            engineModelID = nil
            engineState = .notReady
        }
        try? FileManager.default.removeItem(at: modelPath(for: model))
        downloadStates[model.id] = .notDownloaded
    }

    // MARK: - Engine Initialization

    func initializeEngine() async {
        guard let model = selectedModel, isDownloaded(model) else { return }

        // Already warm for this model
        if engineModelID == model.id, engineState == .ready { return }

        // Different model — tear down first
        if engineModelID != model.id {
            engine = nil
            engineModelID = nil
        }

        engineState = .initializing
        let path = modelPath(for: model).path
        let modelID = model.id

        do {
            let engineTask: Task<Engine, Error> = Task.detached(priority: .userInitiated) {
                // Try GPU (Metal) first; fall back to CPU if Metal compilation fails.
                do {
                    let config = try EngineConfig(modelPath: path, backend: .gpu)
                    let e = Engine(engineConfig: config)
                    try await e.initialize()
                    return e
                } catch {
                    // GPU failed — retry on CPU (avoids Metal shader compilation issues)
                    let config = try EngineConfig(modelPath: path, backend: .cpu())
                    let e = Engine(engineConfig: config)
                    try await e.initialize()
                    return e
                }
            }
            let newEngine = try await engineTask.value
            engine = newEngine
            engineModelID = modelID
            engineState = .ready
        } catch {
            engineState = .error("Engine init failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine recovery

    /// Tear the engine down so the next enhancement rebuilds a clean one.
    ///
    /// A local generation cancelled mid-decode (e.g. by a timeout) can leave the in-process
    /// LiteRT-LM engine wedged — every later request then hangs until the app is restarted.
    /// There's no reliable way to "unstick" it in place, so we drop the engine and let the
    /// next call reinitialise a fresh one.
    private func resetEngine() {
        logger.notice("Resetting Gemma engine after a failed/timed-out generation; it will rebuild on the next request.")
        engine = nil
        engineModelID = nil
        engineState = .notReady
    }

    // MARK: - Enhancement

    func enhance(_ text: String, withSystemPrompt systemPrompt: String, timeout: TimeInterval = 30) async throws -> String {
        guard let model = selectedModel, isDownloaded(model) else {
            throw GemmaError.modelNotDownloaded
        }

        // Single-flight: the in-process engine runs one generation at a time. A second
        // concurrent request (e.g. a new recording started mid-enhancement) would contend for
        // the same engine and corrupt both, so reject rather than overlap.
        guard !isGenerating else {
            throw GemmaError.busy
        }

        if engine == nil || engineState != .ready {
            await initializeEngine()
        }

        guard let engine, engineState == .ready else {
            throw GemmaError.initializationFailed("Engine is not available")
        }

        // Apply any model-specific message transformation (e.g. /no_think for Qwen3)
        let userText: String
        if let suffix = selectedModel?.messageSuffix {
            userText = text + suffix
        } else {
            userText = text
        }

        // Local inference is compute-bound with no network latency, so the caller's
        // network-oriented timeout (7s by default) is far too short and kills healthy long
        // dictations mid-decode — which is what wedges the engine. Give generation a generous,
        // length-aware budget instead; resetEngine() below is the safety net for a genuinely
        // hung engine.
        let localBudget = min(300, max(60, Double(userText.count) / 12))
        let effectiveTimeout = max(timeout, localBudget)

        isGenerating = true
        defer { isGenerating = false }

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let convConfig = ConversationConfig(
                        systemMessage: Message(systemPrompt, role: .system)
                    )
                    let conversation = try await engine.createConversation(with: convConfig)
                    var result = ""
                    for try await chunk in conversation.sendMessageStream(Message(userText)) {
                        result += chunk.toString
                    }
                    return result
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    throw GemmaError.timeout
                }
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw GemmaError.initializationFailed("No result returned from engine")
                }
                group.cancelAll()
                return result
            }
        } catch {
            // Timed out or errored mid-generation. A cancelled native generation can leave the
            // engine wedged, so tear it down — the next call rebuilds a clean engine and recovers
            // automatically (this previously required an app restart).
            resetEngine()
            throw error
        }
    }
}

// MARK: - URLSession Download Delegate

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let continuation: CheckedContinuation<URL, Error>
    private let onProgress: (Double) -> Void
    var session: URLSession?

    init(continuation: CheckedContinuation<URL, Error>, onProgress: @escaping (Double) -> Void) {
        self.continuation = continuation
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let code = httpResponse.statusCode
            let msg: String
            switch code {
            case 401: msg = "HTTP 401: Authentication required. The model may be gated."
            case 403: msg = "HTTP 403: Access denied. Accept the model licence on Hugging Face."
            default:  msg = "HTTP \(code): \(HTTPURLResponse.localizedString(forStatusCode: code))"
            }
            continuation.resume(throwing: GemmaError.downloadFailed(msg))
            self.session = nil
            return
        }
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".litertlm")
        do {
            try FileManager.default.moveItem(at: location, to: stableURL)
            continuation.resume(returning: stableURL)
        } catch {
            continuation.resume(throwing: error)
        }
        self.session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.resume(throwing: error)
            self.session = nil
        }
    }
}

// MARK: - Error Types

enum GemmaError: Error, LocalizedError {
    case modelNotDownloaded
    case downloadFailed(String)
    case initializationFailed(String)
    case timeout
    case busy

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "No local model downloaded. Please download one in Settings → AI Provider."
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .initializationFailed(let msg):
            return "Engine initialisation failed: \(msg)"
        case .timeout:
            return "Local model enhancement timed out"
        case .busy:
            return "The local model is already processing another request."
        }
    }
}
