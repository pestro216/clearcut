import Foundation
import Security
import StoreKit

/// Free to try, then one payment. Cutting out is never limited: the first `freeSaves` finished
/// photos saved to the library are free, so people see the app work on their own photos before
/// paying. The unlock is a one-off (non-consumable) purchase through Apple, with Restore Purchases.
/// The personal build is always unlocked.
@MainActor
final class Unlock: ObservableObject {
    static let shared = Unlock()
    static let productID = "app.clearcut.photos.unlock"
    static let freeSaves = 10

    @Published private(set) var unlocked = false
    @Published private(set) var used = 0
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    /// A plain-English line when something went wrong, shown on the unlock screen.
    @Published var problem: String?

    var freeLeft: Int { unlocked ? .max : max(0, Self.freeSaves - used) }

    private var updates: Task<Void, Never>?
    /// Asks Apple for this account's purchases (it may ask the person to sign in). Swapped out in
    /// the app tests, where nobody can answer a sign-in.
    var syncWithAppStore: () async throws -> Void = { try await AppStore.sync() }

    init() {
        #if PERSONAL
        unlocked = true
        #else
        used = FreeCount.read()
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLEARCUT_UNLOCKED"] == "1" { unlocked = true }
        #endif
        #endif
    }

    /// Called once at launch: listens for purchases made elsewhere (another device, Ask to Buy,
    /// refunds), checks what this Apple Account owns, and fetches the price.
    func start() {
        #if !PERSONAL
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
        #endif
    }

    /// Counts photos saved while locked.
    func recordSaves(_ n: Int) {
        guard !unlocked, n > 0 else { return }
        used += n
        FreeCount.write(used)
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refresh() async {
        #if !PERSONAL
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { owned = true }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLEARCUT_UNLOCKED"] == "1" { owned = true }
        #endif
        unlocked = owned
        #endif
    }

    func purchase() async {
        problem = nil
        await loadProduct()
        guard let product else {
            problem = "Can't reach the App Store right now. Check your connection and try again."
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result {
                    await t.finish()
                    await refresh()
                } else {
                    problem = "Apple couldn't confirm the purchase. Try Restore Purchases."
                }
            case .pending:
                problem = "Waiting for approval. It unlocks by itself once approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            problem = "The purchase didn't go through. Nothing was charged."
        }
    }

    func restore() async {
        problem = nil
        busy = true
        defer { busy = false }
        try? await syncWithAppStore()
        await refresh()
        if !unlocked { problem = "No earlier purchase found on this Apple Account." }
    }
}

/// The free-save count, kept in the Keychain on this device so it isn't reset by reinstalling.
enum FreeCount {
    private static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                              kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.clearcut.photos") + ".free",
                                              kSecAttrAccount as String: "saves"]

    static func read() -> Int {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), let n = Int(s) else { return 0 }
        return max(0, n)
    }

    static func write(_ n: Int) {
        let data = Data(String(n).utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
