import XCTest
@testable import SmartInventory

/// Live lookup of `BarcodeEnrichmentService.enrich(barcode:)`.
/// Hit = Open Food Facts product. Miss = code absent from OFF and UPCItemDB.
final class BarcodeEnrichmentServiceTests: XCTestCase {

    /// Nutella — present in Open Food Facts (`status == 1`).
    private let openFoodFactsHitBarcode = "3017620422003"
    /// Not in Open Food Facts; UPCItemDB returns `INVALID_UPC`.
    private let unknownBarcode = "8900000000000"

    func testEnrichmentHitFromOpenFoodFacts() async {
        let product = await BarcodeEnrichmentService.shared.enrich(barcode: openFoodFactsHitBarcode)
        guard let product else {
            XCTFail("Expected Open Food Facts hit for \(openFoodFactsHitBarcode)")
            return
        }
        XCTAssertFalse(product.name.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertFalse(product.category.isEmpty)
        XCTAssertFalse(product.uomSymbol.isEmpty)
    }

    func testEnrichmentMissReturnsNil() async {
        let product = await BarcodeEnrichmentService.shared.enrich(barcode: unknownBarcode)
        XCTAssertNil(product, "Unknown code should miss OFF and UPCItemDB")
    }
}
