import SwiftUI
import SwiftData
import Speech
import AVFoundation

// MARK: - SpeechKit (nonisolated call-site helpers)
//
// Both SFSpeechRecognizer.requestAuthorization AND recognitionTask(resultHandler:)
// deliver their callbacks on a background thread (Apple's internal speech queue).
//
// In Swift 6, any closure created inside a @MainActor context — including every
// method on a SwiftUI View — is stamped with @MainActor isolation. When the
// callback fires on the background thread, _swift_task_checkIsolatedSwift asserts
// main-actor isolation and traps BEFORE any code in the closure body runs.
// DispatchQueue.main.async inside the body therefore cannot help.
//
// Fix: route each call through a `nonisolated static func`. This breaks the
// @MainActor context at the call site so the closure the SDK receives carries no
// actor-isolation requirement. We then hop back to main explicitly where needed.

enum SpeechKit {

    /// Wraps SFSpeechRecognizer.requestAuthorization to prevent @MainActor
    /// isolation being stamped onto the callback closure.
    nonisolated static func requestAuthorization(
        _ completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { status in
            completion(status)
        }
    }

    /// Wraps recognitionTask(with:resultHandler:) for the same reason.
    /// startRecording() is @MainActor, which would otherwise stamp the
    /// resultHandler closure with @MainActor isolation → background-thread crash.
    nonisolated static func startTask(
        on recognizer: SFSpeechRecognizer,
        with request: SFSpeechAudioBufferRecognitionRequest,
        resultHandler: @escaping @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request, resultHandler: resultHandler)
    }

    /// AVAudioEngine tap callbacks fire on RealtimeMessenger.mServiceQueue, not MainActor.
    /// Installing the tap from @MainActor stamps isolation onto the closure → crash.
    nonisolated static func installInputTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        bufferSize: AVAudioFrameCount = 1024
    ) {
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            request.append(buffer)
        }
    }
}

// MARK: - VoiceRecordingController
//
// Owns every AVFoundation/Speech object so they live on a single, stable,
// @MainActor-isolated reference rather than scattered across @State copies.
// @StateObject guarantees SwiftUI creates this once on the main thread.

@MainActor
final class VoiceRecordingController: ObservableObject {
    let audioEngine = AVAudioEngine()
    var recognizer: SFSpeechRecognizer?
    var request:  SFSpeechAudioBufferRecognitionRequest?
    var task:     SFSpeechRecognitionTask?

    @Published var showLowConfidenceWarning = false

    private(set) var isRunning = false
    private var tapInstalled = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Self.preferredRecognitionLocale())
    }

    static func defaultLocaleID() -> String {
        Locale.current.region?.identifier == "IN" ? "en-IN" : "en-US"
    }

    static func preferredRecognitionLocale() -> Locale {
        let region = Locale.current.region?.identifier ?? ""
        return region == "IN" ? Locale(identifier: "en-IN") : .current
    }

    func setRecognizerLocale(_ locale: Locale) {
        stop()
        recognizer = SFSpeechRecognizer(locale: locale)
        showLowConfidenceWarning = false
    }

    enum RecordingError: LocalizedError {
        case invalidInputFormat
        case engineStartFailed

        var errorDescription: String? {
            switch self {
            case .invalidInputFormat: return "Microphone input is unavailable."
            case .engineStartFailed:  return "Recording failed to start."
            }
        }
    }

    /// Tear down the engine and speech task cleanly.
    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func installTap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) throws {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecordingError.invalidInputFormat }

        SpeechKit.installInputTap(on: inputNode, format: format, request: request)
        tapInstalled = true
    }

    func startEngine() throws {
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            throw RecordingError.engineStartFailed
        }
    }
}

// MARK: - RecordingPulseRing
//
// Isolated subview so repeatForever animation runs in .task (next run-loop turn),
// not in onAppear during the same update that flips isRecording → avoids
// AttributeGraph / "modifying state during view update" crashes.

private struct RecordingPulseRing: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color.stoqlyDanger.opacity(0.3), lineWidth: 3)
            .frame(width: 96, height: 96)
            .scaleEffect(expanded ? 1.15 : 1.0)
            .task {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
    }
}

