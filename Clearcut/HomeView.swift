import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject var store: BatchStore
    @State private var picks: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clearcut")
                .font(.system(size: 20, weight: .bold))
            Spacer()
            Text("Product photos, finished in one go.")
                .font(.system(size: 30, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose a set of photos. Backgrounds come off by themselves, then one surface and shadow is applied to every photo.")
                .font(.system(size: 17))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
            PhotosPicker(selection: $picks, maxSelectionCount: 250, selectionBehavior: .ordered, matching: .images) {
                Text("Start new batch")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.ink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 28)
            Spacer().frame(height: 48)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            store.add(new)
            picks = []
        }
    }
}
