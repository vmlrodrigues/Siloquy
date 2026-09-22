import Foundation
import Testing
@testable import Siloquy

@MainActor
struct LanguageModelDownloadTests {
    private func parakeetV3() throws -> FluidAudioModel {
        try #require(TranscriptionModelRegistry.models.first {
            $0.name == "parakeet-tdt-0.6b-v3"
        } as? FluidAudioModel)
    }

    @Test func failureCanBeRetriedAndReadinessIsRefreshed() async throws {
        let suite = "SiloquyDownloadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try parakeetV3()
        var installed = false
        var attempts = 0
        var refreshes = 0
        var manager: FluidAudioModelManager!
        manager = FluidAudioModelManager(defaults: defaults, modelsExist: { _ in installed }, resetModels: { _ in Issue.record("No complete cache to repair") }) { version, _ in
            #expect(version == .v3)
            #expect(manager.isFluidAudioModelDownloading(model))
            #expect(manager.downloadError(for: model) == nil)
            attempts += 1
            // A second request, including one from the catalogue, shares this download.
            await manager.downloadFluidAudioModel(model)
            if attempts == 1 {
                throw URLError(.notConnectedToInternet)
            }
            installed = true
        }
        manager.onModelsChanged = { refreshes += 1 }

        await manager.downloadFluidAudioModel(model)
        #expect(attempts == 1)
        #expect(!manager.isFluidAudioModelDownloaded(model))
        #expect(!manager.isFluidAudioModelDownloading(model))
        #expect(manager.downloadError(for: model) != nil)
        #expect(refreshes == 1)

        await manager.downloadFluidAudioModel(model)
        #expect(attempts == 2)
        #expect(manager.isFluidAudioModelDownloaded(model))
        #expect(manager.downloadStatus(for: model) == nil)
        #expect(manager.downloadError(for: model) == nil)
        #expect(refreshes == 2)
        manager = nil
    }

    @Test func anExistingDownloadRefreshesReadinessWithoutFetchingAgain() async throws {
        let suite = "SiloquyDownloadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try parakeetV3()
        var refreshes = 0
        let manager = FluidAudioModelManager(defaults: defaults, modelsExist: { _ in true }, resetModels: { _ in Issue.record("A healthy cache must not be reset") }) { _, _ in
            Issue.record("An installed model must not be downloaded again")
        }
        manager.onModelsChanged = { refreshes += 1 }
        await manager.downloadFluidAudioModel(model)
        #expect(refreshes == 1)
        #expect(manager.downloadStatus(for: model) == nil)
    }
    @Test func lateFailureSurvivesRestartAndRetryRepairsOnlyTheFailedVersion() async throws {
        let suite = "SiloquyDownloadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try parakeetV3()
        var filesPresent = false
        var attempts = 0
        var repairs = 0
        var manager: FluidAudioModelManager!
        func makeManager() -> FluidAudioModelManager {
            FluidAudioModelManager(defaults: defaults, modelsExist: { _ in filesPresent }, resetModels: { version in
                #expect(version == .v3)
                repairs += 1
                filesPresent = false
            }) { _, _ in
                attempts += 1
                filesPresent = true
                #expect(!manager.isFluidAudioModelDownloaded(model), "Finalization is still in progress")
                if attempts == 1 { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        manager = makeManager()
        await manager.downloadFluidAudioModel(model)
        #expect(manager.downloadError(for: model) != nil)
        #expect(!manager.isFluidAudioModelDownloaded(model))

        manager = makeManager()
        #expect(manager.downloadError(for: model) != nil)
        #expect(!manager.isFluidAudioModelDownloaded(model))
        var readyAfterRefresh = false
        manager.onModelsChanged = { readyAfterRefresh = manager.isFluidAudioModelDownloaded(model) }
        await manager.downloadFluidAudioModel(model)
        #expect(attempts == 2)
        #expect(repairs == 1)
        #expect(readyAfterRefresh)
        #expect(manager.downloadError(for: model) == nil)
        manager = makeManager()
        #expect(manager.isFluidAudioModelDownloaded(model))
        #expect(manager.downloadError(for: model) == nil)
        manager = nil
    }

    @Test func failedCacheRepairRemainsRetryable() async throws {
        let suite = "SiloquyDownloadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try parakeetV3()
        var filesPresent = false
        var attempts = 0
        let manager = FluidAudioModelManager(defaults: defaults, modelsExist: { _ in filesPresent }, resetModels: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }) { _, _ in
            attempts += 1
            filesPresent = true
            throw CocoaError(.fileReadCorruptFile)
        }
        await manager.downloadFluidAudioModel(model)
        await manager.downloadFluidAudioModel(model)
        #expect(attempts == 1, "Do not reload the same corrupt cache if repair fails")
        #expect(!manager.isFluidAudioModelDownloaded(model))
        #expect(!manager.isFluidAudioModelDownloading(model))
        #expect(manager.downloadError(for: model) == CocoaError(.fileWriteNoPermission).localizedDescription)
    }

}