// MARK: - VoiceInventoryView
//
// Step 1 — Record: user taps record, speaks item names and counts naturally.
//           Live transcript shown in real time. Tap stop when done.
// Step 2 — AI Parse: transcript sent to Claude → structured items returned.
// Step 3 — Review: editable table of items. User confirms/removes before saving.
//
// Free limit: 3 uses per calendar month. Pro = unlimited.

struct VoiceInventoryView: View {
    var preselectedStorage: Storage? = nil
    var onComplete: ((Int) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    // Audio controller — @StateObject ensures single ownership, main-thread init.
    @StateObject private var audio = VoiceRecordingController()
    @StateObject private var sarvamRecorder = SarvamSpeechTranscriber()

    // @ObservedObject, not @StateObject — AIUsageManager.shared is a pre-existing
    // @MainActor singleton; @StateObject would incorrectly take ownership of it.
    @ObservedObject private var usageManager: AIUsageManager = AIUsageManager.shared

    // State machine
    enum Step { case record, parsing, review, saving }
    @State private var step: Step = .record

    // Recording UI state only — audio objects live in VoiceRecordingController
    @State private var isRecording  = false
    @State private var transcript   = ""

    // Results
    @State private var parsedItems: [ParsedInventoryItem] = []
    @State private var editableItems: [EditableItem] = []
    @State private var selectedStorage: Storage?
    @State private var errorMessage: String?
    @State private var showingPaywall = false
    @State private var showingItemLimitPaywall = false
    @State private var recordingPermissionDenied = false
    @State private var didRequestRecordingPermissions = false
    @State private var selectedLocale: String = VoiceRecordingController.defaultLocaleID()
    @State private var isCloudRecognizing = false
    @State private var voiceEngine: VoiceSpeechEngine = .apple(localeID: VoiceRecordingController.defaultLocaleID())
    @State private var didTrackVoiceEngineForSession = false

    private var localePills: [(String, String)] {
        let lang = localizationManager.currentCode
        let normalized = lang?.split(separator: "-").first.map(String.init) ?? "en"
        if normalized == "en" || lang == nil {
            return SpeechEnginePicker.englishLocalePills()
        }
        let localeID = SpeechEnginePicker.voiceLocaleID(for: lang)
        return [(localeID, SpeechEnginePicker.localeDisplayName(for: localeID))]
    }

    private var voiceUnavailable: Bool {
        if case .unavailable = voiceEngine { return true }
        return false
    }

    private var usesCloudEngine: Bool {
        if case .sarvam = voiceEngine { return true }
        return false
    }

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
    }

    private var remainingItemSlots: Int {
        ItemCapReview.remainingSlots(
            storage: selectedStorage,
            context: modelContext,
            isPro: subscriptionManager.isPro
        )
    }

