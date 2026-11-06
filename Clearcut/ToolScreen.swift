import SwiftUI
import PhotosUI

enum Tool: String, Identifiable {
    case background, shadow
    var id: String { rawValue }
    var title: String { self == .background ? "Background" : "Shadow" }
}

/// Full-screen editing tool: a large live preview you can swipe through, the tool's
/// controls underneath, Cancel to undo every change made here, Done to go back.
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
                .font(.system(size: 17))
                Spacer()
                Text(tool.title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            PreviewPager(page: $page)
                .frame(maxHeight: .infinity)

            Group {
                switch tool {
                case .background: BackgroundControls()
                case .shadow: ShadowControls()
                }
            }
            .padding(.top, 8)
            .background(Theme.paper)
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear {
            entryLook = store.look
            page = startID ?? store.items.first(where: { $0.removed })?.id ?? store.items.first?.id
            store.focusID = page
        }
        .onChange(of: page) { _, new in store.focusID = new }
        .onDisappear { store.focusID = nil }
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
                    PreviewImage(item: item)
                        .padding(.horizontal, 16)
                        .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if store.items.count > 1, let page, let i = store.items.firstIndex(where: { $0.id == page }) {
                Text("\(i + 1) of \(store.items.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// One photo as it will be exported, fitted into the available space.
struct PreviewImage: View {
    @EnvironmentObject var store: BatchStore
    let item: BatchItem

    var body: some View {
        GeometryReader { geo in
            let aspect = item.pixelSize.width / max(item.pixelSize.height, 1)
            let w = min(geo.size.width, geo.size.height * aspect)
            let h = w / aspect
            ZStack {
                if item.removed {
                    if store.look.backdrop == .transparent { Checker() }
                    if let p = store.previews[item.id] {
                        Image(uiImage: p).resizable()
                    } else if let o = item.smallOriginal {
                        Image(uiImage: UIImage(cgImage: o)).resizable().opacity(0.4)
                        ProgressView()
                    }
                } else if let o = item.smallOriginal {
                    Image(uiImage: UIImage(cgImage: o)).resizable()
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
    }
}

// MARK: Background

struct BackgroundControls: View {
    @EnvironmentObject var store: BatchStore
    @State private var group: String = "Colour"
    @State private var custom: Color = .white
    @State private var photoPick: PhotosPickerItem?

    private var groups: [String] { ["Colour"] + Surface.Group.allCases.map(\.rawValue) + ["Your photo"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                if group == "Colour" {
                    colourRow
                } else if group == "Your photo" {
                    photoRow
                } else if let g = Surface.Group(rawValue: group), let list = Surface.catalogue[g] {
                    surfaceRow(list)
                }
            }
            .frame(height: 118, alignment: .top)

            Button {
                store.setAllRemoved(!store.anyRemoved)
            } label: {
                Text(store.anyRemoved ? "Restore original backgrounds" : "Remove backgrounds")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundStyle(Theme.ink)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .onAppear {
            switch store.look.backdrop {
            case .colour(let c): group = "Colour"; custom = c.color
            case .transparent: group = "Colour"
            case .surface(let id): group = Surface.group(of: id)?.rawValue ?? "Colour"
            case .photo: group = "Your photo"
            }
        }
        .onChange(of: custom) { _, c in
            let rgb = RGB(color: c)
            if store.look.backdrop != .colour(rgb) { store.look.backdrop = .colour(rgb) }
        }
        .onChange(of: photoPick) { _, p in
            if let p { store.setBackdropPhoto(p) }
            photoPick = nil
        }
    }

    private var colourRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { store.look.backdrop = .transparent } label: {
                        Checker()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.15)))
                            .overlay(ring(store.look.backdrop == .transparent))
                    }
                    .accessibilityLabel("Transparent")
                    ForEach(RGB.swatches, id: \.self) { c in
                        Button { store.look.backdrop = .colour(c) } label: {
                            Circle().fill(c.color)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.black.opacity(0.15)))
                                .overlay(ring(store.look.backdrop == .colour(c)))
                        }
                    }
                    ColorPicker("Custom colour", selection: $custom, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 5)
            }
            Toggle("Studio light", isOn: $store.look.studioLight)
                .font(.system(size: 16))
                .padding(.horizontal, 20)
                .disabled(!isColour)
                .opacity(isColour ? 1 : 0.4)
        }
    }

    private func surfaceRow(_ list: [Surface]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(list) { s in
                    Button { store.look.backdrop = .surface(s.id) } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let img = Renderer.surfaceThumb(s.id) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else {
                                    Color.gray
                                }
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(store.look.backdrop == .surface(s.id) ? Theme.ink : Color.clear, lineWidth: 3))
                            Text(s.title).font(.system(size: 13)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 3)
        }
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $photoPick, matching: .images) {
                Text(store.look.backdrop == .photo ? "Change backdrop photo" : "Choose from Photos")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white)
                    .foregroundStyle(Theme.ink)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(store.look.backdrop == .photo ? Theme.ink : Theme.line,
                                lineWidth: store.look.backdrop == .photo ? 2 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("A photo of your own surface, such as a table or floor, shot from above.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 20)
    }

    private var isColour: Bool {
        if case .colour = store.look.backdrop { return true }
        return false
    }

    private func ring(_ on: Bool) -> some View {
        Circle().stroke(on ? Theme.ink : Color.clear, lineWidth: 2.5).padding(-4)
    }
}

