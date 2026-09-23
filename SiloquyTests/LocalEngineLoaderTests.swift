import Foundation
import Testing
@testable import Siloquy

struct LocalEngineLoaderTests {
    private enum Failure: Error { case unavailable }

    @Test func cachesAreIsolatedFromLegacyAndFallbackBackends() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyCache = root.appendingPathComponent("model_weight_cache.bin")
        let oldContents = Data("incompatible legacy cache".utf8)
        try oldContents.write(to: legacyCache)
        let accelerated = LocalEngineLoader.cacheDirectory(root: root, attempt: .metalMTP)
        let metal = LocalEngineLoader.cacheDirectory(root: root, attempt: .metal)
        let cpu = LocalEngineLoader.cacheDirectory(root: root, attempt: .cpu)
        #expect(Set([accelerated, metal, cpu]).count == 3)
        #expect(accelerated.deletingLastPathComponent().lastPathComponent == LocalEngineLoader.runtimeVersion)
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
