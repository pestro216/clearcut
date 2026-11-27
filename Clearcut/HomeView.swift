import SwiftUI
import PhotosUI

struct HomeView: View {
    @EnvironmentObject var store: BatchStore
    @State private var picks: [PhotosPickerItem] = []
    @State private var about = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clearcut")
                .font(.system(size: 20, weight: .bold))
            Spacer(minLength: 20)
            HomeDemo()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 20)
            PhotosPicker(selection: $picks, maxSelectionCount: BatchStore.maxPerBatch, selectionBehavior: .ordered, matching: .images) {
                Text("Start new batch")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.ink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("Up to \(BatchStore.maxPerBatch) photos at a time")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            Button { about = true } label: {
                Text("© \(Copyright.year) \(Copyright.owner)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .accessibilityLabel("About Clearcut")
            .padding(.top, 12)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $about) { AboutView() }
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            store.add(new)
            picks = []
        }
    }
}

enum Copyright {
    static let owner = "Woolfall"
    static let year = "2026"
}

/// A looping demonstration on the home screen: an item as photographed, then a line sweeps across
/// and leaves it on a clean surface with a soft shadow, a different one each time. Holds still on
/// the finished look when Reduce Motion is on.
///
/// With a real photo bundled (`demo-photo.jpg` and its Clearcut cutout `demo-cutout.png`, the
/// same size, in Clearcut/Demo), the demo uses them. Without, it draws a shirt symbol on a floor.
struct HomeDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var images: [String: UIImage] = [:]
    @State private var photo: UIImage?
    @State private var cutout: UIImage?

    /// The "photo" surface, then the finished looks it changes into, in turn.
    private let before = "laminate_floor_02"
    private let looks: [Look] = [.surface("white_stucco"), .surface("dark_wood"), .transparent, .surface("marble_01")]
    private enum Look: Hashable { case surface(String), transparent }

    private let cycle: Double = 3.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let n = Int(t / cycle)
            let phase = t.truncatingRemainder(dividingBy: cycle) / cycle
            // Hold on the photo, sweep, then hold on the result.
            let sweep = CGFloat(reduceMotion ? 1 : min(1, max(0, (phase - 0.18) / 0.36)))
            let look = looks[((n % looks.count) + looks.count) % looks.count]
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    scene(original: true, look: look, size: geo.size)
                    scene(original: false, look: look, size: geo.size)
                        .mask(alignment: .leading) { Rectangle().frame(width: w * sweep) }
                    if sweep > 0 && sweep < 1 {
                        Rectangle().fill(.white).frame(width: 2)
                            .position(x: w * sweep, y: geo.size.height / 2)
                    }
                }
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("A shirt on a floor, shown again cut out on a clean surface")
        .task { load() }
    }

    @ViewBuilder
    private func scene(original: Bool, look: Look, size: CGSize) -> some View {
        let item = min(size.width, size.height) * 0.56
        if let photo, let cutout {
            ZStack {
                if original {
                    fill(photo, size)
                } else {
                    if case .surface(let id) = look { backdrop(id) } else { Checkerboard() }
                    if case .surface = look {
                        fill(cutout, size).colorMultiply(.black).opacity(0.38)
                            .offset(x: item * 0.03, y: item * 0.05).blur(radius: item * 0.05)
                    }
                    fill(cutout, size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            drawn(original: original, look: look, size: size, item: item)
        }
    }

    /// An image filling the card, centred; the photo and its cutout line up exactly.
    private func fill(_ img: UIImage, _ size: CGSize) -> some View {
        Image(uiImage: img).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
    }

    @ViewBuilder
    private func drawn(original: Bool, look: Look, size: CGSize, item: CGFloat) -> some View {
        ZStack {
            if original {
                backdrop(before).overlay(Color.black.opacity(0.12))
            } else if case .surface(let id) = look {
                backdrop(id)
            } else {
                Checkerboard()
            }
            if original {
                // The photo's own hard, off-centre shadow.
                shirt(item).foregroundStyle(Color.black.opacity(0.35)).offset(x: -item * 0.1, y: item * 0.12).blur(radius: 2)
            } else if case .surface = look {
                shirt(item).foregroundStyle(Color.black.opacity(0.32)).offset(x: item * 0.05, y: item * 0.08).blur(radius: item * 0.06)
            }
            shirt(item).foregroundStyle(Color(red: 0.24, green: 0.33, blue: 0.52))
            shirt(item).foregroundStyle(Color.white.opacity(0.08)).scaleEffect(0.9).offset(y: -item * 0.02)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func shirt(_ side: CGFloat) -> some View {
        Image(systemName: "tshirt.fill").resizable().scaledToFit().frame(width: side, height: side)
    }

    @ViewBuilder
    private func backdrop(_ id: String) -> some View {
        if let img = images[id] {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Theme.tile
        }
    }

    private func load() {
        if photo == nil, let p = Bundle.main.url(forResource: "demo-photo", withExtension: "jpg"),
           let c = Bundle.main.url(forResource: "demo-cutout", withExtension: "png"),
           let pi = UIImage(contentsOfFile: p.path), let ci = UIImage(contentsOfFile: c.path), pi.size == ci.size {
            photo = pi; cutout = ci
        }
        var ids = [before]
        for l in looks { if case .surface(let id) = l { ids.append(id) } }
        for id in ids where images[id] == nil {
            if let u = Bundle.main.url(forResource: "thumb-\(id)", withExtension: "jpg"), let img = UIImage(contentsOfFile: u.path) {
                images[id] = img
            }
        }
    }
}

/// The light and dark squares that stand for "transparent".
private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 14
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.9)))
                    x += 2 * s
                }
                y += s; row += 1
            }
        }
    }
}

/// Copyright, privacy and credits for the work Clearcut is built on.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Clearcut", "Version \(version)\n© \(Copyright.year) \(Copyright.owner). All rights reserved.")
                    section("Privacy", "Your photos never leave your phone. Clearcut has no accounts, no tracking and no internet connection: every cutout is made on the phone itself. Finished photos are only added to your library when you tap Save.")
                    section("Cutout model", "BiRefNet (Zheng et al., 2024), MIT licence, converted for iPhone by the birefnet-lite-coreml project, MIT licence. Full licence texts are below.")
                    section("Surfaces", "Surface photos from Poly Haven (polyhaven.com), CC0.")
                    section("Licences", Licences.text)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(body).font(.system(size: 15)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}
