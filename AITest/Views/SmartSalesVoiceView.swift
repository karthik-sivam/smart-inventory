import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct SmartSalesVoiceView: View {
    var onCompleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]

    @StateObject private var audio = VoiceRecordingController()
    @State private var step: VoiceStep = .record
    @State private var transcript = ""
    @State private var parsedRows: [ParsedSaleRow] = []
    @State private var isRecording = false
    @State private var errorMessage: String?
    @State private var recordingPermissionDenied = false

    enum VoiceStep { case record, analyzing, review }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .record: recordView
                case .analyzing: analyzingView
                case .review:
                    SaleEntryReviewView(
                        rows: $parsedRows,
                        onConfirm: { onCompleted?() ?? dismiss() },
                        onCancel: { step = .record }
                    )
                    .environmentObject(currencyManager)
                }
            }
            .navigationTitle(step == .review ? "Review Sales" : "Voice Sales Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .review {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear { requestRecordingPermissions() }
    }

    private var recordView: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundColor(.stoqlyAccent)
                    Text("Say each item with quantity and price, e.g. \"5 chips at 10, 2 waters at 20\"")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript").font(.subheadline).fontWeight(.semibold)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(minHeight: 140)
                        if transcript.isEmpty {
                            Text("Your speech will appear here…")
                                .foregroundColor(.secondary).padding(14)
                        } else {
                            Text(transcript).padding(14)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.stoqlyDanger)
                }

                if recordingPermissionDenied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline).foregroundColor(.stoqlyPrimary)
                }

                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.stoqlyDanger : Color.stoqlyPrimary)
                            .frame(width: 80, height: 80)
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title2).foregroundColor(.white)
                    }
                }
                .disabled(recordingPermissionDenied)

                Text(isRecording ? "Tap to stop" : "Tap to record")
                    .font(.caption).foregroundColor(.secondary)

                if !transcript.isEmpty && !isRecording {
                    Text("Tap \"Parse Sales\" to analyse your recording")
                        .font(.caption2).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Parse Sales") { analyzeTranscript() }
                        .buttonStyle(.borderedProminent)
                        .tint(.stoqlyAccent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Parsing your sales…").font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

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
        errorMessage = nil
        audio.stop()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = String(localized: "voice.audioSessionFailed", defaultValue: "Could not start audio session.")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        audio.request = req

        guard let recognizer = audio.recognizer, recognizer.isAvailable else {
            errorMessage = String(localized: "voice.recognizerUnavailable", defaultValue: "Speech recognizer unavailable.")
            audio.stop()
            return
        }

        audio.task = SpeechKit.startTask(on: recognizer, with: req) { result, error in
            let transcriptText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let callbackError = error
            DispatchQueue.main.async {
                if let transcriptText { transcript = transcriptText }
                if isFinal { stopRecording(); return }
                if let callbackError {
                    let nsError = callbackError as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" &&
                        (nsError.code == 216 || nsError.code == 203 || nsError.code == 301) { return }
                    errorMessage = callbackError.localizedDescription
                    stopRecording()
                }
            }
        }

        do {
            try audio.installTap(appendingTo: req)
            try audio.startEngine()
            isRecording = true
        } catch {
            errorMessage = String(localized: "voice.recordingFailed", defaultValue: "Recording failed to start.")
            stopRecording()
        }
    }

    private func stopRecording() {
        guard isRecording || audio.isRunning else { return }
        audio.request?.endAudio()
        isRecording = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            audio.stop()
        }
    }

    private func analyzeTranscript() {
        step = .analyzing
        Task {
            do {
                parsedRows = try await AIInventoryService.shared.parseSalesTranscript(
                    transcript: transcript,
                    knownItemNames: allItems.map(\.name)
                )
                AnalyticsManager.shared.track(.smartSalesModeSelected(mode: "voice"))
                step = .review
            } catch {
                errorMessage = error.localizedDescription
                step = .record
            }
        }
    }
}
