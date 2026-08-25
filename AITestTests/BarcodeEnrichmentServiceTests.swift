import XCTest
@testable import SmartInventory

/// Live lookup of `BarcodeEnrichmentService.enrichWithOutcome(barcode:)`.
/// Hit = Open Food Facts product. Miss = code absent from OFF and UPCItemDB.
final class BarcodeEnrichmentServiceTests: XCTestCase {

    /// Nutella — present in Open Food Facts (`status == 1`).
    private let openFoodFactsHitBarcode = "3017620422003"
    /// Not in Open Food Facts; UPCItemDB returns `INVALID_UPC`.
    private let unknownBarcode = "8900000000000"

    func testEnrichmentHitFromOpenFoodFacts() async {
        let result = await BarcodeEnrichmentService.shared.enrichWithOutcome(barcode: openFoodFactsHitBarcode)
        guard let product = result.product else {
            XCTFail("Expected Open Food Facts hit for \(openFoodFactsHitBarcode)")
            return
        }
        XCTAssertEqual(result.outcome, "found")
        XCTAssertEqual(result.provider, "off")
        XCTAssertGreaterThanOrEqual(result.durationMs, 0)
        XCTAssertNil(result.reason)
        XCTAssertFalse(product.name.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertFalse(product.category.isEmpty)
        XCTAssertFalse(product.uomSymbol.isEmpty)
    }

    func testEnrichmentMissReturnsNil() async {
        let result = await BarcodeEnrichmentService.shared.enrichWithOutcome(barcode: unknownBarcode)
        XCTAssertNil(result.product, "Unknown code should miss OFF and UPCItemDB")
        XCTAssertTrue(["not_found", "network_error", "parser_error"].contains(result.outcome))
        XCTAssertTrue(["off", "upcitemdb"].contains(result.provider))
        XCTAssertGreaterThanOrEqual(result.durationMs, 0)
    }
}
