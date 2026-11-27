#if PERSONAL
import UIKit
import Security
import UniformTypeIdentifiers

/// Personal build only: sends one item's photos to Google's Gemini, which recognises the item
/// (checking Google Search when it helps) and writes a title and description. Runs only when
/// "Describe with Gemini" is tapped, on Mathew's own free Google AI Studio key kept in the
/// Keychain. Not in the App Store version (decision 27 Nov 2026).
enum GeminiWriter {
    struct Listing: Equatable { var title: String; var description: String }

    enum Failure: LocalizedError {
        case noKey, badKey, limit(String), declined, network(String), unreadable
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Gemini API key first."
            case .badKey: return "Google didn't accept the API key. Check it with Change API key."
            case .limit(let s): return "Google turned this down for every free Gemini model it offers your key. Google said: " + s
            case .declined: return "Gemini declined to describe these photos."
            case .network(let s): return "Couldn't reach Gemini: \(s)"
            case .unreadable: return "Gemini's answer couldn't be read. Try again."
            }
        }
    }

    /// Google's aliases for its current Flash models, tried first. Which models a free key may use
    /// changes over time (some get a free limit of zero), so the key's own model list is tried
    /// after these, and the one that worked is remembered.
    static let preferred = ["gemini-flash-latest", "gemini-flash-lite-latest"]
    private static let workedKey = "gemini.model.v1"

    static let instructions = """
    You write listings for second-hand clothing, shoes and accessories on Vinted, eBay and Depop. \
    You are shown photos of one item: usually the front, the back, its labels and close-ups.

    First identify the item as precisely as the photos allow: brand, product line or model name, \
    type, colour, material, size, and anything distinctive (fit, pattern, features). Read every \
    label. If the brand and a style name or code are visible, you may use Google Search to confirm \
    the exact product name; never guess a model name you can't confirm from the photos or a search.

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

    private static let service = "app.clearcut.photos"
    private static let account = "gemini-api-key"

    static var hasKey: Bool { readKey() != nil }

    static func saveKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !k.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(k.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func readKey() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    // MARK: Request

    /// Photos for sending: JPEG, at most 1600 px on the long side.
    static func encoded(_ urls: [URL]) -> [String] {
        urls.prefix(5).compactMap { u in
            autoreleasepool {
                guard let data = try? Data(contentsOf: u), let cg = ImageIOHelpers.loadOriented(data, maxPixel: 1600),
                      let jpg = ImageIOHelpers.encode(cg, type: .jpeg, quality: 0.85) else { return nil }
                return jpg.base64EncodedString()
            }
        }
    }

    /// Writes the listing. `hints` is what the phone already read from the labels.
    static func describe(photos: [URL], hints: ListingFacts) async throws -> Listing {
        guard let key = readKey() else { throw Failure.noKey }
        let images = await Task.detached(priority: .userInitiated) { GeminiWriter.encoded(photos) }.value
        guard !images.isEmpty else { throw Failure.unreadable }

        var parts: [[String: Any]] = images.map { ["inline_data": ["mime_type": "image/jpeg", "data": $0]] }
        var ask = "Here are the photos of one item."
        if !hints.text.isEmpty { ask += " Text the phone read from its labels (may contain mistakes):\n" + hints.text }
        parts.append(["text": ask])

        var models: [String] = []
        if let w = UserDefaults.standard.string(forKey: workedKey) { models.append(w) }
        models += preferred
        models += await listFlashModels(key: key)
        var seen = Set<String>()
        models = models.filter { seen.insert($0).inserted }

        var last: Failure = .limit("no model answered")
        for model in models.prefix(6) {
            // Google Search first (better names); without it if that part isn't allowed on this key.
            for search in [true, false] {
                do {
                    let listing = try await send(parts: parts, key: key, model: model, search: search)
                    UserDefaults.standard.set(model, forKey: workedKey)
                    return listing
                } catch let f as Failure {
                    switch f {
                    case .limit, .network: last = f; continue
                    default: throw f
                    }
                }
            }
        }
        throw last
    }

    /// Flash models this key can use for writing, newest first, from Google's own list.
    private static func listFlashModels(key: String) async -> [String] {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30
        guard let result = try? await URLSession.shared.data(for: request),
              let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              let list = json["models"] as? [[String: Any]] else { return [] }
        let skip = ["image", "tts", "audio", "live", "embedding", "thinking", "exp", "preview"]
        let names = list.compactMap { m -> String? in
            guard let name = (m["name"] as? String)?.replacingOccurrences(of: "models/", with: ""),
                  let methods = m["supportedGenerationMethods"] as? [String], methods.contains("generateContent"),
                  name.contains("flash"), !skip.contains(where: { name.contains($0) }) else { return nil }
            return name
        }
        return names.sorted(by: >)
    }

    private static func send(parts: [[String: Any]], key: String, model: String, search: Bool) async throws -> Listing {
        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": instructions]]],
            "contents": [["role": "user", "parts": parts]],
        ]
        if search { body["tools"] = [["google_search": [String: Any]()]] }

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.network(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let error = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any]
        let message = error?["message"] as? String ?? ""
        switch status {
        case 200: break
        case 429: throw Failure.limit(message.isEmpty ? "too many requests" : String(message.prefix(300)))
        case 401, 403: throw Failure.badKey
        case 400 where message.localizedCaseInsensitiveContains("api key"): throw Failure.badKey
        default: throw Failure.network(message.isEmpty ? "error \(status)" : message)
        }
        return try parse(data)
    }

    /// The title and description from Gemini's reply: the JSON object in its text.
    static func parse(_ data: Data) throws -> Listing {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.unreadable }
        if (json["promptFeedback"] as? [String: Any])?["blockReason"] != nil { throw Failure.declined }
        let candidate = (json["candidates"] as? [[String: Any]])?.first
        if let reason = candidate?["finishReason"] as? String, ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"].contains(reason) {
            throw Failure.declined
        }
        let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { throw Failure.unreadable }
        var piece = String(text[start...end])
        if (try? JSONSerialization.jsonObject(with: Data(piece.utf8))) == nil, let lastOpen = text[..<end].lastIndex(of: "{") {
            piece = String(text[lastOpen...end])
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(piece.utf8))) as? [String: Any],
              let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let description = (obj["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw Failure.unreadable
        }
        return Listing(title: String(title.prefix(80)), description: description)
    }
}
#endif
