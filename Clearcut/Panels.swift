import SwiftUI
import PhotosUI

struct PanelSheet: View {
    let panel: Panel
    var body: some View {
        Group {
            switch panel {
            case .background: BackgroundPanel()
            case .shadow: ShadowPanel()
            case .layout: LayoutPanel()
            }
        }
        .background(Theme.paper.ignoresSafeArea())
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

struct BackgroundPanel: View {
    @EnvironmentObject var store: BatchStore
    @State private var custom: Color = .white
    @State private var photoPick: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Background")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 20)

                Button {
                    store.setAllRemoved(!store.anyRemoved)
                } label: {
                    Text(store.anyRemoved ? "Restore original background" : "Remove original background")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white)
                        .foregroundStyle(Theme.ink)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                SectionTitle(text: "Colour")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button { store.look.backdrop = .transparent } label: {
                            Checker()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.black.opacity(0.15)))
                                .overlay(selectionRing(store.look.backdrop == .transparent))
                        }
                        .accessibilityLabel("Transparent")
                        ForEach(RGB.swatches, id: \.self) { c in
                            Button { store.look.backdrop = .colour(c) } label: {
                                Circle().fill(c.color)
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(Color.black.opacity(0.15)))
                                    .overlay(selectionRing(store.look.backdrop == .colour(c)))
                            }
                        }
                        ColorPicker("Custom colour", selection: $custom, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40, height: 40)
                    }
                    .padding(4)
                }

                Toggle("Studio light", isOn: $store.look.studioLight)
                    .font(.system(size: 16))
                    .disabled(!isColour)
                    .opacity(isColour ? 1 : 0.4)

                SectionTitle(text: "Textures")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(TextureKind.allCases) { k in
                            Button { store.look.backdrop = .texture(k) } label: {
                                VStack(spacing: 6) {
                                    Group {
                                        if let img = Renderer.textureThumbs[k] {
                                            Image(uiImage: img).resizable().scaledToFill()
                                        } else {
                                            Color.gray
                                        }
                                    }
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(store.look.backdrop == .texture(k) ? Theme.ink : Color.clear, lineWidth: 2.5))
                                    Text(k.title).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                SectionTitle(text: "Your own photo")
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
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            if case .colour(let c) = store.look.backdrop { custom = c.color }
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

    private var isColour: Bool {
        if case .colour = store.look.backdrop { return true }
        return false
    }

    private func selectionRing(_ on: Bool) -> some View {
        Circle().stroke(on ? Theme.ink : Color.clear, lineWidth: 2.5).padding(-4)
    }
}

// MARK: Shadow

struct ShadowPanel: View {
    @EnvironmentObject var store: BatchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Shadow")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 20)
            HStack(spacing: 10) {
                ForEach(ShadowStyle.allCases) { s in
                    Button { store.look.shadow = s } label: {
                        VStack(spacing: 6) {
                            ShadowGlyph(style: s)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(store.look.shadow == s ? Theme.ink : Theme.line,
                                            lineWidth: store.look.shadow == s ? 2.5 : 1))
                            Text(s.title).font(.system(size: 13)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Strength").font(.system(size: 15))
                    Spacer()
                    Text("\(Int(store.look.shadowStrength * 100))%").font(.system(size: 15)).foregroundStyle(Theme.muted)
                }
                Slider(value: $store.look.shadowStrength, in: 0.1...1)
            }
            .opacity(store.look.shadow == .none ? 0.4 : 1)
            .disabled(store.look.shadow == .none)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct ShadowGlyph: View {
    let style: ShadowStyle
    var body: some View {
        ZStack {
            switch style {
            case .none:
                EmptyView()
            case .soft:
                Ellipse().fill(Color.black.opacity(0.4)).frame(width: 26, height: 6).blur(radius: 2.5).offset(y: 13)
            case .floating:
                Ellipse().fill(Color.black.opacity(0.25)).frame(width: 20, height: 5).blur(radius: 3).offset(y: 18)
            case .hard:
                Rectangle().fill(Color.black.opacity(0.22))
                    .frame(width: 18, height: 10)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: -1.0, d: 1, tx: 0, ty: 0))
                    .offset(x: 16, y: 7)
            }
            RoundedRectangle(cornerRadius: 3).fill(Theme.ink)
                .frame(width: 18, height: 24)
                .offset(y: style == .floating ? -4 : 0)
        }
    }
}

// MARK: Layout

struct LayoutPanel: View {
    @EnvironmentObject var store: BatchStore
    private let sizes = [1080, 2048, 3000, 4096]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Layout")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 20)

                SectionTitle(text: "Shape")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CanvasShape.allCases) { s in
                            Button { store.look.shape = s } label: {
                                Text(s.title)
                                    .font(.system(size: 15, weight: store.look.shape == s ? .semibold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(store.look.shape == s ? Theme.ink : Color.white)
                                    .foregroundStyle(store.look.shape == s ? Color.white : Theme.ink)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Theme.line, lineWidth: store.look.shape == s ? 0 : 1))
                            }
                        }
                    }
                    .padding(2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Item size").font(.system(size: 15))
                        Spacer()
                        Text("\(Int(store.look.itemSize * 100))%").font(.system(size: 15)).foregroundStyle(Theme.muted)
                    }
                    Slider(value: $store.look.itemSize, in: 0.3...1.0)
                    Text("Tap a photo to move or resize just that one.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }

                SectionTitle(text: "Export size")
                Picker("Export size", selection: $store.look.exportLongSide) {
                    ForEach(sizes, id: \.self) { Text("\($0) px").tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Save as PNG", isOn: $store.look.preferPNG)
                    .font(.system(size: 16))
                Text("JPEG is smaller. Transparent backgrounds always save as PNG.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
    }
}
