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
    let recognizer  = SFSpeechRecognizer(locale: .current)
    var request:  SFSpeechAudioBufferRecognitionRequest?
    var task:     SFSpeechRecognitionTask?

    private(set) var isRunning = false
    private var tapInstalled = false

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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query private var storages: [Storage]
    @Query private var uoms: [UOM]

    // Audio controller — @StateObject ensures single ownership, main-thread init.
    @StateObject private var audio = VoiceRecordingController()

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
    @State private var recordingPermissionDenied = false
    @State private var didRequestRecordingPermissions = false

    private var isStorageSelected: Bool {
        selectedStorage != nil && !storages.isEmpty
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
        .onAppear {
            if selectedStorage == nil, let preselectedStorage {
                selectedStorage = preselectedStorage
            }
            guard !didRequestRecordingPermissions else { return }
            didRequestRecordingPermissions = true
            requestRecordingPermissions()
        }
    }

    // MARK: - Step 1: Record

    private var recordView: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Usage badge
                if !subscriptionManager.isPro {
                    let remaining = usageManager.remaining(.voice, isPro: false)
                    HStack(spacing: 8) {
                        Image(systemName: "mic.badge.plus")
                            .foregroundColor(.stoqlyPrimary)
                        Text("\(remaining) voice count\(remaining == 1 ? "" : "s") left this month")
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
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                            .fill(Color.stoqlyCard)
                            .frame(minHeight: 140)
                        if transcript.isEmpty {
                            Text("Your speech will appear here…")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(14)
                        } else {
                            Text(transcript)
                                .font(.body)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                            .stroke(isRecording ? Color.stoqlyDanger.opacity(0.5) : Color(.separator), lineWidth: 1)
                    )
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
                    .disabled(recordingPermissionDenied || !isStorageSelected)

                    Text(isRecording ? "Tap to stop" : "Tap to record")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                List {
                    Section {
                        ForEach($editableItems) { $item in
                            EditableItemRow(item: $item, selectedStorage: selectedStorage)
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
                    HStack(spacing: 12) {
                        Button("Re-record") {
                            transcript = ""
                            editableItems = []
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
                        .disabled(!isStorageSelected)
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
        guard !isRecording, !audio.isRunning else { return }
        guard usageManager.canUse(.voice, isPro: subscriptionManager.isPro) else {
            showingPaywall = true
            return
        }

        errorMessage = nil
        audio.stop()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not start audio session."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        audio.request = req

        guard let recognizer = audio.recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer unavailable."
            audio.stop()
            return
        }

        audio.task = SpeechKit.startTask(on: recognizer, with: req) { result, error in
            let transcriptText = result?.bestTranscription.formattedString
            let isFinal        = result?.isFinal ?? false
            DispatchQueue.main.async {
                handleRecognitionUpdate(transcriptText: transcriptText, isFinal: isFinal, error: error)
            }
        }

        do {
            try audio.installTap(appendingTo: req)
            try audio.startEngine()
            isRecording = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Recording failed to start."
            stopRecording()
        }
    }

    private func handleRecognitionUpdate(transcriptText: String?, isFinal: Bool, error: (any Error)?) {
        guard isRecording || audio.isRunning else { return }

        if let transcriptText {
            transcript = transcriptText
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
        guard isRecording || audio.isRunning else { return }
        audio.stop()
        isRecording = false
    }

    // MARK: - Logic: AI Parse

    private func parseTranscript() async {
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard usageManager.canUse(.voice, isPro: subscriptionManager.isPro) else {
            showingPaywall = true
            return
        }

        step = .parsing
        do {
            let items = try await AIInventoryService.shared.parseVoiceTranscript(transcript)
            usageManager.recordUse(.voice)
            editableItems = items.map { EditableItem(from: $0) }
            editableItems.applyNameMatching(in: selectedStorage)
            step = .review
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsManager.shared.track(.smartCountFailed(mode: "voice", reason: error.localizedDescription))
            step = .record
        }
    }

    // MARK: - Logic: Save

    private func saveItems() async {
        guard let storage = selectedStorage else { return }
        step = .saving

        let itemsToSave = editableItems.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }

        for editable in itemsToSave {
            let matchedUOM = uoms.first { $0.symbol.lowercased() == (editable.unitSymbol?.lowercased() ?? "") }

            switch editable.match {
            case .existing(let existing):
                let qty = editable.quantity ?? existing.currentQuantity
                let count = InventoryCount(previousQuantity: existing.currentQuantity, countedQuantity: qty, notes: "Voice inventory")
                existing.countHistory.append(count)
                existing.currentQuantity = qty
                existing.updatedAt = Date()
                let event = ActivityEvent(
                    eventType: "ItemCounted",
                    itemName: existing.name,
                    storageName: storage.name,
                    notes: "Voice inventory",
                    performedBy: "You"
                )
                modelContext.insert(event)
            case .new:
                let item = InventoryItem(
                    name: editable.name,
                    description: "",
                    currentQuantity: editable.quantity ?? 0,
                    category: editable.category ?? "Uncategorised",
                    storage: storage,
                    uom: matchedUOM
                )
                modelContext.insert(item)
                let event = ActivityEvent(
                    eventType: "ItemAdded",
                    itemName: item.name,
                    storageName: storage.name,
                    notes: "Added via voice inventory",
                    performedBy: "You"
                )
                modelContext.insert(event)
            }
        }

        modelContext.safeSave(context: "VoiceInventorySave")

        AnalyticsManager.shared.track(.smartCountCompleted(
            mode: "voice",
            itemCount: itemsToSave.count
        ))

        // Sync to Firestore
        Task {
            for item in storage.items {
                FirestoreManager.shared.syncItem(item)
            }
        }

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
    var match: ItemMatch = .new

    init(from parsed: ParsedInventoryItem) {
        id           = parsed.id
        name         = parsed.name
        quantity     = parsed.quantity
        unitSymbol   = parsed.unitSymbol
        category     = parsed.category
        confidence   = parsed.confidence
    }
}

extension Array where Element == EditableItem {
    mutating func applyNameMatching(in storage: Storage?) {
        guard let storage else { return }
        for index in indices {
            let name = self[index].name.lowercased()
            if let found = storage.items.first(where: { $0.name.lowercased() == name }) {
                self[index].match = .existing(found)
            } else {
                self[index].match = .new
            }
        }
    }
}

// MARK: - EditableItemRow

struct EditableItemRow: View {
    @Binding var item: EditableItem
    var selectedStorage: Storage?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Confidence dot
                Circle()
                    .fill(item.confidence >= 0.8 ? Color.stoqlySuccess : Color.stoqlyWarning)
                    .frame(width: 8, height: 8)

                TextField("Item name", text: $item.name)
                    .font(.subheadline).fontWeight(.medium)
            }

            ItemMatchReviewControls(
                match: $item.match,
                parsedName: item.name,
                selectedStorage: selectedStorage
            )

            HStack(spacing: 12) {
                HStack {
                    Text("Qty")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("0", value: $item.quantity, format: .number)
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

                if item.confidence < 0.75 {
                    Text("Low confidence")
                        .font(.caption2)
                        .foregroundColor(.stoqlyWarning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.stoqlyWarningTint)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
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
