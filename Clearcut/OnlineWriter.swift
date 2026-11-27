import UIKit
import Security
import UniformTypeIdentifiers

/// The opt-in online listing writer: sends one item's photos to Anthropic's Claude, which
/// recognises the item (searching the web to pin down the exact model when it helps) and
/// writes a title and description. Only runs when you tap "Describe with AI"; nothing else in
/// Clearcut uses the internet.
///
/// For Mathew's own use it runs on his own Anthropic API key, typed into the app once and kept in
/// the iPhone's Keychain. A store release needs a small web service in between instead, because a
/// key can't be shipped inside an app (docs/app-store-plan.md).
enum OnlineWriter {
    struct Listing: Equatable { var title: String; var description: String }

    enum Failure: LocalizedError {
        case noKey, badKey, busy, declined, network(String), unreadable
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Anthropic API key first."
            case .badKey: return "Anthropic didn't accept the API key. Check it in Settings for Describe with AI."
            case .busy: return "Anthropic is busy right now. Try again in a minute."
            case .declined: return "Claude declined to describe these photos."
            case .network(let s): return "Couldn't reach Anthropic: \(s)"
            case .unreadable: return "Claude's answer couldn't be read. Try again."
            }
        }
    }

    static let model = "claude-opus-5-5"

    static let instructions = """
    You write listings for second-hand clothing, shoes and accessories on Vinted, eBay and Depop. \
    You are shown photos of one item: usually the front, the back, its labels and close-ups.

    First identify the item as precisely as the photos allow: brand, product line or model name, \
    type, colour, material, size, and anything distinctive (fit, pattern, features). Read every \
    label. If the brand and a style name or code are visible, you may search the web to confirm the \
    exact product name; never guess a model name you can't confirm from the photos or a search.

    Then write:
    - title: at most 80 characters, in the order resellers use: brand, model or line, colour, type, \
    size, one key feature if there's room. No emoji, no capital-letter shouting, no hashtags.
    - description: plain, friendly British English. Two to four short sentences on what it is and \
    what's good about it, then short lines for Brand, Size, Colour, Material (from the label) and \
    any useful details. Leave out condition, flaws, age and measurements unless they are clearly \
    visible; never claim "new", "authentic" or "rare" unless a tag or label shows it.

    Reply with only a JSON object: {"title": "...", "description": "..."}
    """

    // MARK: Key

    private static let keychainAccount = "anthropic-api-key"

    static var hasKey: Bool { readKey() != nil }

    static func saveKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "app.clearcut.photos",
                                   kSecAttrAccount as String: keychainAccount]
        SecItemDelete(base as CFDictionary)
        guard !k.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(k.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func readKey() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "app.clearcut.photos",
                                kSecAttrAccount as String: keychainAccount,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    // MARK: Request

    /// Photos for sending: JPEG, at most 1568 px on the long side (the size Claude reads at).
    static func encoded(_ urls: [URL]) -> [String] {
        urls.prefix(5).compactMap { u in
            autoreleasepool {
                guard let data = try? Data(contentsOf: u), let cg = ImageIOHelpers.loadOriented(data, maxPixel: 1568),
                      let jpg = ImageIOHelpers.encode(cg, type: .jpeg, quality: 0.85) else { return nil }
                return jpg.base64EncodedString()
            }
        }
    }

    /// Writes the listing. `hints` is what the phone already read from the labels.
    static func describe(photos: [URL], hints: ListingFacts) async throws -> Listing {
        guard let key = readKey() else { throw Failure.noKey }
        let images = await Task.detached(priority: .userInitiated) { OnlineWriter.encoded(photos) }.value
        guard !images.isEmpty else { throw Failure.unreadable }

        var content: [[String: Any]] = images.map { b64 in
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]]
        }
        var ask = "Here are the photos of one item."
        let read = hints.text
        if !read.isEmpty { ask += " Text the phone read from its labels (may contain mistakes):\n" + read }
        content.append(["type": "text", "text": ask])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": instructions,
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 3]],
            "messages": [["role": "user", "content": content]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.network(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw Failure.badKey
        case 429, 500...599: throw Failure.busy
        default:
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }.flatMap { $0["message"] as? String }
            throw Failure.network(msg ?? "error \(status)")
        }
        return try parse(data)
    }

    /// The title and description from Claude's reply: the JSON object in its final text.
    static func parse(_ data: Data) throws -> Listing {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable }
        if json["stop_reason"] as? String == "refusal" { throw Failure.declined }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw Failure.unreadable
        }
        // The last complete object, in case Claude wrote a note before it.
        var candidate = String(text[start...end])
        if (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) == nil,
           let lastOpen = text[..<end].lastIndex(of: "{") {
            candidate = String(text[lastOpen...end])
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) as? [String: Any],
              let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let description = (obj["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw Failure.unreadable
        }
        return Listing(title: String(title.prefix(80)), description: description)
    }
}