    private var canSaveReviewItems: Bool {
        isStorageSelected && ItemCapReview.canSave(
            items: editableItems,
            remainingSlots: remainingItemSlots,
            isPro: subscriptionManager.isPro
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .record:  recordView
                case .parsing: parsingView
                case .review:  reviewView
                case .saving:  savingView
                }
            }
            .navigationTitle("Voice Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        stopRecording()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "ai_limit").sheetStyle()
        }
        .sheet(isPresented: $showingItemLimitPaywall) {
            PaywallView(source: "item_limit", trigger: "item_cap_bulk").sheetStyle()
        }
        .onAppear {
            if selectedStorage == nil, let preselectedStorage {
                selectedStorage = preselectedStorage
            }
            refreshVoiceEngine()
            guard !didRequestRecordingPermissions else { return }
            didRequestRecordingPermissions = true
            requestRecordingPermissions()
            if case .apple = voiceEngine {
                audio.setRecognizerLocale(Locale(identifier: selectedLocale))
            }
        }
        .onChange(of: localizationManager.refreshID) { _, _ in
            refreshVoiceEngine()
        }
        .onChange(of: selectedLocale) { _, newLocale in
            if isRecording { stopRecording() }
            if case .apple = voiceEngine {
                audio.setRecognizerLocale(Locale(identifier: newLocale))
            }
        }
    }

    private func refreshVoiceEngine() {
        voiceEngine = SpeechEnginePicker.pickEngine(for: localizationManager.currentCode)
        switch voiceEngine {
        case .apple(let localeID):
            selectedLocale = localeID
            audio.setRecognizerLocale(Locale(identifier: localeID))
        case .sarvam(let languageCode):
            selectedLocale = languageCode
        case .unavailable:
            break
        }
    }

    // MARK: - Step 1: Record

    private var recordView: some View {
        ScrollView {
            VStack(spacing: 24) {

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(localePills, id: \.0) { id, label in
                            Button(label) { selectedLocale = id }
                                .font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(selectedLocale == id ? Color.stoqlyPrimary : Color(.systemGray5))
                                .foregroundColor(selectedLocale == id ? .white : .primary)
                                .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal)
                }

                if voiceUnavailable {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Voice not available in this language", systemImage: "mic.slash")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.stoqlyWarning)
                        Text("Voice counting isn't available in this language yet — try Photo or Sheet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.stoqlyWarningTint)
                    .cornerRadius(10)
                }

                if isCloudRecognizing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Recognizing (cloud)…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.stoqlyCard)
                    .cornerRadius(10)
                }

                // Usage badge
                if !subscriptionManager.isPro {
                    let remaining = usageManager.remaining(.voice, isPro: false)
                    HStack(spacing: 8) {
                        Image(systemName: "mic.badge.plus")
                            .foregroundColor(.stoqlyPrimary)
                        Text(
                            String(
                                format: L("ai.voice.quotaRemaining", "%1$d voice count%2$@ left this month"),
                                remaining,
                                remaining == 1 ? "" : "s"
                            )
                        )
                            .font(.subheadline)
                        Spacer()
                        Button("Go Pro") { showingPaywall = true }
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.stoqlyPrimary)
                    }
                    .padding(12)
                    .background(Color.stoqlyPrimaryTint)
                    .cornerRadius(10)
                }

                // Storage picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Count into")
                        .font(.subheadline).fontWeight(.semibold)
                    if storages.isEmpty {
                        Text("No storages yet — add one first.")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Picker("Storage", selection: $selectedStorage) {
                            Text("Select storage").tag(Optional<Storage>.none)
                            ForEach(storages) { s in
                                Text(s.name).tag(Optional(s))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.stoqlyPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.stoqlyCard)
                        .cornerRadius(AppTheme.radiusMd)
                    }
                    if !storages.isEmpty && selectedStorage == nil {
                        Text("Select a storage to enable voice inventory.")
                            .font(.caption)
                            .foregroundColor(.stoqlyWarning)
                    }
                }

                // Tip card
                VStack(alignment: .leading, spacing: 8) {
                    Label("How to speak your inventory", systemImage: "lightbulb")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.stoqlyAccent)
                    Text("\"5 kg of flour, 3 bottles of olive oil, 2 boxes of sugar, and we're out of salt\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(12)
                .background(Color.stoqlyAccentTint)
                .cornerRadius(10)

                // Transcript area
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.subheadline).fontWeight(.semibold)

                    if audio.showLowConfidenceWarning {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                            Text("Low confidence — please check and edit the text below before analysing.")
                                .font(.caption)
                        }
                    }

                    TextEditor(text: $transcript)
                        .font(.body)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(Color.stoqlyCard)
                        .cornerRadius(AppTheme.radiusMd)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                                .stroke(isRecording ? Color.stoqlyDanger.opacity(0.5) : Color(.separator), lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if transcript.isEmpty {
                                Text("Your speech will appear here…")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(16)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.stoqlyDanger)
                        .padding(10)
                        .background(Color.stoqlyDangerTint)
                        .cornerRadius(8)
                }

                if recordingPermissionDenied {
                    VStack(spacing: 8) {
                        Text("Microphone and speech recognition access are required for voice inventory.")
                            .font(.subheadline).multilineTextAlignment(.center)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.stoqlyPrimary)
                    }
                    .padding()
                    .background(Color.stoqlyCard)
                    .cornerRadius(AppTheme.radiusMd)
                }

                // Record button
                if !voiceUnavailable {
                VStack(spacing: 12) {
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.stoqlyDanger : Color.stoqlyPrimary)
                                .frame(width: 80, height: 80)
                                .shadow(color: (isRecording ? Color.stoqlyDanger : Color.stoqlyPrimary).opacity(0.4),
                                        radius: 12, x: 0, y: 4)

                            if isRecording {
                                RecordingPulseRing()
                            }

                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(recordingPermissionDenied || !isStorageSelected || isCloudRecognizing)

                    Text(isRecording ? "Tap to stop" : "Tap to record")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                }

                if !transcript.isEmpty && !isRecording {
                    Button("Analyse with AI") {
                        Task { await parseTranscript() }
                    }
                    .stoqlyButtonStyle()
                    .disabled(!isStorageSelected)
                    .padding(.top, 4)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    // MARK: - Step 2: Parsing

    private var parsingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(.stoqlyPrimary)
            Text("Analysing your transcript…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Step 3: Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            if editableItems.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "mic.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No items detected")
                        .font(.title3).fontWeight(.semibold)
                    Text("Try speaking more clearly or add items manually.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { step = .record }
                        .stoqlyButtonStyle()
                    Spacer()
                }
                .padding()
            } else {
                if ItemCapReview.shouldShowBanner(
                    newCount: ItemCapReview.newCount(editableItems),
                    remainingSlots: remainingItemSlots,
                    isPro: subscriptionManager.isPro
                ) {
                    ItemCapOverflowBanner(remainingSlots: remainingItemSlots) {
                        showingItemLimitPaywall = true
                    }
                }

                List {
                    Section {
                        ForEach($editableItems) { $item in
                            EditableItemRow(
                                item: $item,
                                selectedStorage: selectedStorage,
                                isPro: subscriptionManager.isPro,
                                remainingSlots: remainingItemSlots
                            )
                        }
                        .onDelete { editableItems.remove(atOffsets: $0) }
                    } header: {
                        HStack {
                            Text("\(editableItems.count) item\(editableItems.count == 1 ? "" : "s") detected")
                            Spacer()
                            Text("Swipe to remove")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                VStack(spacing: 12) {
                    Divider()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.stoqlyDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    if !subscriptionManager.isPro {
                        ItemCapSelectionCounter(
                            selectedNew: ItemCapReview.selectedNewCount(editableItems),
                            remainingSlots: remainingItemSlots
                        )
                    }
                    HStack(spacing: 12) {
                        Button("Re-record") {
                            transcript = ""
                            editableItems = []
                            errorMessage = nil
                            step = .record
                        }
                        .font(.subheadline)
                        .foregroundColor(.stoqlyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.stoqlyPrimaryTint)
                        .cornerRadius(AppTheme.radiusMd)

                        Button("Add to Inventory") {
                            Task { await saveItems() }
                        }
                        .stoqlyButtonStyle()
                        .frame(maxWidth: .infinity)
                        .disabled(!canSaveReviewItems)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Step 4: Saving

    private var savingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(.stoqlySuccess)
            Text("Saving items…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Logic: Recording

    private func requestRecordingPermissions() {
        SpeechKit.requestAuthorization { speechStatus in
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    AnalyticsManager.shared.track(.permissionResult(type: "speech", granted: speechStatus == .authorized))
                    AnalyticsManager.shared.track(.permissionResult(type: "microphone", granted: micGranted))
                    recordingPermissionDenied = speechStatus != .authorized || !micGranted
                }
            }
        }
    }

    private func toggleRecording() {
        guard !recordingPermissionDenied else { return }
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording, !audio.isRunning, !isCloudRecognizing else { return }
        guard !voiceUnavailable else { return }
        guard usageManager.canUse(.voice, isPro: subscriptionManager.isPro) else {
            showingPaywall = true
            return
        }

        errorMessage = nil
        audio.showLowConfidenceWarning = false
        didTrackVoiceEngineForSession = false

        switch voiceEngine {
        case .apple:
            startAppleRecording()
        case .sarvam:
            startSarvamRecording()
        case .unavailable:
            break
        }
    }

    private func startAppleRecording() {
        audio.stop()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = L("voice.audioSessionFailed", "Could not start audio session.")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        audio.request = req

        guard let recognizer = audio.recognizer, recognizer.isAvailable else {
            errorMessage = L("voice.recognizerUnavailable", "Speech recognizer unavailable.")
            audio.stop()
            return
        }

        audio.task = SpeechKit.startTask(on: recognizer, with: req) { result, error in
            let transcriptText = result?.bestTranscription.formattedString
            let isFinal        = result?.isFinal ?? false
            let minConfidence  = result?.bestTranscription.segments.map(\.confidence).min()
            DispatchQueue.main.async {
                handleRecognitionUpdate(
                    transcriptText: transcriptText,
                    isFinal: isFinal,
                    minConfidence: minConfidence,
                    error: error
                )
            }
        }

        do {
            try audio.installTap(appendingTo: req)
            try audio.startEngine()
            isRecording = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("voice.recordingFailed", "Recording failed to start.")
            stopRecording()
        }
    }

    private func startSarvamRecording() {
        audio.stop()
        do {
            try sarvamRecorder.startRecording()
            isRecording = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("voice.recordingFailed", "Recording failed to start.")
            sarvamRecorder.stopRecording(deleteFile: true)
        }
    }

    private func handleRecognitionUpdate(
        transcriptText: String?,
        isFinal: Bool,
        minConfidence: Float?,
        error: (any Error)?
    ) {
        guard isRecording || audio.isRunning else { return }

        if let transcriptText {
            transcript = transcriptText
            trackVoiceEngineUsedIfNeeded()
        }

        if let minConfidence, minConfidence < 0.6 {
            audio.showLowConfidenceWarning = true
        }

        if isFinal {
            stopRecording()
            return
        }

        guard let error else { return }

        // 216 = recognition cancelled by us in stop() — ignore.
        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 { return }

        errorMessage = error.localizedDescription
        stopRecording()
    }

    private func stopRecording() {
        guard isRecording || audio.isRunning || isCloudRecognizing else { return }

        if usesCloudEngine, isRecording {
            isRecording = false
            isCloudRecognizing = true
            errorMessage = nil
            let languageCode = selectedLocale
            Task {
                do {
                    let text = try await sarvamRecorder.transcribe(languageCode: languageCode)
                    transcript = text
                    trackVoiceEngineUsedIfNeeded()
                    isCloudRecognizing = false
                } catch {
                    isCloudRecognizing = false
                    errorMessage = error.localizedDescription
                    sarvamRecorder.stopRecording(deleteFile: true)
                }
            }
            return
        }

        audio.stop()
        sarvamRecorder.stopRecording(deleteFile: true)
        isRecording = false
    }

    private func trackVoiceEngineUsedIfNeeded() {
        guard !didTrackVoiceEngineForSession else { return }
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let engine: String
        switch voiceEngine {
        case .apple: engine = "apple"
        case .sarvam: engine = "sarvam"
        case .unavailable: return
        }

        didTrackVoiceEngineForSession = true
        AnalyticsManager.shared.track(.voiceEngineUsed(engine: engine, language: selectedLocale))
    }

    // MARK: - Logic: AI Parse

    private func parseTranscript() async {
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard usageManager.canUse(.voice, isPro: subscriptionManager.isPro) else {
            showingPaywall = true
            return
        }

        step = .parsing
        let clock = AIRequestClock(
            feature: "voice_count",
            mode: "voice",
            inputBytes: transcript.utf8.count
        )
        do {
            let hints = allItems.prefix(50).map(\.name)
            let items = try await AIInventoryService.shared.parseVoiceTranscript(
                transcript,
                inventoryHints: Array(hints),
                appLanguageCode: localizationManager.currentCode
            )
            clock.finish(itemCount: items.count)
            usageManager.recordUse(.voice)
            editableItems = items.map { EditableItem(from: $0) }
            editableItems.applyNameMatching(in: selectedStorage)
            editableItems.applyDefaultCapSelection(
                remainingSlots: remainingItemSlots,
                isPro: subscriptionManager.isPro
            )
            step = .review
        } catch {
            errorMessage = error.localizedDescription
            clock.finish(error: error, stage: "parse")
            AnalyticsManager.shared.track(.smartCountFailed(mode: "voice", reason: error.localizedDescription))
            step = .record
        }
    }

    // MARK: - Logic: Save

    private func saveItems() async {
        guard let storage = selectedStorage else { return }
        errorMessage = nil
        step = .saving

        let itemsToSave = editableItems.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        var runningCount = SubscriptionManager.shared.itemCount(in: storage, context: modelContext)
        var appliedCount = 0

        for editable in itemsToSave {
            let matchedUOM = uoms.first { $0.symbol.lowercased() == (editable.unitSymbol?.lowercased() ?? "") }

            switch editable.match {
            case .existing(let existing):
                let qty = editable.quantity ?? existing.currentQuantity
                let count = InventoryCount(previousQuantity: existing.currentQuantity, countedQuantity: qty, notes: "Voice inventory")
                existing.countHistory.append(count)
existing.lastCountedAt = count.countDate
                existing.currentQuantity = qty
                existing.applyCapturedFields(from: editable)
                let event = ActivityEvent(
                    eventType: "ItemCounted",
                    itemName: existing.name,
                    storageName: storage.name,
                    quantityBefore: count.previousQuantity,
                    quantityAfter: qty,
                    notes: "Voice inventory",
                    performedBy: "You"
                )
                modelContext.insert(event)
                appliedCount += 1
            case .new:
                guard subscriptionManager.isPro || editable.isSelectedForAdd else { continue }
                guard SubscriptionManager.shared.canInsertNewItem(runningCount: &runningCount) else {
                    continue
                }
                let item = InventoryItem(
                    name: editable.name,
                    description: editable.aiNotes ?? "",
                    sku: editable.sku ?? "",
                    barcode: editable.barcode ?? "",
                    currentQuantity: editable.quantity ?? 0,
                    minQuantity: editable.minQuantity ?? 0,
                    unitCost: editable.unitCost ?? 0,
                    category: editable.category ?? "Uncategorised",
                    expiryDate: editable.expiryDate,
                    storage: storage,
                    uom: matchedUOM
                )
                if let sellingPrice = editable.sellingPrice {
                    item.sellingPrice = sellingPrice
                }
                modelContext.insert(item)
                AnalyticsManager.shared.track(.itemAdded(
                    category: item.category,
                    hasBarcode: !(editable.barcode?.isEmpty ?? true),
                    hasPhoto: false,
                    source: "ai",
                    inputMethod: "voice"
                ))
                let event = ActivityEvent(
                    eventType: "ItemAdded",
                    itemName: item.name,
                    storageName: storage.name,
                    notes: "Added via voice inventory",
                    performedBy: "You"
                )
                modelContext.insert(event)
                appliedCount += 1
            }
        }

        guard modelContext.safeSave(context: "VoiceInventorySave") else {
            errorMessage = L("voice.saveFailed", "Couldn't save your inventory changes. Please try again.")
            step = .review
            return
        }

        AnalyticsManager.shared.track(.smartCountCompleted(
            mode: "voice",
            itemCount: appliedCount,
            capturedExtraFields: {
                let fields = Array(Set(itemsToSave.flatMap(\.capturedExtraFieldNames)))
                return fields.isEmpty ? nil : fields
            }()
        ))

        // Sync to Firestore
        Task {
            for item in storage.items {
                FirestoreManager.shared.syncItem(item)
            }
        }

        onComplete?(appliedCount)
        dismiss()
    }
}

// MARK: - EditableItem (mutable copy for review table)

struct EditableItem: Identifiable {
    enum ItemMatch {
        case existing(InventoryItem)
        case new
    }

    let id: UUID
    var name: String
    var quantity: Double?
    var unitSymbol: String?
    var category: String?
    var confidence: Double
    var fillPercent: Double?
    var remainingVolume: String?
    var unitCost: Double?
    var sellingPrice: Double?
    var expiryDate: Date?
    var sku: String?
    var barcode: String?
    var minQuantity: Double?
    var aiNotes: String?
    var match: ItemMatch = .new
    /// Free-tier: whether this NEW row should be inserted. Updates ignore this.
    var isSelectedForAdd: Bool = true

    var isNew: Bool {
        if case .new = match { return true }
        return false
    }

    init(from parsed: ParsedInventoryItem) {
        id           = parsed.id
        name         = parsed.name
        quantity     = parsed.quantity
        unitSymbol   = parsed.unitSymbol
        category     = parsed.category
        confidence   = parsed.confidence
        fillPercent  = parsed.fillPercent
        remainingVolume = parsed.remainingVolume
        unitCost     = parsed.unitCost
        sellingPrice = parsed.sellingPrice
        expiryDate   = parsed.expiryDate
        sku          = parsed.sku
        barcode      = parsed.barcode
        minQuantity  = parsed.minQuantity
        aiNotes      = parsed.notes
        if let vol = parsed.remainingVolume?.lowercased() {
            if vol.contains("ml") || vol.contains("மில") { unitSymbol = "mL" }
            else if vol.contains("l") || vol.contains("லி") { unitSymbol = "L" }
        }
    }

    var capturedExtraFieldNames: [String] {
        var fields: [String] = []
        if unitCost != nil { fields.append("unit_cost") }
        if sellingPrice != nil { fields.append("selling_price") }
        if expiryDate != nil { fields.append("expiry_date") }
        if let sku, !sku.isEmpty { fields.append("sku") }
        if let barcode, !barcode.isEmpty { fields.append("barcode") }
        if minQuantity != nil { fields.append("min_quantity") }
        if let aiNotes, !aiNotes.isEmpty { fields.append("notes") }
        return fields
    }

    var capturedExtrasSummary: String? {
        var parts: [String] = []
        if let unitCost { parts.append(String(format: L("Cost: %@", "Cost: %@"), unitCost.smartFormatted)) }
        if let sellingPrice { parts.append(String(format: L("Sell: %@", "Sell: %@"), sellingPrice.smartFormatted)) }
        if let expiryDate {
            parts.append(String(format: L("Exp: %@", "Exp: %@"), AppLocaleFormatting.abbreviatedDate(expiryDate)))
        }
        if let sku, !sku.isEmpty { parts.append("SKU: \(sku)") }
        if let barcode, !barcode.isEmpty { parts.append("Barcode: \(barcode)") }
        if let minQuantity { parts.append(String(format: L("Min: %@", "Min: %@"), minQuantity.smartFormatted)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension InventoryItem {
    func applyCapturedFields(from editable: EditableItem) {
        if let unitCost = editable.unitCost { self.unitCost = unitCost }
        if let sellingPrice = editable.sellingPrice { self.sellingPrice = sellingPrice }
        if let expiryDate = editable.expiryDate { self.expiryDate = expiryDate }
        if let sku = editable.sku, !sku.isEmpty { self.sku = sku }
        if let barcode = editable.barcode, !barcode.isEmpty { self.barcode = barcode }
        if let minQuantity = editable.minQuantity { self.minQuantity = minQuantity }
        if let notes = editable.aiNotes, !notes.isEmpty {
            if itemDescription.isEmpty {
                itemDescription = notes
            } else if !itemDescription.contains(notes) {
                itemDescription += "\n\(notes)"
            }
        }
        updatedAt = Date()
    }

    func applyCapturedFields(from parsed: ParsedInventoryItem) {
        applyCapturedFields(from: EditableItem(from: parsed))
    }
}

extension Array where Element == EditableItem {
    mutating func applyNameMatching(in storage: Storage?) {
        guard let storage else { return }
        for index in indices {
            if let barcode = self[index].barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !barcode.isEmpty,
               let found = storage.items.first(where: { $0.barcode == barcode }) {
                self[index].match = .existing(found)
                continue
            }
            if let sku = self[index].sku?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sku.isEmpty,
               let found = storage.items.first(where: {
                   $0.sku.lowercased() == sku.lowercased()
               }) {
                self[index].match = .existing(found)
                continue
            }

            let query = self[index].name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                self[index].match = .new
                continue
            }

            if let exact = storage.items.first(where: { $0.name.lowercased() == query }) {
                self[index].match = .existing(exact)
                continue
            }

            guard query.count >= 3 else {
                self[index].match = .new
                continue
            }
            let candidates = storage.items.filter {
                $0.name.lowercased().contains(query) || query.contains($0.name.lowercased())
            }
            if candidates.count == 1, let found = candidates.first {
                self[index].match = .existing(found)
            } else {
                self[index].match = .new
            }
        }
    }

    @MainActor
    mutating func applyDefaultCapSelection(remainingSlots: Int, isPro: Bool) {
        ItemCapReview.applyDefaultSelection(&self, remainingSlots: remainingSlots, isPro: isPro)
    }
}

// MARK: - EditableItemRow

struct EditableItemRow: View {
    @Binding var item: EditableItem
    var selectedStorage: Storage?
    var isPro: Bool = false
    var remainingSlots: Int = Int.max

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if !isPro, item.isNew {
                    capSelectionToggle
                }

                SmartConfidenceChip(confidence: item.confidence)

                TextField("Item name", text: $item.name)
                    .font(.subheadline).fontWeight(.medium)
            }
            .opacity(!isPro && item.isNew && remainingSlots == 0 ? 0.45 : 1)

            ItemMatchReviewControls(
                match: $item.match,
                parsedName: item.name,
                selectedStorage: selectedStorage
            )

            HStack(spacing: 12) {
                HStack {
                    Text("Qty")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("0", text: Binding(
                        get: { item.quantity?.smartFormatted ?? "" },
                        set: { item.quantity = Double($0.replacingOccurrences(of: ",", with: ".")) }
                    ))
                        .font(.caption)
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                }

                HStack {
                    Text("Unit")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("pcs", text: Binding(
                        get: { item.unitSymbol ?? "" },
                        set: { item.unitSymbol = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.caption)
                    .frame(width: 50)
                }

                Spacer()
            }

            if let fill = item.fillPercent {
                Text("~\(Int(fill))% full\(item.remainingVolume.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if item.remainingVolume != nil || Self.isLiquidUnit(item.unitSymbol ?? "") {
                if item.fillPercent == nil && Self.isLiquidUnit(item.unitSymbol ?? "") {
                    Text("Fill level not visible — enter quantity manually")
                        .font(.caption).foregroundColor(.orange)
                }
            }

            if let summary = item.capturedExtrasSummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var capSelectionToggle: some View {
        Button {
            guard remainingSlots > 0 else { return }
            item.isSelectedForAdd.toggle()
        } label: {
            Image(systemName: item.isSelectedForAdd ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(remainingSlots == 0 ? .secondary : .stoqlyPrimary)
        }
        .buttonStyle(.plain)
        .disabled(remainingSlots == 0)
        .accessibilityLabel(item.isSelectedForAdd
            ? L("itemCap.selected", "Selected to add")
            : L("itemCap.deselected", "Not selected"))
    }

    private static func isLiquidUnit(_ unit: String) -> Bool {
        let u = unit.lowercased()
        if u == "ml" || u.contains("ml") || u.contains("மில") { return true }
        if u == "l" || u.contains("litre") || u.contains("liter") || u.contains("லி") { return true }
        return false
    }
}

// MARK: - Item match review badge + toggle (shared by AI inventory review lists)

struct ItemMatchReviewControls: View {
    @Binding var match: EditableItem.ItemMatch
    let parsedName: String
    let selectedStorage: Storage?

    @State private var showingLinkPicker = false

    var body: some View {
        HStack(spacing: 8) {
            matchBadge
            Spacer()
            matchToggleButton
        }
        .sheet(isPresented: $showingLinkPicker) {
            LinkExistingItemPickerSheet(
                parsedName: parsedName,
                selectedStorage: selectedStorage,
                match: $match
            )
            .sheetStyle()
        }
    }

    @ViewBuilder
    private var matchBadge: some View {
        switch match {
        case .existing(let inv):
            Text("↑ Updates · current: \(inv.currentQuantity.smartFormatted) \(inv.uom?.symbol ?? "pcs")")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.stoqlyPrimary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.stoqlyPrimary.opacity(0.12))
                .cornerRadius(12)
        case .new:
            Text("＋ New item")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.stoqlySuccess)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.stoqlySuccess.opacity(0.12))
                .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var matchToggleButton: some View {
        switch match {
        case .existing:
            Button("Mark as new") {
                match = .new
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        case .new:
            Button("Link to existing") {
                showingLinkPicker = true
            }
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
