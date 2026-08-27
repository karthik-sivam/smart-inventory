import SwiftUI
import PhotosUI
import UIKit

/// Displays either a PhotosPicker (Pro) or an inline Pro upgrade banner (Free).
/// selectedPhotoData: binding to the picked compressed image bytes to upload.
/// existingPhotoURL: already-uploaded URL to show as thumbnail (nil on new item).
struct ItemPhotoSection: View {
    @Binding var selectedPhotoData: Data?
    let existingPhotoURL: String?
    var showsSectionContainer: Bool = true
    var onPickerTapped: (() -> Void)? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var thumbnailImage: Image? = nil
    @State private var showingPaywall = false
    @State private var showProHint = false
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        Group {
            if showsSectionContainer {
                Section(header: Text("Photo")) {
                    photoContent
                }
            } else {
                photoContent
            }
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if subscriptionManager.isPro {
            proPhotoRow
        } else {
            // Presentation MUST NOT sit on `Section` / outer `Group`. A Form
            // Section with two children (lock row + hint) applies the modifier
            // to both, so two sheets present at once and iOS dismisses immediately.
            // Attach to the always-present lock row — a single identity.
            //
            // Must be `.fullScreenCover`, not `.sheet`. ItemPhotoSection
            // lives inside EditItemView / AddItemView, already sheets
            // (ItemDetailView → Edit, StorageDetailView → Add) with
            // `.sheetStyle()` detents. A nested sheet + SubscriptionManager
            // publish from PaywallView.loadProducts() re-identifies the
            // parent sheet and auto-dismisses. Same precedent as the
            // barcode scanner. Do not apply `.sheetStyle()` — detents
            // are sheet-only.
            freePhotoRow
                .fullScreenCover(isPresented: $showingPaywall) {
                    PaywallView(source: "item_photo", trigger: "item_photo")
                }
            if showProHint {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a photo so your team can identify stock at a glance. Item photos are a Pro feature.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        AnalyticsManager.shared.track(.upgradeCtaTapped(source: "item_photo"))
                        showingPaywall = true
                    } label: {
                        Text("Upgrade to Pro")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("itemPhotoUpgradeButton")
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var proPhotoRow: some View {
        let currentHasPhoto = hasPhoto
        let currentThumbnailImage = thumbnailImage

        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 12) {
                Group {
                    if let img = currentThumbnailImage {
                        img
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5))
                            Image(systemName: "photo").foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentHasPhoto ? "Change Photo" : "Add Photo")
                        .foregroundColor(.primary)
                    Text("JPEG, max 5 MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if currentHasPhoto {
                    Button(role: .destructive) {
                        selectedPhotoData = nil
                        thumbnailImage = nil
                        pickerItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        // simultaneousGesture (not .gesture / onTapGesture) so PhotosPicker
        // still receives the tap that presents the system picker.
        .simultaneousGesture(
            TapGesture().onEnded { onPickerTapped?() }
        )
        .onChange(of: pickerItem) { _, newItem in
            Task {
                guard let newItem else { return }
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    selectedPhotoData = compressIfNeeded(data)
                    if let uiImage = UIImage(data: selectedPhotoData ?? data) {
                        thumbnailImage = Image(uiImage: uiImage)
                    }
                }
            }
        }
        .onAppear { loadExistingThumbnail() }
    }

    @ViewBuilder
    private var freePhotoRow: some View {
        Button(action: {
            AnalyticsManager.shared.track(.proLockTapped(feature: "item_photo"))
            withAnimation(.easeInOut(duration: 0.2)) { showProHint.toggle() }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 56, height: 56)
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Item Photo")
                        .foregroundColor(.primary)
                    Text("Helps your team identify stock instantly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Text("Pro")
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(LinearGradient(colors: [.blue, .purple],
                                           startPoint: .leading, endPoint: .trailing))
                .cornerRadius(8)
            }
        }
        .buttonStyle(.plain)
    }

    private var hasPhoto: Bool {
        selectedPhotoData != nil || existingPhotoURL != nil
    }

    private func loadExistingThumbnail() {
        guard thumbnailImage == nil, let urlString = existingPhotoURL,
              let url = URL(string: urlString) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let uiImage = UIImage(data: data) {
                thumbnailImage = Image(uiImage: uiImage)
            }
        }
    }

    private func compressIfNeeded(_ data: Data) -> Data {
        guard let uiImage = UIImage(data: data) else { return data }
        let maxDimension: CGFloat = 800
        let size = uiImage.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.7) ?? data
    }
}
