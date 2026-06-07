import SwiftUI
import LLMkit

struct APIKeyManagementView: View {
    @EnvironmentObject private var aiService: AIService
    @State private var apiKey: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isVerifying = false
    @State private var ollamaBaseURL: String = UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
    @State private var ollamaModels: [OllamaModel] = []
    @State private var selectedOllamaModel: String = UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
    @State private var isCheckingOllama = false
    @State private var isEditingURL = false
    @State private var localCLICommandTemplate: String = ""
    @State private var localCLITimeoutSeconds: Double = LocalCLIService.defaultTimeoutSeconds
    @State private var isSyncingLocalCLIState = false
    @State private var showDeleteGemmaConfirm = false
    
    var body: some View {
        Section("AI Provider Integration") {
            HStack {
                Picker("Provider", selection: $aiService.selectedProvider) {
                    ForEach(AIProvider.allCases.filter { $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox && $0 != .speechmatics && $0 != .assemblyAI }, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.automatic)
                .tint(.blue)
                
                if aiService.isAPIKeyValid && aiService.selectedProvider != .ollama {
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if aiService.selectedProvider == .ollama {
                    Spacer()
                    if isCheckingOllama {
                        ProgressView()
                            .controlSize(.small)
                    } else if !ollamaModels.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Disconnected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: aiService.selectedProvider) { oldValue, newValue in
                if aiService.selectedProvider == .ollama {
                    checkOllamaConnection()
                }
                if aiService.selectedProvider == .localCLI {
                    syncLocalCLIStateFromService()
                }
                if aiService.selectedProvider == .gemmaLocal {
                    if aiService.gemmaService.isModelDownloaded {
                        Task { await aiService.gemmaService.initializeEngine() }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Model Selection
                if aiService.selectedProvider == .openRouter {
                    if aiService.availableModels.isEmpty {
                        HStack {
                            Text("No models loaded")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    } else {
                        HStack {
                            Picker("Model", selection: Binding(
                                get: { aiService.currentModel },
                                set: { aiService.selectModel($0) }
                            )) {
                                ForEach(aiService.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    await aiService.fetchOpenRouterModels()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    
                } else if !aiService.availableModels.isEmpty &&
                            aiService.selectedProvider != .ollama &&
                            aiService.selectedProvider != .custom &&
                            aiService.selectedProvider != .gemmaLocal {
                    Picker("Model", selection: Binding(
                        get: { aiService.currentModel },
                        set: { aiService.selectModel($0) }
                    )) {
                        ForEach(aiService.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                if aiService.selectedProvider == .ollama {
                    if isEditingURL {
                        HStack {
                            TextField("Base URL", text: $ollamaBaseURL)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Save") {
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                                isEditingURL = false
                            }
                        }
                    } else {
                        HStack {
                            Text("Server: \(ollamaBaseURL)")
                            Spacer()
                            Button("Edit") { isEditingURL = true }
                            Button(action: {
                                ollamaBaseURL = "http://localhost:11434"
                                aiService.updateOllamaBaseURL(ollamaBaseURL)
                                checkOllamaConnection()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help("Reset to default")
                        }
                    }

                    if !ollamaModels.isEmpty {
                        Divider()

                        Picker("Model", selection: $selectedOllamaModel) {
                            ForEach(ollamaModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .onChange(of: selectedOllamaModel) { oldValue, newValue in
                            aiService.updateSelectedOllamaModel(newValue)
                        }
                    }

                } else if aiService.selectedProvider == .localCLI {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Command")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Menu("Load Template") {
                                ForEach(LocalCLITemplate.allCases) { template in
                                    Button(template.displayName) {
                                        aiService.loadLocalCLITemplate(template)
                                        syncLocalCLIStateFromService()
                                    }
                                }
                            }
                        }

                        TextEditor(text: $localCLICommandTemplate)
                            .font(.system(.body, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                            .onChange(of: localCLICommandTemplate) { _, newValue in
                                guard !isSyncingLocalCLIState else { return }
                                if newValue != aiService.localCLICommandTemplate {
                                    aiService.updateLocalCLICommandTemplate(newValue)
                                }
                            }
                    }

                    Picker("Timeout", selection: $localCLITimeoutSeconds) {
                        Text("15s").tag(15.0)
                        Text("30s").tag(30.0)
                        Text("45s").tag(45.0)
                        Text("60s").tag(60.0)
                        Text("90s").tag(90.0)
                        Text("120s").tag(120.0)
                        Text("180s").tag(180.0)
                        Text("300s").tag(300.0)
                    }
                    .onChange(of: localCLITimeoutSeconds) { _, newValue in
                        aiService.updateLocalCLITimeoutSeconds(newValue)
                    }

                    Text("Environment variables available: VOICEINK_SYSTEM_PROMPT, VOICEINK_USER_PROMPT, VOICEINK_FULL_PROMPT. VoiceInk also writes VOICEINK_FULL_PROMPT to stdin for every command.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !aiService.isAPIKeyValid {
                        Text("Load a template or enter a command to enable Local CLI enhancement.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                } else if aiService.selectedProvider == .gemmaLocal {
                    GemmaLocalSetupView(
                        gemmaService: aiService.gemmaService,
                        showDeleteConfirm: $showDeleteGemmaConfirm,
                        onDeleted: { aiService.refreshGemmaValidityState() }
                    )
                } else if aiService.selectedProvider == .custom {
                    TextField("API Endpoint URL", text: $aiService.customBaseURL, prompt: Text("e.g. https://api.openai.com/v1/chat/completions"))
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    TextField("Model Name", text: $aiService.customModel, prompt: Text("e.g. gemini-3.1-pro-preview, gpt-5.5"))
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    if aiService.isAPIKeyValid {
                        HStack {
                            Text("API Key Set")
                            Spacer()
                            Button("Remove Key", role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        Button("Verify and Save") {
                            isVerifying = true
                            aiService.saveAPIKey(apiKey) { success, errorMessage in
                                isVerifying = false
                                if !success {
                                    alertMessage = errorMessage ?? "Verification failed"
                                    showAlert = true
                                }
                                apiKey = ""
                            }
                        }
                        .disabled(aiService.customBaseURL.isEmpty || aiService.customModel.isEmpty || apiKey.isEmpty)
                    }
                    
                } else {
                    if aiService.isAPIKeyValid {
                        HStack {
                            Text("API Key")
                            Spacer()
                            Text("••••••••")
                                .foregroundColor(.secondary)
                            Button("Remove", role: .destructive) {
                                aiService.clearAPIKey()
                            }
                        }
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            if let url = getAPIKeyURL() {
                                Link(destination: url) {
                                    HStack {
                                        Image(systemName: "key.fill")
                                        Text("Get API Key")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Button(action: {
                                isVerifying = true
                                aiService.saveAPIKey(apiKey) { success, errorMessage in
                                    isVerifying = false
                                    if !success {
                                        alertMessage = errorMessage ?? "Verification failed"
                                        showAlert = true
                                    }
                                    apiKey = ""
                                }
                            }) {
                                HStack {
                                    if isVerifying {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text("Verify and Save")
                                }
                            }
                            .disabled(apiKey.isEmpty)
                        }
                    }
                }
            }
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            if aiService.selectedProvider == .ollama {
                checkOllamaConnection()
            }
            if aiService.selectedProvider == .localCLI {
                syncLocalCLIStateFromService()
            }
            if aiService.selectedProvider == .gemmaLocal
                && aiService.gemmaService.isModelDownloaded {
                Task { await aiService.gemmaService.initializeEngine() }
            }
        }
    }

    private func syncLocalCLIStateFromService() {
        isSyncingLocalCLIState = true
        localCLICommandTemplate = aiService.localCLICommandTemplate
        localCLITimeoutSeconds = aiService.localCLITimeoutSeconds
        DispatchQueue.main.async {
            isSyncingLocalCLIState = false
        }
    }
    
    private func checkOllamaConnection() {
        isCheckingOllama = true
        aiService.checkOllamaConnection { connected in
            if connected {
                Task {
                    ollamaModels = await aiService.fetchOllamaModels()
                    isCheckingOllama = false
                }
            } else {
                ollamaModels = []
                isCheckingOllama = false
                alertMessage = "Could not connect to Ollama. Please check if Ollama is running and the base URL is correct."
                showAlert = true
            }
        }
    }
    
    private func getAPIKeyURL() -> URL? {
        switch aiService.selectedProvider {
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://makersuite.google.com/app/apikey")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .elevenLabs: return URL(string: "https://elevenlabs.io/speech-synthesis")
        case .deepgram: return URL(string: "https://console.deepgram.com/api-keys")
        case .soniox: return URL(string: "https://console.soniox.com/")
        case .speechmatics: return URL(string: "https://portal.speechmatics.com/manage-access/")
        case .assemblyAI: return URL(string: "https://www.assemblyai.com/dashboard/api-keys")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .cerebras: return URL(string: "https://cloud.cerebras.ai/")
        default: return nil
        }
    }
}

// MARK: - Local Models Setup View

private struct GemmaLocalSetupView: View {
    @ObservedObject var gemmaService: GemmaService
    @Binding var showDeleteConfirm: Bool
    let onDeleted: () -> Void

    @State private var showFilePicker = false
    @State private var importTargetModel: LocalModel?
    @State private var deleteTargetModel: LocalModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Engine state banner (shown when a model is selected and active)
            if let selected = gemmaService.selectedModel {
                engineBanner(for: selected)
                    .padding(.bottom, 8)
            }

            // One row per catalogued model
            ForEach(Array(GemmaService.catalog.enumerated()), id: \.element.id) { index, model in
                if index > 0 { Divider().padding(.vertical, 6) }
                modelRow(for: model)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.init(filenameExtension: "litertlm") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard let target = importTargetModel else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                gemmaService.importModel(from: url, as: target)
            case .failure(let error):
                gemmaService.downloadStates[target.id] = .error("Import failed: \(error.localizedDescription)")
            }
        }
        .confirmationDialog(
            "Delete \(deleteTargetModel?.displayName ?? "model")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let m = deleteTargetModel { gemmaService.deleteModel(m) }
                onDeleted()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The model file will be removed. You can download it again at any time.")
        }
    }

    // MARK: - Engine banner

    @ViewBuilder
    private func engineBanner(for model: LocalModel) -> some View {
        switch gemmaService.engineState {
        case .initializing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Warming up \(model.displayName)…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .ready:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("\(model.displayName) ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .error(let msg):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    .font(.caption)
                Text(msg).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Retry") { Task { await gemmaService.initializeEngine() } }
                    .controlSize(.small).buttonStyle(.bordered)
            }
        case .notReady:
            EmptyView()
        }
    }

    // MARK: - Model row

    @ViewBuilder
    private func modelRow(for model: LocalModel) -> some View {
        let isSelected = gemmaService.selectedModelID == model.id
        let state = gemmaService.downloadStates[model.id] ?? .notDownloaded

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Selection indicator
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 14))
                    .onTapGesture {
                        Task { await gemmaService.selectModel(model) }
                    }

                // Name + detail
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(model.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons
                actionButtons(for: model, state: state)
            }

            // Progress bar (downloading only)
            if case .downloading(let progress) = state {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress).progressViewStyle(.linear)
                    Text("\(Int(progress * 100))% of \(model.formattedSize)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 22)
            }

            // Error message
            if case .error(let msg) = state {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 22)
            }
        }
    }

    // MARK: - Action buttons per state

    @ViewBuilder
    private func actionButtons(for model: LocalModel, state: DownloadState) -> some View {
        switch state {
        case .notDownloaded:
            HStack(spacing: 6) {
                Button("Download") {
                    gemmaService.startDownload(for: model)
                    Task { await gemmaService.selectModel(model) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Import…") {
                    importTargetModel = model
                    showFilePicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .downloading:
            Button("Cancel") { gemmaService.cancelDownload(for: model) }
                .buttonStyle(.bordered)
                .controlSize(.small)

        case .downloaded:
            HStack(spacing: 6) {
                if gemmaService.selectedModelID != model.id {
                    Button("Use") {
                        Task { await gemmaService.selectModel(model) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("Delete", role: .destructive) {
                    deleteTargetModel = model
                    showDeleteConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .error:
            HStack(spacing: 6) {
                Button("Retry") { gemmaService.startDownload(for: model) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Import…") {
                    importTargetModel = model
                    showFilePicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
