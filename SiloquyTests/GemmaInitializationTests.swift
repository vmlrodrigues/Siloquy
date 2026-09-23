import Foundation
import LiteRTLM
import Testing
@testable import Siloquy

@MainActor
struct GemmaInitializationTests {
    private actor Loader {
        var calls: [String] = []
        var cancelledCalls: [Int] = []
        private var gates: [Int: CheckedContinuation<Void, Never>] = [:]

        func load(_ path: String) async throws -> Engine {
            calls.append(path)
            let call = calls.count
            await withCheckedContinuation { gates[call] = $0 }
            if Task.isCancelled { cancelledCalls.append(call) }
            // A lifecycle fixture: no native initialization, model data, or GPU.
            // Intentionally ignore cancellation to model native code finishing late.
            return Engine(engineConfig: try EngineConfig(modelPath: path))
        }

        func waitForCall(_ call: Int) async {
            while gates[call] == nil { await Task.yield() }
        }

        func finish(_ call: Int) { gates.removeValue(forKey: call)?.resume() }
    }

    private enum Failure: Error { case generation }

    private actor Generator {
        var engines: [Engine] = []
        private var gates: [Int: CheckedContinuation<String, Error>] = [:]

        func generate(_ engine: Engine) async throws -> String {
            engines.append(engine)
            let call = engines.count
            return try await withCheckedThrowingContinuation { gates[call] = $0 }
        }

        func waitForCall(_ call: Int) async {
            while gates[call] == nil { await Task.yield() }
        }

        func finish(_ call: Int, result: Result<String, Error>) {
            gates.removeValue(forKey: call)?.resume(with: result)
        }
    }

    private final class Fixture {
        let suite = "GemmaInitializationTests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults: UserDefaults
        let loader = Loader()
        let generator = Generator()
        let service: GemmaService

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for model in GemmaService.catalog {
                try Data("fixture".utf8).write(to: directory.appendingPathComponent(model.filename))
            }
            service = GemmaService(defaults: defaults, modelDirectory: directory,
                                   automaticallyInitialize: false,
                                   loadEngine: { [loader] path in try await loader.load(path) },
                                   generate: { [generator] engine, _, _ in try await generator.generate(engine) })
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
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
        var secondFinished = false
        let second = Task {
            joined = true
            await f.service.initializeEngine()
            secondFinished = true
        }
        while !joined { await Task.yield() }
        second.cancel()
        let finishedBeforeWarmup = await waitUntil { secondFinished }
        await f.loader.finish(1)
        await first.value
        await second.value
        #expect(f.service.engineState == .ready)
        #expect(await f.loader.calls.count == 1)
        #expect(finishedBeforeWarmup, "A cancelled joining caller must not wait for native warm-up")
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
        // Cancellation now returns independently of warm-up completion.
        await f.service.initializeEngine()
        #expect(await f.loader.calls.count == 1)
        #expect(f.service.engineState == .ready)
    }

    @Test func cancelledWarmupReleasesBusySlotForTheNextRequest() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        var firstFinished = false
        let first = Task {
            defer { firstFinished = true }
            await #expect(throws: CancellationError.self) {
                try await f.service.enhance("First text", withSystemPrompt: "Fix grammar")
            }
        }
        await f.loader.waitForCall(1)
        first.cancel()
        let finishedBeforeWarmup = await waitUntil { firstFinished }
        if !finishedBeforeWarmup {
            // Unblock the fixture even if this regression returns, rather than
            // leaving a suspended task behind after the assertion fails.
            await f.loader.finish(1)
        }
        await first.value
        try #require(finishedBeforeWarmup)
        #expect(f.service.engineState == .initializing)

        var secondStarted = false
        var secondFinished = false
        let second = Task {
            secondStarted = true
            defer { secondFinished = true }
            return try await f.service.enhance("Second text", withSystemPrompt: "Fix grammar")
        }
        while !secondStarted { await Task.yield() }
        #expect(!secondFinished, "The next caller must join warm-up instead of getting busy")
        await f.loader.finish(1)
        await f.generator.waitForCall(1)
        await f.generator.finish(1, result: .success("Second text."))
        #expect(try await second.value == "Second text.")
        #expect(await f.loader.calls.count == 1)
        #expect(await f.loader.cancelledCalls.isEmpty)
        #expect(f.service.engineState == .ready)
    }

    @Test(arguments: [false, true], [false, true])
    func oldGenerationCannotDiscardReplacement(replacementReady: Bool, cancelled: Bool) async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let warmup = Task { await f.service.initializeEngine() }
        await f.loader.waitForCall(1)
        await f.loader.finish(1)
        await warmup.value

        let old = Task {
            try await f.service.enhance("Old request", withSystemPrompt: "Fix grammar")
        }
        await f.generator.waitForCall(1)
        let switched = Task { await f.service.selectModel(GemmaService.catalog[1]) }
        await f.loader.waitForCall(2)
        if replacementReady {
            await f.loader.finish(2)
            await switched.value
        }
        if cancelled { old.cancel() }
        await f.generator.finish(1, result: .failure(cancelled ? CancellationError() : Failure.generation))
        do {
            _ = try await old.value
            Issue.record("The old generation must fail")
        } catch {
            #expect(cancelled ? error is CancellationError : error is Failure)
        }
        #expect(f.service.engineState == (replacementReady ? .ready : .initializing))
        if !replacementReady {
            await f.loader.finish(2)
            await switched.value
        }
        #expect(await f.loader.cancelledCalls.isEmpty)
        #expect(f.service.engineState == .ready)
        let next = Task { try await f.service.enhance("New model", withSystemPrompt: "Fix grammar") }
        await f.generator.waitForCall(2)
        await f.generator.finish(2, result: .success("New model."))
        #expect(try await next.value == "New model.")
        let engines = await f.generator.engines
        #expect(engines[0] !== engines[1])
        #expect(await f.loader.calls.count == 2)
    }

    @Test func failureOfTheCurrentEngineStillTriggersRecovery() async throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let first = Task { try await f.service.enhance("First", withSystemPrompt: "Fix grammar") }
        await f.loader.waitForCall(1)
        await f.loader.finish(1)
        await f.generator.waitForCall(1)
        await f.generator.finish(1, result: .failure(Failure.generation))
        await #expect(throws: Failure.self) { try await first.value }
        #expect(f.service.engineState == .notReady)

        let next = Task { try await f.service.enhance("Next", withSystemPrompt: "Fix grammar") }
        await f.loader.waitForCall(2)
        await f.loader.finish(2)
        await f.generator.waitForCall(2)
        await f.generator.finish(2, result: .success("Next."))
        #expect(try await next.value == "Next.")
        #expect(f.service.engineState == .ready)
    }
}
