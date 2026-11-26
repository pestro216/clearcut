import SwiftUI
import PhotosUI

struct BatchView: View {
    @EnvironmentObject var store: BatchStore
    @State private var tool: Tool?
    @State private var editing: EditTarget?
    @State private var confirmClose = false
    @State private var morePicks: [PhotosPickerItem] = []
    @State private var onlyAttention = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var shown: [BatchItem] {
        onlyAttention ? store.items.filter { $0.needsAttention } : store.items
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.attentionCount > 0 {
                Button { onlyAttention.toggle() } label: {
                    Text(onlyAttention ? "Show all photos"
                         : store.attentionCount == 1 ? "1 photo needs a look" : "\(store.attentionCount) photos need a look")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(onlyAttention ? Theme.ink : Theme.warning)
                        .padding(.vertical, 6)
                }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shown) { item in
                        Tile(item: item)
                            .onTapGesture { if item.status != .processing { editing = EditTarget(id: item.id) } }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            bottomBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .fullScreenCover(item: $tool) { t in ToolScreen(tool: t, startID: nil) }
        .fullScreenCover(item: $editing) { target in ItemEditor(id: target.id) }
        .sheet(item: $store.exportResult) { result in
            ExportDoneView(result: result).presentationDetents([.medium])
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
        .onChange(of: store.attentionCount) { _, n in if n == 0 { onlyAttention = false } }
    }

    private var header: some View {
        HStack {
            Button { confirmClose = true } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Close batch")
            Spacer()
            VStack(spacing: 1) {
                Text(store.items.count == 1 ? "1 photo" : "\(store.items.count) photos")
                    .font(.system(size: 17, weight: .semibold))
                if let p = store.importing {
                    Text("Cutting out \(min(p.done + 1, p.total)) of \(p.total)")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            PhotosPicker(selection: $morePicks, maxSelectionCount: max(1, store.room), selectionBehavior: .ordered, matching: .images) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Add photos")
            .disabled(store.exportProgress != nil || store.room == 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button { store.exportAll() } label: {
                Group {
                    if let p = store.exportProgress {
                        Text("Saving \(p.done) of \(p.total)")
                    } else {
                        let n = store.exportable.count
                        Text(n == 0 ? "Nothing to export" : n == 1 ? "Export 1 photo" : "Export \(n) photos")
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.ink)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(store.busy || store.exportable.isEmpty)
            .opacity(store.importing != nil ? 0.45 : 1)

            HStack(spacing: 0) {
                toolButton("Background", "square.on.square", .background)
                toolButton("Shadow", "shadow", .shadow)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.paper.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) })
    }

    private func toolButton(_ title: String, _ symbol: String, _ t: Tool) -> some View {
        Button { tool = t } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.ink)
        }
        .disabled(store.exportProgress != nil || store.items.isEmpty)
    }
}

struct Tile: View {
    @EnvironmentObject var store: BatchStore
    let item: BatchItem

    var body: some View {
        Theme.tile
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = store.grid[item.id] {
                    Image(uiImage: img).resizable().scaledToFit()
                        .background { if item.removed && store.transparent { Checker() } }
                } else {
                    ProgressView()
                }
            }
            .overlay(alignment: .topTrailing) {
                // The quick cutout is showing; the full one is still being made.
                if item.status == .processing && store.grid[item.id] != nil {
                    ProgressView().controlSize(.small).padding(6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                switch item.status {
                case .check:
                    badge("Check")
                case .failed:
                    badge("Not cut out")
                default:
                    if !item.removed && item.canRemove { badge("Original") }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(text == "Original" ? Theme.ink : Theme.warning)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white)
            .clipShape(Capsule())
            .padding(6)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(result.saved == 1 ? "1 photo saved" : "\(result.saved) photos saved")
                .font(.system(size: 22, weight: .bold))
            Text((result.failures.isEmpty ? "Saved to your camera roll at full resolution."
                  : "Saved to your camera roll. \(result.failures.count) couldn't be saved:")
                 + (result.skipped > 0 ? " \(result.skipped) kept as originals weren't saved again; they're already in your library." : ""))
                .foregroundStyle(Theme.muted)
            if !result.failures.isEmpty {
                ForEach(result.failures, id: \.self) { Text($0).font(.system(size: 14)).foregroundStyle(Theme.warning) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(result.thumbs.enumerated()), id: \.offset) { _, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            Spacer()
            Button { store.clear() } label: {
                Text("Close batch")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.ink).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { dismiss() } label: {
                Text("Keep editing").font(.system(size: 17, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
        .padding(24)
        .background(Theme.paper.ignoresSafeArea())
    }
}
