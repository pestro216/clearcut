import SwiftUI
import UIKit

/// A ready-to-copy title and description for one item, made on the phone from its photos:
/// labels read for brand, size and fabric, Vision for the kind of item, the cutout for its
/// colour. Nothing is written that wasn't read from the photos.
struct ListingScreen: View {
    @EnvironmentObject var store: BatchStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID

    @State private var chosen: [UUID] = []
    @State private var facts = ListingFacts()
    @State private var written: String?
    @State private var working = false
    @State private var copied: String?
    /// The online version, when asked for.
    @State private var online: OnlineWriter.Listing?
    @State private var usePhone = false
    @State private var onlineBusy = false
    @State private var onlineError: String?
    @State private var keySheet = false

    /// The chosen photos in batch order.
    private var ordered: [UUID] { store.items.map(\.id).filter { chosen.contains($0) } }
    private var showingOnline: Bool { online != nil && !usePhone }
    private var title: String { showingOnline ? online!.title : facts.title }
    private var description: String { showingOnline ? online!.description : (written ?? facts.text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        photoStrip
                        Text("Photos of this item, labels included. Tap to add or leave one out.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    if working {
                        HStack(spacing: 10) { ProgressView(); Text("Reading the labels").foregroundStyle(Theme.muted) }
                    } else if title.isEmpty {
                        Text("Nothing could be read from these photos. A close-up of the brand and size labels helps.")
                            .foregroundStyle(Theme.muted)
                    } else {
                        card("Title", title)
                        card("Description", description)
                    }
                    onlineSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear(perform: setUp)
        .onDisappear { store.listings[id] = facts }
        .onChange(of: chosen) { _, _ in make(); online = nil; onlineError = nil }
        .sheet(isPresented: $keySheet) { KeySheet { if OnlineWriter.hasKey { describeOnline() } } }
    }

    @ViewBuilder private var onlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if online != nil {
                Button(usePhone ? "Show the AI version" : "Show the phone's version") { usePhone.toggle(); copied = nil }
                    .font(.system(size: 15, weight: .medium))
            }
            Button {
                if OnlineWriter.hasKey { describeOnline() } else { keySheet = true }
            } label: {
                HStack(spacing: 10) {
                    if onlineBusy { ProgressView() }
                    Text(onlineBusy ? "Claude is looking at the photos" : online == nil ? "Describe with AI" : "Describe again with AI")
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.white).foregroundStyle(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(onlineBusy || ordered.isEmpty)
            if let onlineError {
                Text(onlineError).font(.system(size: 14)).foregroundStyle(Theme.warning)
            }
            Text("Sends the chosen photos to Anthropic's Claude, which recognises the item and can search the web for its exact name. Nothing else in Clearcut goes online. Costs about 1p per item on your Anthropic account.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if OnlineWriter.hasKey {
                Button("Change API key") { keySheet = true }.font(.system(size: 13))
            }
        }
    }

    private func describeOnline() {
        let picked = ordered.compactMap { id in store.items.first { $0.id == id } }
        let photos = picked.map(\.originalURL)
        let hints = facts, want = ordered
        onlineBusy = true
        onlineError = nil
        Task {
            do {
                let result = try await OnlineWriter.describe(photos: photos, hints: hints)
                if want == ordered { online = result; usePhone = false; copied = nil }
            } catch {
                onlineError = error.localizedDescription
            }
            onlineBusy = false
        }
    }

    private func card(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            Text(text).font(.system(size: 17)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Button {
                UIPasteboard.general.string = text
                copied = heading
            } label: {
                Text(copied == heading ? "Copied" : "Copy \(heading.lowercased())")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Theme.ink).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            .frame(width: 64, height: 64)
                            .overlay { if let img = store.grid[item.id] { Image(uiImage: img).resizable().scaledToFit() } }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(on ? Theme.ink : Color.clear, lineWidth: 3))
                            .opacity(on ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Photo, used" : "Photo, not used")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func setUp() {
        guard chosen.isEmpty, let i = store.items.firstIndex(where: { $0.id == id }) else { return }
        if let saved = store.listings[id] { facts = saved }
        // This photo and the next three: the usual front, back, label and close-up.
        chosen = Array(store.items[i..<min(store.items.count, i + 4)].map(\.id))
    }

    /// Reads the chosen photos and writes the title and description.
    private func make() {
        let picked = ordered.compactMap { id in store.items.first { $0.id == id } }
        guard let first = picked.first else { facts = ListingFacts(); written = nil; return }
        let texts = picked.map(\.originalURL)
        let front = (photo: first.previewPhotoURL ?? first.originalURL, alpha: first.previewAlphaURL)
        let want = ordered
        working = true
        copied = nil
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                PhotoReader.read(texts: texts, front: front)
            }.value
            guard want == ordered else { return }
            facts = found
            var better: String?
            if !found.title.isEmpty { better = await ListingWriter.write(found) }
            guard want == ordered else { return }
            written = better
            working = false
        }
    }
}

/// Where the Anthropic API key is typed in. It is kept in the iPhone's Keychain, on this phone only.
private struct KeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let saved: () -> Void
    @State private var key = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Anthropic API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Make a key at console.anthropic.com, under API keys, and paste it here. It is kept in this iPhone's Keychain and only sent to Anthropic.")
                }
                if OnlineWriter.hasKey {
                    Section { Button("Remove the saved key", role: .destructive) { OnlineWriter.saveKey(""); dismiss() } }
                }
            }
            .navigationTitle("Describe with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { OnlineWriter.saveKey(key); dismiss(); saved() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
