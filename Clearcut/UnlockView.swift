import SwiftUI

/// The unlock screen: the price before buying, the purchase, and Restore Purchases.
/// `waiting` is how many finished cutouts are waiting to be saved (0 when opened from About).
struct UnlockView: View {
    @ObservedObject private var unlock = Unlock.shared
    @Environment(\.dismiss) private var dismiss
    var waiting = 0
    /// Called once the app is unlocked, for example to save the waiting photos.
    var onUnlocked: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unlock \(AppName.display)")
                .font(.system(size: 22, weight: .bold))
            Text(intro)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                point("Save as many photos as you like")
                point("One payment, no subscription")
                point("Yours on every device signed in to your Apple Account")
            }
            .padding(.vertical, 4)
            if let problem = unlock.problem {
                Text(problem).font(.system(size: 14)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { Task { await unlock.purchase(); finishIfUnlocked() } } label: {
                Group {
                    if unlock.busy { ProgressView().tint(.white) }
                    else if let p = unlock.product { Text("Unlock for \(p.displayPrice)") }
                    else { Text("Unlock") }
                }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Theme.ink).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(unlock.busy)
            HStack {
                Button("Restore Purchases") { Task { await unlock.restore(); finishIfUnlocked() } }
                Spacer()
                Button("Not now") { dismiss() }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.ink)
            .disabled(unlock.busy)
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .task { unlock.problem = nil; await unlock.loadProduct() }
    }

    private var intro: String {
        let free = "Your first \(Unlock.freeSaves) saved photos are free."
        switch waiting {
        case 0: return free + " After that, one payment unlocks the app for good."
        case 1: return free + " Unlock to save the 1 photo still waiting."
        default: return free + " Unlock to save the \(waiting) photos still waiting."
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 15))
        }
    }

    private func finishIfUnlocked() {
        guard unlock.unlocked else { return }
        dismiss()
        onUnlocked()
    }
}

/// One line for the About screen: what's unlocked, with Unlock and Restore Purchases.
struct UnlockSection: View {
    @ObservedObject private var unlock = Unlock.shared
    @State private var showUnlock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Purchase").font(.system(size: 17, weight: .semibold))
            if unlock.unlocked {
                Text("Unlocked. Thank you.").font(.system(size: 15)).foregroundStyle(Theme.muted)
            } else {
                Text(unlock.freeLeft == 1 ? "1 free save left." : "\(unlock.freeLeft) free saves left.")
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                HStack(spacing: 18) {
                    Button("Unlock") { showUnlock = true }
                    Button("Restore Purchases") { Task { await unlock.restore() } }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .disabled(unlock.busy)
                if let problem = unlock.problem, !showUnlock {
                    Text(problem).font(.system(size: 14)).foregroundStyle(Theme.warning)
                }
            }
        }
        .sheet(isPresented: $showUnlock) { UnlockView().presentationDetents([.medium, .large]) }
    }
}
