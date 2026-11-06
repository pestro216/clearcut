import SwiftUI
import PhotosUI

enum Panel: String, Identifiable {
    case background, shadow, layout
    var id: String { rawValue }
    var height: CGFloat {
        switch self {
        case .background: return 470
        case .shadow: return 250
        case .layout: return 400
        }
    }
}

struct BatchView: View {
    @EnvironmentObject var store: BatchStore
    @State private var panel: Panel?
    @State private var editing: EditTarget?
    @State private var confirmClose = false
    @State private var morePicks: [PhotosPickerItem] = []

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(store.items) { item in
                        Tile(item: item)
                            .onTapGesture { if !store.busy { editing = EditTarget(id: item.id) } }
                    }
                    if let p = store.importing {
                        ProgressTile(done: p.done, total: p.total)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            bottomBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(item: $panel) { p in
            PanelSheet(panel: p)
                .presentationDetents([.height(p.height)])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(p.height)))
                .presentationCornerRadius(18)
        }
        .fullScreenCover(item: $editing) { target in
            ItemEditor(id: target.id)
        }
        .sheet(item: $store.exportResult) { result in
            ExportDoneView(result: result)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Close this batch?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Close batch", role: .destructive) { store.clear() }
        } message: {
            Text("Anything you haven't exported will be lost.")
        }
        .onChange(of: morePicks) { _, new in
            guard !new.isEmpty else { return }
            store.add(new)
            morePicks = []
        }
    }

    private var header: some View {
        HStack {
            Button { confirmClose = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Close batch")
            Spacer()
            Text(store.items.count == 1 ? "1 photo" : "\(store.items.count) photos")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            PhotosPicker(selection: $morePicks, maxSelectionCount: 250, selectionBehavior: .ordered, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Add photos")
            .disabled(store.exportProgress != nil)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button { store.exportAll() } label: {
                Group {
                    if let p = store.exportProgress {
                        Text("Saving \(p.done) of \(p.total)")
                    } else {
                        Text(store.items.count == 1 ? "Export 1 image" : "Export \(store.items.count) images")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.ink)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(store.busy || store.items.isEmpty)
            .opacity(store.importing != nil ? 0.5 : 1)

            HStack(spacing: 0) {
                toolButton("Background", "square.on.square", .background)
                toolButton("Shadow", "shadow", .shadow)
                toolButton("Layout", "aspectratio", .layout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Theme.paper.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) })
    }

    private func toolButton(_ title: String, _ symbol: String, _ p: Panel) -> some View {
        Button { panel = p } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.ink)
        }
        .disabled(store.exportProgress != nil)
    }
}

struct Tile: View {
    @EnvironmentObject var store: BatchStore
    let item: BatchItem

    var body: some View {
        Color.white
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if item.removed {
                        if store.look.backdrop == .transparent { Checker() }
                        if let p = store.previews[item.id] {
                            Image(uiImage: p).resizable().scaledToFit()
                        } else {
                            ProgressView()
                        }
                    } else if let o = item.smallOriginal {
                        Image(uiImage: UIImage(cgImage: o)).resizable().scaledToFit()
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if item.status == .noSubject {
                    Text("No item found")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white)
                        .clipShape(Capsule())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct ProgressTile: View {
    let done: Int
    let total: Int
    var body: some View {
        Color.white.opacity(0.6)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Cutting out \(min(done + 1, total)) of \(total)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct Checker: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 10
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.9)))
                    x += 2 * s
                }
                y += s
                row += 1
            }
        }
    }
}

struct ExportDoneView: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let result: BatchStore.ExportResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result.saved == 1 ? "1 image saved" : "\(result.saved) images saved")
                .font(.system(size: 22, weight: .bold))
            Text(result.failed > 0
                 ? "Saved to your camera roll. \(result.failed) couldn't be saved."
                 : "Saved to your camera roll.")
                .foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(result.thumbs.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            Spacer()
            Button {
                store.clear()
            } label: {
                Text("Close batch")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.ink).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { dismiss() } label: {
                Text("Keep editing")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
    }
}
