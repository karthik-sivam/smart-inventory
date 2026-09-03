import SwiftUI

/// Blocking wall shown when the running build is below the configured minimum.
///
/// Deliberately has no dismiss affordance — that is the point of a forced
/// update. It is only ever reachable when `AppUpdateManager` has positively
/// confirmed the build is too old; every failure path leaves it hidden.
struct ForceUpdateView: View {
    let requirement: AppUpdateManager.UpdateRequirement
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(L("forceUpdate.title", "Update required"))
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(requirement.message
                         ?? L("forceUpdate.message",
                              "This version of Stoqly is no longer supported. Update to the latest version to keep using the app."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    openURL(requirement.storeURL)
                } label: {
                    Text(L("forceUpdate.button", "Update now"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("forceUpdateButton")

                Text(String(format: L("forceUpdate.versionNote", "Your version: %@"),
                            AppUpdateManager.shared.currentVersion))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled(true)
    }
}

#Preview {
    ForceUpdateView(requirement: .init(
        minimumVersion: "1.6",
        message: nil,
        storeURL: URL(string: "itms-apps://apps.apple.com/app/id6763451242")!
    ))
}
