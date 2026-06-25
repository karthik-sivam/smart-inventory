import SwiftUI
import SwiftData

/// Shown once after a user signs in for the first time and has no storages.
/// Walks them through creating a first Storage so the rest of the app has
/// somewhere to put items.
struct PostLoginOnboardingView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var storages: [Storage]

    @State private var step = 0
    @State private var storageName = ""
    @State private var selectedColor = "3B82F6"
    @State private var isSaving = false

    private let colorOptions = [
        "3B82F6", "10B981", "F59E0B", "EF4444",
        "8B5CF6", "EC4899", "06B6D4", "84CC16"
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.blue : Color(.systemGray4))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: step)
                    }
                }
                .padding(.top, 24)

                Spacer()

                // Step content
                Group {
                    if step == 0 { welcomeStep }
                    else if step == 1 { createStorageStep }
                    else { readyStep }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.35), value: step)

                Spacer()

                // Primary action button
                Button(action: handlePrimaryAction) {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(primaryButtonLabel)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(step == 1 && storageName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                .accessibilityIdentifier(primaryButtonAccessibilityID)

                // Skip
                if step < 2 {
                    Button("Skip for now") {
                        withAnimation { isPresented = false }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("Welcome to Stoqly")
                .font(.title).fontWeight(.bold)
            Text("The easiest way to track what you have,\nwhere it is, and when you're running low.")
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var createStorageStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("Where do you store things?")
                    .font(.title2).fontWeight(.bold)
                Text("A storage is any physical location — a warehouse,\na fridge, a shelf, a storeroom.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            VStack(alignment: .leading, spacing: 12) {
                TextField("Storage name (e.g. Main Warehouse)", text: $storageName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)
                    .accessibilityIdentifier("postLoginStorageNameField")

                // Colour picker
                HStack(spacing: 12) {
                    ForEach(colorOptions, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: selectedColor == hex ? 3 : 0)
                            )
                            .shadow(radius: selectedColor == hex ? 3 : 0)
                            .onTapGesture { selectedColor = hex }
                    }
                }
                .padding(.horizontal, 32)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're all set!")
                .font(.title).fontWeight(.bold)
            let name = storages.last?.name ?? "your storage"
            Text("Tap + to add your first item to \(name),\nor explore the app at your own pace.")
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    private var primaryButtonLabel: String {
        switch step {
        case 0: return "Get Started"
        case 1: return "Create Storage"
        default: return "Go to Dashboard"
        }
    }

    private var primaryButtonAccessibilityID: String {
        switch step {
        case 0: return "postLoginGetStarted"
        case 1: return "postLoginCreateStorage"
        default: return "postLoginLetsGo"
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case 0:
            withAnimation { step = 1 }
        case 1:
            createStorage()
        default:
            isPresented = false
        }
    }

    private func createStorage() {
        let name = storageName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        let storage = Storage(name: name, location: "", description: "", color: selectedColor)
        modelContext.insert(storage)
        modelContext.safeSave(context: "PostLoginOnboarding createStorage")
        FirestoreManager.shared.syncStorage(storage)
        isSaving = false
        withAnimation { step = 2 }
    }
}
