import Foundation
import FluidAudio
import AppKit
import os

struct FluidAudioDownloadStatus {
    let fractionCompleted: Double
    let message: String
}

@MainActor
class FluidAudioModelManager: ObservableObject {
    @Published private var downloadStatuses: [String: FluidAudioDownloadStatus] = [:]
    @Published private var downloadErrors: [String: String] = [:]
    private var activeDownloadIDs: [String: UUID] = [:]
    private static let errorsKey = "FluidAudioModelDownloadErrors"
    private let defaults: UserDefaults
    private let modelsExist: (AsrModelVersion) -> Bool
    private let resetModels: (AsrModelVersion) throws -> Void
    private let downloadModels: (AsrModelVersion, DownloadUtils.ProgressHandler?) async throws -> Void

    var onModelDeleted: ((String) -> Void)?
    var onModelsChanged: (() -> Void)?

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "FluidAudioModelManager")

    // Add new Fluid Audio models here when support is added.
    private static let modelVersionMap: [String: AsrModelVersion] = [
        "parakeet-tdt-0.6b-v2": .v2,
        "parakeet-tdt-0.6b-v3": .v3,
    ]

    nonisolated static func asrVersion(for modelName: String) -> AsrModelVersion {
        modelVersionMap[modelName] ?? .v3
    }

    nonisolated static func languageHint(from languageCode: String?, for modelName: String) -> Language? {
        // This SDK enum controls script filtering, not model language coverage. V3
        // also supports languages such as Swedish without a hint (automatic detection).
        guard asrVersion(for: modelName) == .v3,
              let languageCode,
              languageCode != "auto"
        else { return nil }

        return Language(rawValue: languageCode)
    }

    init(
        defaults: UserDefaults = .standard,
        modelsExist: @escaping (AsrModelVersion) -> Bool = { version in
            AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
        },
        resetModels: @escaping (AsrModelVersion) throws -> Void = { version in
            let directory = AsrModels.defaultCacheDirectory(for: version)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        },
        downloadModels: @escaping (AsrModelVersion, DownloadUtils.ProgressHandler?) async throws -> Void = { version, progress in
            _ = try await AsrModels.downloadAndLoad(version: version, progressHandler: progress)
        }
    ) {
        self.defaults = defaults
        self.downloadErrors = defaults.dictionary(forKey: Self.errorsKey) as? [String: String] ?? [:]
        self.modelsExist = modelsExist
        self.resetModels = resetModels
        self.downloadModels = downloadModels
    }

    // MARK: - Query helpers

    func isFluidAudioModelDownloaded(named modelName: String) -> Bool {
        // Paths can exist before loading/validation finishes, or after it fails.
        guard downloadErrors[modelName] == nil, downloadStatuses[modelName] == nil else { return false }
        let version = FluidAudioModelManager.asrVersion(for: modelName)
        return modelsExist(version)
    }

    func isFluidAudioModelDownloaded(_ model: FluidAudioModel) -> Bool {
        isFluidAudioModelDownloaded(named: model.name)
    }

    func isFluidAudioModelDownloading(_ model: FluidAudioModel) -> Bool {
        downloadStatuses[model.name] != nil
    }

    func downloadStatus(for model: FluidAudioModel) -> FluidAudioDownloadStatus? {
        downloadStatuses[model.name]
    }

    func downloadError(for model: FluidAudioModel) -> String? {
        downloadErrors[model.name]
    }

    // MARK: - Download

    func downloadFluidAudioModel(_ model: FluidAudioModel) async {
        if isFluidAudioModelDownloading(model) {
            return
        }
        if isFluidAudioModelDownloaded(model) {
            onModelsChanged?()
            return
        }

        let modelName = model.name
        let isRetry = downloadErrors[modelName] != nil
        // Keep the persisted failure until success, including if the app quits mid-retry.
        downloadErrors[modelName] = nil
        let downloadID = UUID()
        activeDownloadIDs[modelName] = downloadID
        downloadStatuses[modelName] = FluidAudioDownloadStatus(
            fractionCompleted: 0.0,
            message: "Preparing FluidAudio download..."
        )
        defer {
            clearDownloadStatus(for: modelName, downloadID: downloadID)
            onModelsChanged?()
        }

        let version = FluidAudioModelManager.asrVersion(for: modelName)
        let progressHandler: DownloadUtils.ProgressHandler = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(progress, for: modelName, downloadID: downloadID)
            }
        }

        do {
            if isRetry && modelsExist(version) {
                // The SDK skips downloads when all paths exist, even if vocabulary or
                // model contents are corrupt. Repair only this failed model's cache.
                try resetModels(version)
            }
            try await downloadModels(version, progressHandler)
            setDownloadError(nil, for: modelName)
        } catch {
            setDownloadError(error.localizedDescription, for: modelName)
            logger.error("❌ FluidAudio download failed for \(modelName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Delete

    func deleteFluidAudioModel(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.removeItem(at: cacheDirectory)
            }
            setDownloadError(nil, for: model.name)
        } catch {
            // Silently ignore removal errors
        }

        // Notify TranscriptionModelManager to clear currentTranscriptionModel if it matches
        onModelDeleted?(model.name)
    }

    // MARK: - Finder

    func showFluidAudioModelInFinder(_ model: FluidAudioModel) {
        let cacheDirectory = cacheDirectory(for: model)

        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            NSWorkspace.shared.selectFile(cacheDirectory.path, inFileViewerRootedAtPath: "")
        }
    }

    // MARK: - Private helpers

    private func setDownloadError(_ error: String?, for modelName: String) {
        downloadErrors[modelName] = error
        // Another model may be retrying concurrently: its persisted failure must
        // survive until that model succeeds, even while its visible error is cleared.
        var errors = defaults.dictionary(forKey: Self.errorsKey) as? [String: String] ?? [:]
        errors[modelName] = error
        defaults.set(errors, forKey: Self.errorsKey)
    }

    private func cacheDirectory(for model: FluidAudioModel) -> URL {
        cacheDirectory(for: FluidAudioModelManager.asrVersion(for: model.name))
    }

    private func cacheDirectory(for version: AsrModelVersion) -> URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    private func clearDownloadStatus(for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }
        activeDownloadIDs[modelName] = nil
        downloadStatuses[modelName] = nil
    }

    private func updateDownloadProgress(_ progress: DownloadUtils.DownloadProgress, for modelName: String, downloadID: UUID) {
        guard activeDownloadIDs[modelName] == downloadID else { return }

        // Drive the bar by FluidAudio's byte-weighted fraction, which advances smoothly with
        // bytes even while a single large file downloads. (This used to use the file count,
        // but Parakeet's one big model file is most of the total bytes, so the count froze on
        // it and the download looked stuck at e.g. "6/22 files" for a minute or more. #27)
        let fraction = min(max(progress.fractionCompleted, 0.0), 1.0)

        downloadStatuses[modelName] = FluidAudioDownloadStatus(
            fractionCompleted: fraction,
            message: FluidAudioModelManager.statusMessage(for: progress)
        )
    }

    private static func statusMessage(for progress: DownloadUtils.DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            return "Listing files from repository..."
        case .downloading(let completedFiles, let totalFiles):
            guard totalFiles > 0 else {
                return "Checking cached models..."
            }
            // No percentage here — the card shows a single overall % of its own, and the
            // spinner conveys liveness. Two differently-scaled percentages just confuse (#27).
            return "Downloading models: \(completedFiles)/\(totalFiles) files"
        case .compiling(let modelName):
            guard !modelName.isEmpty else {
                return "Finalizing models..."
            }
            return "Compiling \(displayName(forModelComponent: modelName))"
        }
    }

    private static func displayName(forModelComponent modelName: String) -> String {
        modelName.replacingOccurrences(of: ".mlmodelc", with: "")
    }
}
