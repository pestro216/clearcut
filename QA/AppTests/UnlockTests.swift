import XCTest
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
    }

    func testProductHasAPrice() async {
        let u = Unlock()
        await u.loadProduct()
        XCTAssertEqual(u.product?.id, Unlock.productID)
        XCTAssertFalse(u.product?.displayPrice.isEmpty ?? true, "The price must be shown before buying")
    }

    func testBuyThenRestoreOnAFreshStart() async {
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
        let u = Unlock()
        await u.purchase()
        XCTAssertTrue(u.unlocked)
        for t in session.allTransactions() { try session.refundTransaction(identifier: UInt(t.identifier)) }
        await u.refresh()
        XCTAssertFalse(u.unlocked)
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
