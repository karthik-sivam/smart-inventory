import SwiftUI

// MARK: - PendingPaymentBanner (D1e)
//
// Inline, non-blocking notice shown on the paywall while StoreKit reports a
// purchase as `.pending` (bank 2FA, Ask-to-Buy). It never blocks the screen and
// offers no payment action — the purchase resolves on its own through
// `Transaction.updates`, which auto-dismisses this banner.

struct PendingPaymentBanner: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(L("pack_D1e_pending_title", "Payment processing"))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color(.label))
                Text(L("pack_D1e_pending_body",
                       "Waiting for your bank to confirm the payment. We'll update once it's done — you can keep using Stoqly."))
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(.secondaryLabel))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(L("pack_D1e_pending_dismiss", "Dismiss"))
            .accessibilityIdentifier("pendingPaymentBannerClose")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pendingPaymentBanner")
    }
}

#Preview {
    PendingPaymentBanner(onClose: {})
}
