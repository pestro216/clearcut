import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes a listing description with Apple's on-phone language model (iOS 26, Apple Intelligence
/// phones). Nothing leaves the phone. Only compiled when the app is built with the iOS 26 SDK;
/// otherwise, and on phones without Apple Intelligence, the plain description is used.
enum ListingWriter {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    static let instructions = """
    You write short, honest second-hand clothing listings for sites like Vinted, eBay and Depop. \
    Use only the facts given. Never add a fact that is not given: no condition, fit, era, origin, \
    rarity or measurements unless they are listed. Plain, friendly British English, no emoji, no \
    hashtags, no capital-letter shouting. Three to five short sentences, then the facts as short lines.
    """

    /// A description written from the facts, or nil if the model isn't there or declines.
    static func write(_ facts: ListingFacts) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { return nil }
            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Facts:\n" + facts.text + "\n\nWrite the listing description."
            guard let response = try? await session.respond(to: prompt) else { return nil }
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        #endif
        return nil
    }
}
