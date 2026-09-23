import Foundation
import LiteRTLM
import Testing
@testable import Siloquy

@MainActor
struct GemmaInitializationTests {
    private actor Loader {
        var calls: [String] = []
        private var gates: [Int: CheckedContinuation<Void, Never>] = [:]

        func load(_ path: String) async throws -> Engine {
            calls.append(path)
            let call = calls.count
            await withCheckedContinuation { gates[call] = $0 }
            // A lifecycle fixture: no native initialization, model data, or GPU.
            // Intentionally ignore cancellation to model native code finishing late.
            return Engine(engineConfig: try EngineConfig(modelPath: path))
        }

        func waitForCall(_ call: Int) async {
            while gates[call] == nil { await Task.yield() }
        }

        func finish(_ call: Int) { gates.removeValue(forKey: call)?.resume() }
    }

    private final class Fixture {
        let suite = "GemmaInitializationTests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults: UserDefaults
        let loader = Loader()
        let service: GemmaService

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for model in GemmaService.catalog {
                try Data("fixture".utf8).write(to: directory.appendingPathComponent(model.filename))
            }
            service = GemmaService(defaults: defaults, modelDirectory: directory,
                                   automaticallyInitialize: false) { [loader] path in
                try await loader.load(path)
            }
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func cancellingACallerPreservesSharedWarmupAndReadyEngine() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let first = Task { await f.service.initializeEngine() }
        await f.loader.waitForCall(1)
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await f.service.initializeEngine()
        }
        while !secondStarted { await Task.yield() }
        first.cancel()
        await f.loader.finish(1)
        await first.value
        await second.value
        #expect(f.service.engineState == .ready)
        #expect(await f.loader.calls.count == 1)
        await f.service.initializeEngine()
        #expect(await f.loader.calls.count == 1, "The completed engine must stay warm")
    }

    @Test func cancellingAJoiningCallerDoesNotInvalidateReadiness() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let first = Task { await f.service.initializeEngine() }
        await f.loader.waitForCall(1)
        var joined = false
        let second = Task {
            joined = true
            await f.service.initializeEngine()
        }
        while !joined { await Task.yield() }
        second.cancel()
        await f.loader.finish(1)
        await first.value
        await second.value
        #expect(f.service.engineState == .ready)
        #expect(await f.loader.calls.count == 1)
    }

    @Test func modelSwitchRejectsTheOldInitializationResult() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let first = Task { await f.service.initializeEngine() }
        await f.loader.waitForCall(1)
        let nextModel = GemmaService.catalog[1]
        let switched = Task { await f.service.selectModel(nextModel) }
        await f.loader.waitForCall(2)
        await f.loader.finish(2)
        await switched.value
        #expect(f.service.engineState == .ready)
        await f.loader.finish(1)
        await first.value
        #expect(f.service.engineState == .ready)
        #expect(f.service.selectedModelID == nextModel.id)
        await f.service.initializeEngine()
        #expect(await f.loader.calls.count == 2, "A late result must not replace the selected engine")
    }

    @Test func deletingAWarmingModelPreventsLatePublication() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let warmup = Task { await f.service.initializeEngine() }
        await f.loader.waitForCall(1)
        f.service.deleteModel(GemmaService.catalog[0])
        await f.loader.finish(1)
        await warmup.value
        #expect(f.service.engineState == .notReady)
        #expect(!f.service.isModelDownloaded)
        #expect(f.service.downloadStates[GemmaService.catalog[0].id] == .notDownloaded)
    }

    @Test func overlappingEnhancementsAreRejectedDuringWarmup() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let first = Task { try await f.service.enhance("Synthetic text", withSystemPrompt: "Fix grammar") }
        await f.loader.waitForCall(1)
        do {
            _ = try await f.service.enhance("Second text", withSystemPrompt: "Fix grammar")
            Issue.record("Expected a busy error")
        } catch GemmaError.busy {} catch { Issue.record("Unexpected error: \(error)") }
        first.cancel()
        await f.loader.finish(1)
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await f.loader.calls.count == 1)
        #expect(f.service.engineState == .ready)
    }
}
