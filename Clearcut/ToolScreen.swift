import SwiftUI
import PhotosUI

enum Tool: String, Identifiable {
    case background, shadow
    var id: String { rawValue }
    var title: String { self == .background ? "Background" : "Shadow" }
}

/// Full-screen tool: a large live preview you can swipe through, the tool's controls underneath,
/// Cancel to undo everything changed here, Done to go back.
struct ToolScreen: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let tool: Tool
    let startID: UUID?

    @State private var page: UUID?
    @State private var entryLook: Look?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    if let entryLook { store.look = entryLook }
                    dismiss()
                }
                Spacer()
                Text(tool.title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.font(.system(size: 17, weight: .semibold))
            }
            .font(.system(size: 17))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            PreviewPager(page: $page).frame(maxHeight: .infinity)

            Group {
                switch tool {
                case .background: BackgroundControls()
                case .shadow: ShadowControls()
                }
            }
            .padding(.top, 10)
        }
        .background(Theme.paper.ignoresSafeArea())
        .onDisappear { store.suspendGrid(false) }
        .onAppear {
            store.suspendGrid(true)
            entryLook = store.look
            page = startID ?? store.items.first(where: { $0.removed && $0.canRemove })?.id ?? store.items.first?.id
        }
    }
}

/// Swipeable large previews of the batch.
struct PreviewPager: View {
    @EnvironmentObject var store: BatchStore
    @Binding var page: UUID?

    var body: some View {
        VStack(spacing: 6) {
            TabView(selection: $page) {
                ForEach(store.items) { item in
                    LargePreview(id: item.id).padding(.horizontal, 16).tag(Optional(item.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if store.items.count > 1, let page, let i = store.items.firstIndex(where: { $0.id == page }) {
                Text("\(i + 1) of \(store.items.count)").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// One photo rendered at 1100 px with the current look, re-rendered whenever the look changes.
struct LargePreview: View {
    @EnvironmentObject var store: BatchStore
    let id: UUID
    @State private var image: UIImage?

    private var item: BatchItem? { store.items.first { $0.id == id } }

    var body: some View {
        GeometryReader { geo in
            let size = item?.pixelSize ?? CGSize(width: 4, height: 3)
            let aspect = size.width / max(size.height, 1)
            let w = min(geo.size.width, geo.size.height * aspect)
            ZStack {
                if item?.removed == true, store.transparent { Checker() }
                if let image {
                    Image(uiImage: image).resizable()
                } else if let g = store.grid[id] {
                    Image(uiImage: g).resizable().opacity(0.6)
                    ProgressView()
                }
            }
            .frame(width: w, height: w / aspect)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .task(id: "\(store.lookVersion)-\(id)") {
            try? await Task.sleep(nanoseconds: 60_000_000)
            if Task.isCancelled { return }
            if let img = await store.renderPreview(id), !Task.isCancelled { image = img }
        }
    }
}

// MARK: Background

struct BackgroundControls: View {
    @EnvironmentObject var store: BatchStore
    @EnvironmentObject var library: BackgroundLibrary
    @State private var group = "Wood"
    @State private var custom: Color = .white
    @State private var addPick: PhotosPickerItem?
    @State private var adding = false

    private var groups: [String] { library.groups().map(\.0) + ["Colour"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups, id: \.self) { g in
                        Button { group = g } label: {
                            Text(g)
                                .font(.system(size: 15, weight: group == g ? .semibold : .regular))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(group == g ? Theme.ink : Color.white)
                                .foregroundStyle(group == g ? Color.white : Theme.ink)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.line, lineWidth: group == g ? 0 : 1))
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Group {
                if group == "Colour" { colourRow } else { surfaceRow(library.surfaces.filter { $0.group == group }, yours: group == "Yours") }
            }
            .frame(height: 122, alignment: .top)

            Button { store.setAllRemoved(!store.anyRemoved) } label: {
                Text(store.anyRemoved ? "Show original backgrounds" : "Remove backgrounds")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(.bottom, 6)
        }
        .onAppear {
            switch store.look.backdrop {
            case .surface(let id): group = library.surface(id)?.group ?? "Wood"
            case .colour(let c): group = "Colour"; custom = c.color
            case .transparent: group = "Colour"
            }
        }
        .onChange(of: custom) { _, c in
            let rgb = RGB(color: c)
            if store.look.backdrop != .colour(rgb) { store.look.backdrop = .colour(rgb) }
        }
        .onChange(of: addPick) { _, p in
            guard let p else { return }
            adding = true
            Task {
                if let id = await library.add(p) { store.look.backdrop = .surface(id) }
                adding = false
                addPick = nil
            }
        }
    }

    private func surfaceRow(_ list: [Surface], yours: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                if yours {
                    PhotosPicker(selection: $addPick, matching: .images) {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.line, lineWidth: 1.5)
                                if adding { ProgressView() } else { Image(systemName: "plus").font(.system(size: 22)) }
                            }
                            .frame(width: 84, height: 84)
                            Text("Add").font(.system(size: 13))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                ForEach(list) { s in
                    Button { store.look.backdrop = .surface(s.id) } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let u = s.thumbURL, let img = UIImage(contentsOfFile: u.path) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else { Theme.tile }
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(store.look.backdrop == .surface(s.id) ? Theme.ink : Color.clear, lineWidth: 3))
                            Text(s.title).font(.system(size: 13)).foregroundStyle(Theme.ink).lineLimit(1).frame(width: 88)
                            if s.pixels > 0 && s.pixels < 3000 {
                                Text("Low resolution").font(.system(size: 11)).foregroundStyle(Theme.warning)
                            }
                        }
                    }
                    .contextMenu {
                        if s.custom {
                            Button("Delete background", role: .destructive) {
                                if store.look.backdrop == .surface(s.id) { store.look.backdrop = Look().backdrop }
                                library.remove(s)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 3)
        }
    }

    private var colourRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { store.look.backdrop = .transparent } label: {
                        Checker().frame(width: 44, height: 44).clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.15)))
                            .overlay(ring(store.look.backdrop == .transparent))
                    }
                    .accessibilityLabel("Transparent")
                    ForEach(RGB.swatches, id: \.self) { c in
                        Button { store.look.backdrop = .colour(c) } label: {
                            Circle().fill(c.color).frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.black.opacity(0.15)))
                                .overlay(ring(store.look.backdrop == .colour(c)))
                        }
                    }
                    ColorPicker("Custom colour", selection: $custom, supportsOpacity: false).labelsHidden().frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20).padding(.vertical, 5)
            }
            Toggle("Soft studio light", isOn: $store.look.studioLight)
                .font(.system(size: 16)).padding(.horizontal, 20)
                .disabled(!isColour).opacity(isColour ? 1 : 0.4)
        }
    }

    private var isColour: Bool { if case .colour = store.look.backdrop { return true }; return false }
    private func ring(_ on: Bool) -> some View { Circle().stroke(on ? Theme.ink : Color.clear, lineWidth: 2.5).padding(-4) }
}

