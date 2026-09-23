import Foundation
import CryptoKit
import LiteRTLM
import os

/// LiteRT reads process-wide experimental flags during initialize(), not in the
/// Swift Engine initializer. Hold exclusive access across that actor hop (#70).
actor LocalEngineLoader {
    static let shared = LocalEngineLoader()
    // Bump alongside the pinned package: do not assume native caches remain
    // compatible across releases just because LiteRT's filenames stay the same.
    static let runtimeVersion = "0.17.1"

    enum Attempt: String, Sendable {
        case metalMTP, metal, cpu
    }

    private var loading = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "LocalEngineLoader")

    nonisolated static func cacheDirectory(root: URL, modelPath: String, attempt: Attempt) -> URL {
        let path = URL(fileURLWithPath: modelPath).standardizedFileURL.path
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(runtimeVersion, isDirectory: true)
            .appendingPathComponent(attempt.rawValue, isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    func load(modelPath: String, cacheDirectory: String? = nil) async throws -> Engine {
        let supportsMTP = Capabilities(modelPath: modelPath)?.hasSpeculativeDecodingSupport() ?? false
        let cacheRoot = cacheDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Siloquy/LiteRT-LM", isDirectory: true)
        return try await load(supportsMTP: supportsMTP) { [logger] attempt in
            // A failed MTP initialization can leave incomplete cache files.
            // Normal Metal and CPU must not reuse that attempt's cache.
            let cache = Self.cacheDirectory(root: cacheRoot, modelPath: modelPath, attempt: attempt)
            ExperimentalFlags.optIntoExperimentalAPIs()
            ExperimentalFlags.enableSpeculativeDecoding = attempt == .metalMTP
            // Leave a conservative default for any later initialization.
            defer { ExperimentalFlags.enableSpeculativeDecoding = false }

            let engine = try await Self.withCacheRepair(at: cache) { directory in
                let config = try EngineConfig(
                    modelPath: modelPath,
                    backend: attempt == .cpu ? .cpu() : .gpu,
                    cacheDir: directory.path
                )
                let engine = Engine(engineConfig: config)
                try await engine.initialize()
                return engine
            }
            logger.info("Local enhancement engine ready: \(attempt.rawValue, privacy: .public)")
            return engine
        }
    }

    /// Retry once after discarding only this model/backend's generated cache.
    /// An empty cache cannot explain the failure; cancellation must not delete
    /// a cache that may have been built successfully while native code finished.
    nonisolated static func withCacheRepair<T: Sendable>(
        at cache: URL,
        removeCache: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        initialize: @Sendable (URL) async throws -> T
    ) async throws -> T {
        for pass in 0...1 {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            do {
                let result = try await initialize(cache)
                try Task.checkCancellation()
                return result
            } catch {
                if error is CancellationError { throw error }
                try Task.checkCancellation()
                guard pass == 0,
                      !(try FileManager.default.contentsOfDirectory(atPath: cache.path)).isEmpty
                else { throw error }
                try removeCache(cache)
                Logger(subsystem: "com.victorrodrigues.siloquy", category: "LocalEngineLoader")
                    .notice("Retrying local engine initialization with a clean model cache")
            }
        }
        preconditionFailure("The final cache attempt must return or throw")
    }

    /// The injected initializer keeps failure and concurrency tests independent
    /// of model downloads and GPU availability.
    func load<T: Sendable>(
        supportsMTP: Bool,
        initialize: @Sendable (Attempt) async throws -> T
    ) async throws -> T {
        if loading {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            loading = true
        }
        defer {
            if waiters.isEmpty {
                loading = false
            } else {
                waiters.removeFirst().resume()
            }
        }

        let attempts: [Attempt] = supportsMTP ? [.metalMTP, .metal, .cpu] : [.metal, .cpu]
        for attempt in attempts {
            try Task.checkCancellation()
            do {
                let result = try await initialize(attempt)
                try Task.checkCancellation()
                return result
            } catch {
                if error is CancellationError { throw error }
                try Task.checkCancellation()
                logger.warning("Local engine initialization failed (\(attempt.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                if attempt == .cpu { throw error }
            }
        }
        preconditionFailure("The CPU attempt must return or throw")
    }
}
