import Foundation
import Testing
@testable import Siloquy

struct LocalEngineLoaderTests {
    private enum Failure: Error { case unavailable }

    private actor CacheProbe {
        var calls = 0

        func initialize(at cache: URL, alwaysFail: Bool = false) throws -> String {
            calls += 1
            let file = cache.appendingPathComponent("weights.bin")
            if FileManager.default.fileExists(atPath: file.path) || alwaysFail {
                try Data("incomplete".utf8).write(to: file)
                throw Failure.unavailable
            }
            try Data("healthy".utf8).write(to: file)
            return "ready"
        }
    }

    @Test func damagedCacheIsRebuiltWithoutTouchingOtherModelsOrBackends() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let damaged = LocalEngineLoader.cacheDirectory(root: root, modelPath: "/models/e4b", attempt: .metalMTP)
        let otherModel = LocalEngineLoader.cacheDirectory(root: root, modelPath: "/models/e2b", attempt: .metalMTP)
        let otherBackend = LocalEngineLoader.cacheDirectory(root: root, modelPath: "/models/e4b", attempt: .metal)
        for cache in [damaged, otherModel, otherBackend] {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("incomplete".utf8).write(to: cache.appendingPathComponent("weights.bin"))
        }
        let probe = CacheProbe()
        let result = try await LocalEngineLoader.withCacheRepair(at: damaged) {
            try await probe.initialize(at: $0)
        }
        #expect(result == "ready")
        #expect(await probe.calls == 2)
        #expect(try Data(contentsOf: damaged.appendingPathComponent("weights.bin")) == Data("healthy".utf8))
        for cache in [otherModel, otherBackend] {
            #expect(try Data(contentsOf: cache.appendingPathComponent("weights.bin")) == Data("incomplete".utf8))
        }
    }

    @Test func persistentCacheFailureRetriesOnlyOnceThenFallsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = CacheProbe()
        let result = try await LocalEngineLoader().load(supportsMTP: true) { attempt in
            if attempt == .metalMTP {
                return try await LocalEngineLoader.withCacheRepair(at: root) {
                    try await probe.initialize(at: $0, alwaysFail: true)
                }
            }
            return attempt.rawValue
        }
        #expect(result == "metal")
        #expect(await probe.calls == 2)
    }

    @Test func healthyCacheNeedsNoRepair() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = CacheProbe()
        _ = try await LocalEngineLoader.withCacheRepair(at: root, removeCache: { _ in
            Issue.record("A successful initialization must not remove its cache")
        }) { try await probe.initialize(at: $0) }
        #expect(await probe.calls == 1)
    }

    @Test func emptyCacheFailureDoesNotRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: Failure.self) {
            try await LocalEngineLoader.withCacheRepair(at: root, removeCache: { _ in
                Issue.record("An empty cache must not be repaired")
            }) { _ -> String in throw Failure.unavailable }
        }
    }

    @Test func cancelledInitializationPreservesCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("weights.bin")
        try Data("healthy".utf8).write(to: file)
        await #expect(throws: CancellationError.self) {
            try await LocalEngineLoader.withCacheRepair(at: root) { _ -> String in
                throw CancellationError()
            }
        }
        #expect(try Data(contentsOf: file) == Data("healthy".utf8))
    }

    @Test func failedRepairFallsBackWithoutRetryingTheSameCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = CacheProbe()
        let result = try await LocalEngineLoader().load(supportsMTP: true) { attempt in
            if attempt == .metalMTP {
                return try await LocalEngineLoader.withCacheRepair(at: root,
                    removeCache: { _ in throw Failure.unavailable }) {
                    try await probe.initialize(at: $0, alwaysFail: true)
                }
            }
            return attempt.rawValue
        }
        #expect(result == "metal")
        #expect(await probe.calls == 1)
    }

    @Test func cachesAreIsolatedFromLegacyAndFallbackBackends() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyCache = root.appendingPathComponent("model_weight_cache.bin")
        let oldContents = Data("incompatible legacy cache".utf8)
        try oldContents.write(to: legacyCache)
        let accelerated = LocalEngineLoader.cacheDirectory(root: root, modelPath: "/models/e4b.litertlm", attempt: .metalMTP)
        let metal = LocalEngineLoader.cacheDirectory(root: root, modelPath: "/models/e4b.litertlm", attempt: .metal)
        let cpu = LocalEngineLoader.cacheDirectory(root: root, modelPath: "/models/e4b.litertlm", attempt: .cpu)
        #expect(Set([accelerated, metal, cpu]).count == 3)
        #expect(accelerated.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == LocalEngineLoader.runtimeVersion)
        for cache in [accelerated, metal, cpu] {
            #expect(cache != root)
            #expect(!FileManager.default.fileExists(atPath: cache.appendingPathComponent(legacyCache.lastPathComponent).path))
        }
        #expect(try Data(contentsOf: legacyCache) == oldContents)
    }

    private actor Probe {
        var attempts: [LocalEngineLoader.Attempt] = []
        var active = 0
        var peak = 0

        func initialize(_ attempt: LocalEngineLoader.Attempt,
                        failing: Set<LocalEngineLoader.Attempt> = [],
                        cancel: Bool = false) async throws -> String {
            attempts.append(attempt)
            active += 1
            peak = max(peak, active)
            defer { active -= 1 }
            // Suspend while flags would be in use by the native initializer.
            try await Task.sleep(for: .milliseconds(1))
            if cancel { throw CancellationError() }
            if failing.contains(attempt) { throw Failure.unavailable }
            return attempt.rawValue
        }
    }

    @Test func supportedModelUsesMTP() async throws {
        let probe = Probe()
        let result = try await LocalEngineLoader().load(supportsMTP: true) {
            try await probe.initialize($0)
        }
        #expect(result == "metalMTP")
        #expect(await probe.attempts == [.metalMTP])
    }

    @Test func olderModelSkipsMTP() async throws {
        let probe = Probe()
        let result = try await LocalEngineLoader().load(supportsMTP: false) {
            try await probe.initialize($0)
        }
        #expect(result == "metal")
        #expect(await probe.attempts == [.metal])
    }

    @Test func acceleratedFailureRetriesNormalMetal() async throws {
        let probe = Probe()
        let result = try await LocalEngineLoader().load(supportsMTP: true) {
            try await probe.initialize($0, failing: [.metalMTP])
        }
        #expect(result == "metal")
        #expect(await probe.attempts == [.metalMTP, .metal])
    }

    @Test(arguments: [true, false]) func metalFailureFallsBackToCPU(supportsMTP: Bool) async throws {
        let probe = Probe()
        let result = try await LocalEngineLoader().load(supportsMTP: supportsMTP) {
            try await probe.initialize($0, failing: [.metalMTP, .metal])
        }
        #expect(result == "cpu")
        #expect(await probe.attempts == (supportsMTP ? [.metalMTP, .metal, .cpu] : [.metal, .cpu]))
    }

    @Test func terminalFailureReleasesInitializationSlot() async throws {
        let loader = LocalEngineLoader()
        let probe = Probe()
        await #expect(throws: Failure.self) {
            try await loader.load(supportsMTP: true) {
                try await probe.initialize($0, failing: [.metalMTP, .metal, .cpu])
            }
        }
        let recovered = try await loader.load(supportsMTP: true) {
            try await probe.initialize($0)
        }
        #expect(recovered == "metalMTP")
        #expect(await probe.attempts == [.metalMTP, .metal, .cpu, .metalMTP])
    }

    @Test func cancellationDoesNotTryOtherBackendsAndReleasesSlot() async throws {
        let loader = LocalEngineLoader()
        let probe = Probe()
        await #expect(throws: CancellationError.self) {
            try await loader.load(supportsMTP: true) {
                try await probe.initialize($0, cancel: true)
            }
        }
        #expect(await probe.attempts == [.metalMTP])
        _ = try await loader.load(supportsMTP: false) {
            try await probe.initialize($0)
        }
        #expect(await probe.attempts == [.metalMTP, .metal])
    }

    @Test func concurrentInitializationsNeverOverlap() async throws {
        let loader = LocalEngineLoader()
        let probe = Probe()
        try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try await loader.load(supportsMTP: index.isMultiple(of: 2)) {
                        try await probe.initialize($0)
                    }
                }
            }
            for try await _ in group {}
        }
        #expect(await probe.peak == 1)
        #expect(await probe.attempts.count == 20)
    }
}
