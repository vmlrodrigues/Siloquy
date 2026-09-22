import Foundation
import Testing
@testable import Siloquy

@MainActor
struct ModelDownloadRecoveryTests {
    private func model(_ name: String) throws -> FluidAudioModel {
        try #require(TranscriptionModelRegistry.models.first { $0.name == name } as? FluidAudioModel)
    }

    @Test func missingVocabularyMustRecoverOnRetry() async throws {
        let suite = "SiloquyRecoveryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let v3 = try model("parakeet-tdt-0.6b-v3")
        // Mirrors the pinned SDK: modelsExist includes vocabulary, whereas the
        // loadModels download gate checks only the CoreML model paths.
        var modelFilesPresent = true
        var vocabularyPresent = false
        var repairs = 0
        let manager = FluidAudioModelManager(defaults: defaults, modelsExist: { _ in
            modelFilesPresent && vocabularyPresent
        }, resetModels: { _ in
            repairs += 1
            modelFilesPresent = false
        }) { _, _ in
            if !modelFilesPresent {
                modelFilesPresent = true
                vocabularyPresent = true
            }
            if !vocabularyPresent { throw CocoaError(.fileNoSuchFile) }
        }
        await manager.downloadFluidAudioModel(v3)
        #expect(manager.downloadError(for: v3) != nil)
        await manager.downloadFluidAudioModel(v3)
        #expect(repairs == 1, "An incomplete cache must also be eligible for repair")
        #expect(manager.isFluidAudioModelDownloaded(v3), "Retry must recover a missing vocabulary file")
    }

    @Test func anotherModelsSuccessDoesNotEraseARetryFailureMarker() async throws {
        let suite = "SiloquyRecoveryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let v3 = try model("parakeet-tdt-0.6b-v3")
        let v2 = try model("parakeet-tdt-0.6b-v2")
        var v2Present = false
        var v3Present = false
        var v3Attempts = 0
        var manager: FluidAudioModelManager!
        manager = FluidAudioModelManager(defaults: defaults, modelsExist: { version in
            version == .v2 ? v2Present : v3Present
        }, resetModels: { version in
            #expect(version == .v3)
            v3Present = false
        }) { version, _ in
            if version == .v2 {
                v2Present = true
                return
            }
            v3Attempts += 1
            v3Present = true
            if v3Attempts == 1 { throw CocoaError(.fileReadCorruptFile) }
            await manager.downloadFluidAudioModel(v2)
            let restarted = FluidAudioModelManager(defaults: defaults, modelsExist: { _ in true }, resetModels: { _ in
                Issue.record("Read-only restored manager must not repair")
            }, downloadModels: { _, _ in
                Issue.record("Read-only restored manager must not download")
            })
            #expect(!restarted.isFluidAudioModelDownloaded(v3))
            #expect(restarted.isFluidAudioModelDownloaded(v2))
        }
        await manager.downloadFluidAudioModel(v3)
        await manager.downloadFluidAudioModel(v3)
        #expect(manager.isFluidAudioModelDownloaded(v3))
        #expect(manager.isFluidAudioModelDownloaded(v2))
        manager = nil
    }
}
