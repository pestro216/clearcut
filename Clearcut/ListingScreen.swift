import SwiftUI
import UIKit

/// A listing for one item, made from its photos: labels read for brand, size and fabric, the
/// cutout for kind and colour, an A4 sheet for measurements. Every field can be changed, and
/// nothing is filled in that wasn't read from the photos.
struct ListingScreen: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    @State private var chosen: [UUID] = []
    @State private var facts = ListingFacts()
    @State private var reading = false
    @State private var readOnce = false
    @State private var written: String?
    @State private var writing = false
    @State private var copied = false
    @State private var measuring = false

    /// The chosen photos in batch order.
    private var ordered: [UUID] { store.items.map(\.id).filter { chosen.contains($0) } }
    private var descriptionText: String { written ?? facts.text }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoStrip
                } header: {
                    Text("Photos of this item")
                } footer: {
                    Text("Tick every photo of this item, including close-ups of its labels.")
                }
                Section {
                    Button { read() } label: {
                        HStack {
                            Text(reading ? "Reading labels" : readOnce ? "Read labels again" : "Read labels")
                            if reading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(reading || chosen.isEmpty)
                }
                Section("Details") {
                    field("Brand", $facts.brand)
                    field("Item", $facts.kind)
                    field("Colour", $facts.colour)
                    field("Size", $facts.size)
                    field("Material", $facts.materials)
                    field("Condition", $facts.condition, prompt: "Your words, for example: worn twice, no marks")
                }
                Section {
                    field("Length", $facts.length)
                    field("Width", $facts.width)
                    Button("Measure with an A4 sheet") { measuring = true }.disabled(ordered.isEmpty)
                } header: {
                    Text("Measured laid flat")
                } footer: {
                    Text("Lay the item flat with a sheet of A4 paper flat beside it, not touching, and photograph both from above.")
                }
                Section("Title") {
                    Text(facts.title.isEmpty ? "Read the labels or fill in the details." : facts.title)
                        .foregroundStyle(facts.title.isEmpty ? Theme.muted : Theme.ink)
                        .textSelection(.enabled)
                }
                Section {
                    Text(descriptionText).textSelection(.enabled)
                    if ListingWriter.available {
                        Button {
                            write()
                        } label: {
                            HStack {
                                Text(written == nil ? "Write it up with Apple Intelligence" : "Write it again")
                                if writing { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(writing)
                        if written != nil { Button("Use the plain version") { written = nil } }
                    }
                } header: {
                    Text("Description")
                } footer: {
                    if written != nil { Text("Written on your phone from the details above. Check it before posting.") }
                }
                Section {
                    Button(copied ? "Copied" : "Copy title and description") {
                        UIPasteboard.general.string = facts.title + "\n\n" + descriptionText
                        copied = true
                    }
                    .disabled(facts.title.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $measuring) {
                MeasureScreen(ids: ordered) { length, width in
                    facts.length = Measure.text(length)
                    facts.width = Measure.text(width)
                }
            }
        }
        .onAppear(perform: setUp)
        .onDisappear { store.listings[id] = facts }
        .onChange(of: facts) { _, _ in copied = false; written = nil }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.items) { item in
                    let on = chosen.contains(item.id)
                    Button {
                        if on { chosen.removeAll { $0 == item.id } } else { chosen.append(item.id) }
                    } label: {
                        Theme.tile
                            .frame(width: 72, height: 72)
                            .overlay { if let img = store.grid[item.id] { Image(uiImage: img).resizable().scaledToFit() } }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(on ? Theme.ink : Color.clear, lineWidth: 3))
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18))
                                        .foregroundStyle(.white, Theme.ink).padding(4)
                                }
                            }
                            .opacity(on ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Photo, chosen" : "Photo, not chosen")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func field(_ title: String, _ value: Binding<String>, prompt: String = "") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Theme.muted).frame(width: 92, alignment: .leading)
            TextField(title, text: value, prompt: Text(prompt), axis: .vertical)
        }
    }

    private func setUp() {
        if let saved = store.listings[id] { facts = saved; readOnce = true }
        guard chosen.isEmpty, let i = store.items.firstIndex(where: { $0.id == id }) else { return }
        // This photo and the next three: the usual front, back, label and close-up.
        chosen = Array(store.items[i..<min(store.items.count, i + 4)].map(\.id))
    }

    private func read() {
        let picked = ordered.compactMap { id in store.items.first { $0.id == id } }
        guard let first = picked.first else { return }
        let texts = picked.map(\.originalURL)
        let front = (photo: first.previewPhotoURL ?? first.originalURL, alpha: first.previewAlphaURL)
        reading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                PhotoReader.read(texts: texts, front: front)
            }.value
            // What was read replaces only what it found; anything typed stays unless the labels say otherwise.
            if !found.brand.isEmpty { facts.brand = found.brand }
            if !found.kind.isEmpty { facts.kind = found.kind }
            if !found.colour.isEmpty { facts.colour = found.colour }
            if !found.size.isEmpty { facts.size = found.size }
            if !found.materials.isEmpty { facts.materials = found.materials }
            reading = false
            readOnce = true
        }
    }

    private func write() {
        let f = facts
        writing = true
        Task {
            let text = await ListingWriter.write(f)
            writing = false
            if let text, f == facts { written = text }
        }
    }
}