// MARK: Shadow

struct ShadowControls: View {
    @EnvironmentObject var store: BatchStore
    /// Slider positions follow the finger at once; the look (and so the renders) follows a moment
    /// later and on release, so dragging stays smooth.
    @State private var strengthDraft: Double = 0.7
    @State private var angleDraft: Double = 100
    @State private var pending: Task<Void, Never>?

    private var strength: Binding<Double> {
        Binding(get: { strengthDraft }, set: { v in strengthDraft = v; schedule() })
    }
    private var angle: Binding<Double> {
        Binding(get: { angleDraft }, set: { v in angleDraft = v; schedule() })
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            if !Task.isCancelled { commit() }
        }
    }

    private func commit() {
        pending?.cancel()
        var s = store.look.shadow
        s.strength = Float(strengthDraft)
        s.angle = Float(angleDraft)
        pending = nil
        if s != store.look.shadow { store.look.shadow = s }
    }

    private func released(_ editing: Bool) { if !editing { commit() } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(ShadowKind.allCases) { k in
                    Button { store.look.shadow.kind = k } label: {
                        Text(k.title)
                            .font(.system(size: 15, weight: store.look.shadow.kind == k ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(store.look.shadow.kind == k ? Theme.ink : Color.white)
                            .foregroundStyle(store.look.shadow.kind == k ? Color.white : Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: store.look.shadow.kind == k ? 0 : 1))
                    }
                }
            }
            Text(description).font(.system(size: 14)).foregroundStyle(Theme.muted).frame(height: 38, alignment: .top)
            if store.look.shadow.kind != .none {
                row("Strength", Slider(value: strength, in: 0.15...1, onEditingChanged: released), "\(Int((strengthDraft * 100).rounded()))%")
                row("Light from", Slider(value: angle, in: 0...359, onEditingChanged: released), lightName)
            }
            Spacer().frame(height: 4)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 230, alignment: .top)
        .onAppear {
            strengthDraft = Double(store.look.shadow.strength)
            angleDraft = Double(store.look.shadow.angle)
        }
        .onChange(of: store.look.shadow) { _, s in
            // Cancel in the tool screen puts the old look back; follow it.
            if pending == nil {
                strengthDraft = Double(s.strength); angleDraft = Double(s.angle)
            }
        }
    }

    private var description: String {
        switch store.look.shadow.kind {
        case .flatlay: return "Lying on the surface: dark where it touches, softening where it is thicker."
        case .lifted: return "Raised slightly off the surface, with a wider, softer shadow."
        case .none: return "No shadow."
        }
    }

    /// The shadow falls away from the light, so name the light's side.
    private var lightName: String {
        let lightDeg = (angleDraft + 180).truncatingRemainder(dividingBy: 360)
        let names = ["Right", "Bottom right", "Bottom", "Bottom left", "Left", "Top left", "Top", "Top right"]
        return names[Int(((lightDeg + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
    }

    private func row(_ title: String, _ slider: Slider<EmptyView, EmptyView>, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 15)).frame(width: 82, alignment: .leading)
            slider
            Text(value).font(.system(size: 14)).foregroundStyle(Theme.muted).frame(width: 92, alignment: .trailing)
        }
    }
}
