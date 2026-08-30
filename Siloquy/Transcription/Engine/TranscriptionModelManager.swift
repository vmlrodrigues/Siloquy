import Foundation
import SwiftUI
import os

@MainActor
class TranscriptionModelManager: ObservableObject {
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var allAvailableModels: [any TranscriptionModel] = TranscriptionModelRegistry.models

    private weak var whisperModelManager: WhisperModelManager?
    private weak var fluidAudioModelManager: FluidAudioModelManager?

    private let logger = Logger(subsystem: "com.victorrodrigues.siloquy", category: "TranscriptionModelManager")

    init(whisperModelManager: WhisperModelManager, fluidAudioModelManager: FluidAudioModelManager) {
        self.whisperModelManager = whisperModelManager
        self.fluidAudioModelManager = fluidAudioModelManager

        // Wire up deletion callbacks so each manager notifies this manager.
        whisperModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }
        fluidAudioModelManager.onModelDeleted = { [weak self] modelName in
            self?.handleModelDeleted(modelName)
        }

        // Wire up "models changed" callbacks so this manager rebuilds allAvailableModels.
        whisperModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
        fluidAudioModelManager.onModelsChanged = { [weak self] in
            self?.refreshAllAvailableModels()
        }
    }

    // MARK: - Computed: usable models

    /// Names of the models that can run right now.
    ///
    /// Cached because deciding this asks the Keychain whether each cloud provider has a
    /// key — a synchronous XPC round-trip apiece — and stats the disk for the local
    /// ones. Callers read it from view bodies, so recomputing per read put that on the
    /// main actor during rendering and dictation.
    @Published private(set) var usableModelNames: Set<String> = []

    var usableModels: [any TranscriptionModel] {
        allAvailableModels.filter { usableModelNames.contains($0.name) }
    }

    /// Recompute what can run. Called wherever the answer can change: a model
    /// downloaded, deleted or imported, and an API key saved or cleared — all of which
    /// already route through `refreshAllAvailableModels()`.
    func refreshUsableModels() {
        let names = Set(allAvailableModels.filter { isUsable($0) }.map(\.name))
        if names != usableModelNames { usableModelNames = names }
    }

    private func isUsable(_ model: any TranscriptionModel) -> Bool {
        switch model.provider {
        case .whisper:
            return whisperModelManager?.availableModels.contains { $0.name == model.name } ?? false
        case .fluidAudio:
            return fluidAudioModelManager?.isFluidAudioModelDownloaded(named: model.name) ?? false
        case .nativeApple:
            if #available(macOS 26, *) { return true } else { return false }
        case .custom:
            return true
        default:
            if let cloudProvider = CloudProviderRegistry.provider(for: model.provider) {
                return APIKeyManager.shared.hasAPIKey(forProvider: cloudProvider.providerKey)
            }
            return false
        }
    }

    func isAvailableOnCurrentOS(_ model: any TranscriptionModel) -> Bool {
        switch model.provider {
        case .nativeApple:
            if #available(macOS 26, *) { return true } else { return false }
        default:
            return true
        }
    }

    // MARK: - Model loading from UserDefaults

    func loadCurrentTranscriptionModel() {
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            guard isAvailableOnCurrentOS(savedModel) else {
                UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
                currentTranscriptionModel = nil
                return
            }

            currentTranscriptionModel = savedModel
            ensureSelectedLanguageIsSupported(by: savedModel)
        }
    }

    // MARK: - Set default model

    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        guard isAvailableOnCurrentOS(model) else {
            NotificationManager.shared.showNotification(
                title: "\(model.displayName) requires macOS 26 or later",
                type: .error
            )
            return
        }

        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")
        ensureSelectedLanguageIsSupported(by: model)

        if model.provider != .whisper {
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = true
        }

        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    private func ensureSelectedLanguageIsSupported(by model: any TranscriptionModel) {
        let currentLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage")
        let compatibleLanguage = TranscriptionLanguageSupport.validLanguageOrFallback(currentLanguage, for: model)

        if currentLanguage != compatibleLanguage {
            UserDefaults.standard.set(compatibleLanguage, forKey: "SelectedLanguage")
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    // MARK: - Refresh all available models

    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = TranscriptionModelRegistry.models

        for whisperModel in whisperModelManager?.availableModels ?? [] {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedWhisperModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models
        // Every path that changes what can run — download, delete, import, key saved or
        // cleared — comes through here, so this is the one place that must invalidate.
        refreshUsableModels()

        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setDefaultTranscriptionModel(updatedModel)
        }
    }

    // MARK: - Clear current model

    func clearCurrentTranscriptionModel() {
        currentTranscriptionModel = nil
        UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
    }

    // MARK: - Handle model deletion callback

    /// Called by WhisperModelManager.onModelDeleted or FluidAudioModelManager.onModelDeleted.
    func handleModelDeleted(_ modelName: String) {
        if currentTranscriptionModel?.name == modelName {
            currentTranscriptionModel = nil
            UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel")
            whisperModelManager?.loadedWhisperModel = nil
            whisperModelManager?.isModelLoaded = false
            UserDefaults.standard.removeObject(forKey: "CurrentModel")
        }
        refreshAllAvailableModels()
    }
}
