import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject var store: BatchStore
    @State private var picks: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clearcut")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            ExampleStrip()
                .padding(.bottom, 28)
            Text("Batch")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Pick your product photos. The backgrounds come off by themselves, then give the whole set one backdrop and shadow.")
                .font(.system(size: 17))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
            PhotosPicker(selection: $picks, maxSelectionCount: 250, selectionBehavior: .ordered, matching: .images) {
                Text("Start new batch")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.ink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 26)
            Spacer().frame(height: 40)
        }
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

/// A quiet illustration: three plain objects sitting on soft backdrops with shadows.
private struct ExampleStrip: View {
    var body: some View {
        HStack(spacing: 10) {
            tile(bg: Color(red: 0.96, green: 0.95, blue: 0.92), item: Theme.ink, w: 34, h: 54, corner: 8)
            tile(bg: Color(red: 0.82, green: 0.87, blue: 0.91), item: Color(red: 0.77, green: 0.33, blue: 0.24), w: 52, h: 52, corner: 26)
            tile(bg: Color(red: 0.91, green: 0.86, blue: 0.77), item: Color(red: 0.18, green: 0.36, blue: 0.31), w: 46, h: 38, corner: 6)
        }
    }

    private func tile(bg: Color, item: Color, w: CGFloat, h: CGFloat, corner: CGFloat) -> some View {
        ZStack {
            bg
            Ellipse()
                .fill(Color.black.opacity(0.28))
                .frame(width: w * 0.95, height: 9)
                .blur(radius: 4)
                .offset(y: h / 2 + 2)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(item)
                .frame(width: w, height: h)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
