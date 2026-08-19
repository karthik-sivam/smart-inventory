import SwiftUI
import SwiftData

/// Shared free-tier item-cap selection for Voice / Photo / Paper / Bulk review (S45).
@MainActor
enum ItemCapReview {
    static func remainingSlots(storage: Storage?, context: ModelContext, isPro: Bool) -> Int {
        if isPro { return Int.max }
        return SubscriptionManager.shared.remainingFreeItemSlots(storage: storage, context: context)
    }

    static func applyDefaultSelection(_ items: inout [EditableItem], remainingSlots: Int, isPro: Bool) {
        var used = 0
        for index in items.indices {
            switch items[index].match {
            case .existing:
                items[index].isSelectedForAdd = true
            case .new:
                if isPro || used < remainingSlots {
                    items[index].isSelectedForAdd = true
                    used += 1
                } else {
                    items[index].isSelectedForAdd = false
                }
            }
        }
    }

    static func newCount(_ items: [EditableItem]) -> Int {
        items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.isNew
        }.count
    }

    static func selectedNewCount(_ items: [EditableItem]) -> Int {
        items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.isNew && $0.isSelectedForAdd
        }.count
    }

    static func updateCount(_ items: [EditableItem]) -> Int {
        items.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.isNew
        }.count
    }

    static func canSave(items: [EditableItem], remainingSlots: Int, isPro: Bool) -> Bool {
        if isPro { return true }
        let selectedNew = selectedNewCount(items)
        guard selectedNew <= remainingSlots else { return false }
        return updateCount(items) > 0 || selectedNew > 0
    }

    static func shouldShowBanner(newCount: Int, remainingSlots: Int, isPro: Bool) -> Bool {
        !isPro && newCount > remainingSlots
    }
}

struct ItemCapOverflowBanner: View {
    let remainingSlots: Int
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bannerText)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUpgrade) {
                Text(L("itemCap.upgrade", "Upgrade to Pro"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.stoqlyPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.stoqlyWarningTint)
        .cornerRadius(AppTheme.radiusMd)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var bannerText: String {
        if remainingSlots == 0 {
            return L(
                "itemCap.banner.atLimit",
                "You're at the 50-item limit for this storage. Upgrade to Pro to add new items."
            )
        }
        return String(
            format: L(
                "itemCap.banner.overflow",
                "Free plan: 50 items per storage. You can add %1$d more here. Deselect items, or upgrade to Pro to add them all."
            ),
            remainingSlots
        )
    }
}

struct ItemCapSelectionCounter: View {
    let selectedNew: Int
    let remainingSlots: Int

    var body: some View {
        Text(
            String(
                format: L("itemCap.counter", "%1$d/%2$d new items selected"),
                selectedNew,
                remainingSlots
            )
        )
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(selectedNew > remainingSlots ? .stoqlyDanger : .secondary)
    }
}
