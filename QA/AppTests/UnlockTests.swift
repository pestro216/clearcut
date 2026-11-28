import XCTest
import StoreKit
import StoreKitTest
@testable import Clearcut

/// The unlock purchase against Apple's local test store (QA/AppTests/Clearcut.storekit), so it can
/// be checked on GitHub's simulator without a developer account or real money.
@MainActor
final class UnlockTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Clearcut")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        // The test store can take a moment to load its products after the session starts.
        for _ in 0..<10 {
            if let found = try? await Product.products(for: [Unlock.productID]), !found.isEmpty { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func testProductHasAPrice() async throws {
        try await requireTestStore()
        let u = Unlock()
        await u.loadProduct()
        var why = "the test store returned no products"
        do { _ = try await Product.products(for: [Unlock.productID]) } catch { why = "the test store said: \(error)" }
        XCTAssertEqual(u.product?.id, Unlock.productID, why)
        XCTAssertFalse(u.product?.displayPrice.isEmpty ?? true, "The price must be shown before buying")
    }

    func testBuyThenRestoreOnAFreshStart() async throws {
        try await requireTestStore()
        let u = Unlock()
        await u.refresh()
        XCTAssertFalse(u.unlocked)
        await u.purchase()
        XCTAssertTrue(u.unlocked, u.problem ?? "")

        // A fresh start (or another device on the same Apple Account) finds the purchase.
        let again = Unlock()
        again.syncWithAppStore = {}
        await again.refresh()
        XCTAssertTrue(again.unlocked)
        await again.restore()
        XCTAssertTrue(again.unlocked)
        XCTAssertNil(again.problem)
    }

    func testRefundLocksAgain() async throws {
        try await requireTestStore()
        let u = Unlock()
        await u.purchase()
        XCTAssertTrue(u.unlocked)
        for t in session.allTransactions() { try session.refundTransaction(identifier: UInt(t.identifier)) }
        await u.refresh()
        XCTAssertFalse(u.unlocked)
    }

    /// GitHub's simulator has so far never served the test store's product (no error, just nothing),
    /// so these tests are skipped there rather than failing. The real check is Apple's sandbox on a
    /// phone through TestFlight. They run as soon as the test store works.
    private func requireTestStore() async throws {
        let found = (try? await Product.products(for: [Unlock.productID])) ?? []
        if found.isEmpty { throw XCTSkip("The StoreKit test store served no products on this simulator") }
    }

    func testRestoreWithNothingBoughtSaysSo() async {
        let u = Unlock()
        u.syncWithAppStore = {}
        await u.restore()
        XCTAssertFalse(u.unlocked)
        XCTAssertNotNil(u.problem)
    }

    func testFreeSavesCountDown() {
        let u = Unlock()
        let start = u.freeLeft
        u.recordSaves(3)
        XCTAssertEqual(u.freeLeft, max(0, start - 3))
        u.recordSaves(100)
        XCTAssertEqual(u.freeLeft, 0)
    }
}