// MARK: Shadow

struct ShadowControls: View {
    @EnvironmentObject var store: BatchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ShadowStyle.allCases) { s in
                    Button { store.look.shadow = s } label: {
                        VStack(spacing: 5) {
                            ShadowGlyph(style: s)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(store.look.shadow == s ? Theme.ink : Theme.line,
                                            lineWidth: store.look.shadow == s ? 2.5 : 1))
                            Text(s.title).font(.system(size: 12)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            if store.look.shadow != .none {
                VStack(spacing: 2) {
                    sliderRow("Strength", value: $store.look.shadowStrength, range: 0.05...1,
                              label: "\(Int(store.look.shadowStrength * 100))%")
                    sliderRow("Softness", value: $store.look.shadowSoftness, range: 0...1,
                              label: "\(Int(store.look.shadowSoftness * 100))%")
                    if store.look.shadow.usesDistance {
                        sliderRow("Distance", value: $store.look.shadowDistance, range: 0...1,
                                  label: "\(Int(store.look.shadowDistance * 100))%")
                    }
                    if store.look.shadow.usesDirection {
                        sliderRow("Direction", value: $store.look.shadowAngle, range: 0...359,
                                  label: directionName(store.look.shadowAngle))
                    }
                }
                .padding(.horizontal, 20)
            } else {
                Text("No shadow is added.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 20)
            }
            Spacer().frame(height: 6)
        }
        .frame(minHeight: 250, alignment: .top)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 15)).frame(width: 78, alignment: .leading)
            Slider(value: value, in: range)
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.muted).frame(width: 74, alignment: .trailing)
        }
    }

    private func directionName(_ deg: Double) -> String {
        let names = ["Right", "Down right", "Down", "Down left", "Left", "Up left", "Up", "Up right"]
        let i = Int(((deg + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8
        return names[i]
    }
}

struct ShadowGlyph: View {
    let style: ShadowStyle
    var body: some View {
        ZStack {
            switch style {
            case .none:
                EmptyView()
            case .drop:
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35))
                    .frame(width: 18, height: 24).blur(radius: 1.5).offset(x: 3, y: 4)
            case .soft:
                Ellipse().fill(Color.black.opacity(0.4)).frame(width: 26, height: 6).blur(radius: 2.5).offset(y: 13)
            case .floating:
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.2))
                    .frame(width: 18, height: 24).blur(radius: 4).offset(x: 6, y: 8)
            case .hard:
                Rectangle().fill(Color.black.opacity(0.22))
                    .frame(width: 18, height: 10)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: -1.0, d: 1, tx: 0, ty: 0))
                    .offset(x: 16, y: 7)
            }
            RoundedRectangle(cornerRadius: 3).fill(Theme.ink)
                .frame(width: 18, height: 24)
        }
    }
}