/// Measures an item against an A4 sheet in one of its photos, with a ruler for anything else
/// (armpit to armpit, sleeve, inside leg).
struct MeasureScreen: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let ids: [UUID]
    let use: (Double, Double) -> Void

    private enum Phase { case looking, none, found }
    @State private var phase = Phase.looking
    @State private var image: UIImage?
    @State private var sheet: [Measure.Point] = []
    @State private var result: Measure.Result?
    @State private var rulerA = Measure.Point(0, 0)
    @State private var rulerB = Measure.Point(0, 0)
    @State private var startA: Measure.Point?
    @State private var startB: Measure.Point?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if let r = result {
                    Button("Use these") { use(r.length, r.width); dismiss() }.font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20).padding(.vertical, 12)

            GeometryReader { geo in
                if let image {
                    let map = ViewMap(image: image.size, view: geo.size)
                    let toView = map.toView
                    let toImage = map.toImage
                    ZStack {
                        Image(uiImage: image).resizable().scaledToFit()
                        if sheet.count == 4 {
                            Path { p in p.addLines(sheet.map(toView)); p.closeSubpath() }
                                .stroke(Theme.warning, lineWidth: 2)
                        }
                        if let r = result {
                            line(toView(r.lengthEnds.0), toView(r.lengthEnds.1), dashed: true)
                            line(toView(r.widthEnds.0), toView(r.widthEnds.1), dashed: true)
                            line(toView(rulerA), toView(rulerB), dashed: false)
                            handle(at: toView(rulerA))
                                .gesture(DragGesture().onChanged { v in
                                    if startA == nil { startA = rulerA }
                                    let s = toView(startA!)
                                    rulerA = toImage(CGPoint(x: s.x + v.translation.width, y: s.y + v.translation.height))
                                }.onEnded { _ in startA = nil })
                            handle(at: toView(rulerB))
                                .gesture(DragGesture().onChanged { v in
                                    if startB == nil { startB = rulerB }
                                    let s = toView(startB!)
                                    rulerB = toImage(CGPoint(x: s.x + v.translation.width, y: s.y + v.translation.height))
                                }.onEnded { _ in startB = nil })
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 12)

            readout.padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task { await find() }
    }

    @ViewBuilder private var readout: some View {
        switch phase {
        case .looking:
            Text("Looking for an A4 sheet").foregroundStyle(Theme.muted)
        case .none:
            Text("No A4 sheet found in these photos. Lay the item flat with a white sheet of A4 paper flat beside it, not touching, and photograph both from above.")
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .found:
            if let r = result {
                VStack(alignment: .leading, spacing: 6) {
                    row("Length", Measure.text(r.length))
                    row("Width", Measure.text(r.width))
                    if let d = Measure.distance(rulerA, rulerB, sheet: sheet) { row("Ruler", Measure.text(d)) }
                    Text(r.sheetCovered > 0.4
                         ? "The sheet seems to be touching the item, so these may be out. Move it apart and photograph again."
                         : "Drag the two dots to measure anything else. Only right for things lying flat on the same floor as the sheet.")
                        .font(.system(size: 14))
                        .foregroundStyle(r.sheetCovered > 0.4 ? Theme.warning : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
        }
    }

    private func line(_ a: CGPoint, _ b: CGPoint, dashed: Bool) -> some View {
        Path { p in p.move(to: a); p.addLine(to: b) }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: dashed ? 1.5 : 2.5, dash: dashed ? [6, 4] : []))
    }

    private func handle(at p: CGPoint) -> some View {
        Circle().fill(.white)
            .overlay(Circle().stroke(Theme.ink, lineWidth: 2.5))
            .frame(width: 26, height: 26)
            .contentShape(Circle().inset(by: -14))
            .position(p)
    }

    /// The first chosen photo with an A4 sheet in it, and the item measured against it.
    private func find() async {
        let candidates = ids.compactMap { id in store.items.first { $0.id == id } }
            .compactMap { i -> (URL, URL)? in
                guard let p = i.previewPhotoURL, let a = i.previewAlphaURL else { return nil }
                return (p, a)
            }
        let found = await Task.detached(priority: .userInitiated) { () -> Box<(UIImage, [Measure.Point], Measure.Result)?> in
            for (pu, au) in candidates {
                let hit: (UIImage, [Measure.Point], Measure.Result)? = autoreleasepool {
                    guard let data = try? Data(contentsOf: pu), let cg = ImageIOHelpers.loadOriented(data),
                          let photo = RGBAImage(cgImage: cg), let corners = PhotoReader.sheet(in: cg, photo: photo),
                          let alpha = BatchStore.readAlpha(au, width: photo.width, height: photo.height),
                          let r = Measure.item(alpha: alpha, width: photo.width, height: photo.height, sheet: corners) else { return nil }
                    return (UIImage(cgImage: cg), corners, r)
                }
                if let hit { return Box(hit) }
            }
            return Box(nil)
        }.value.value
        if let f = found {
            image = f.0; sheet = f.1; result = f.2
            rulerA = f.2.widthEnds.0; rulerB = f.2.widthEnds.1
            phase = .found
        } else {
            if let first = candidates.first, let img = UIImage(contentsOfFile: first.0.path) { image = img }
            phase = .none
        }
    }
}

/// Converts between a photo's pixels and the view showing it scaled to fit.
private struct ViewMap {
    let k: Double, ox: Double, oy: Double, iw: Double, ih: Double

    init(image: CGSize, view: CGSize) {
        iw = Double(image.width); ih = Double(image.height)
        let vw = Double(view.width), vh = Double(view.height)
        k = min(vw / max(iw, 1), vh / max(ih, 1))
        ox = (vw - iw * k) / 2
        oy = (vh - ih * k) / 2
    }

    func toView(_ p: Measure.Point) -> CGPoint {
        CGPoint(x: ox + p.x * k, y: oy + p.y * k)
    }

    func toImage(_ p: CGPoint) -> Measure.Point {
        let x = (Double(p.x) - ox) / max(k, 1e-9), y = (Double(p.y) - oy) / max(k, 1e-9)
        return Measure.Point(min(iw, max(0, x)), min(ih, max(0, y)))
    }
}
