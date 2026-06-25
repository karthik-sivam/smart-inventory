import SwiftUI
import PhotosUI
import UIKit

/// Displays either a PhotosPicker (Pro) or an inline Pro upgrade banner (Free).
/// selectedPhotoData: binding to the picked compressed image bytes to upload.
/// existingPhotoURL: already-uploaded URL to show as thumbnail (nil on new item).
struct ItemPhotoSection: View {
    @Binding var selectedPhotoData: Data?
    let existingPhotoURL: String?
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var thumbnailImage: Image? = nil
    @State private var showingPaywall = false
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        Section(header: Text("Photo")) {
            if subscriptionManager.isPro {
                proPhotoRow
            } else {
                freePhotoRow
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
        Button(action: { showingPaywall = true }) {
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
        .sheet(isPresented: $showingPaywall) { PaywallView(source: "pro_feature").sheetStyle() }
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
