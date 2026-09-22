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
        let model = try parakeetV3()
        var installed = false
        var attempts = 0
        var refreshes = 0
        var manager: FluidAudioModelManager!
        manager = FluidAudioModelManager(modelsExist: { _ in installed }) { version, _ in
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
        let model = try parakeetV3()
        var refreshes = 0
        let manager = FluidAudioModelManager(modelsExist: { _ in true }) { _, _ in
            Issue.record("An installed model must not be downloaded again")
        }
        manager.onModelsChanged = { refreshes += 1 }
        await manager.downloadFluidAudioModel(model)
        #expect(refreshes == 1)
        #expect(manager.downloadStatus(for: model) == nil)
    }
}
