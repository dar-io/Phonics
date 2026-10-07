import XCTest
@testable import StorySoundsCore

final class CurriculumLoadingTests: XCTestCase {
    func testBundledCurriculumDecodes() throws {
        let c = try Curriculum.loadBundled()
        XCTAssertEqual(c.schemaVersion, CurriculumSchema.version)
        XCTAssertEqual(c.units.count, 98)
        XCTAssertGreaterThan(c.words.count, 1000)
        XCTAssertFalse(c.wordRequirements.isEmpty)
        XCTAssertEqual(c.units.first?.id, "g-s")
    }
    func testAudioManifestDecodesAndIsAllPlaceholder() throws {
        let m = try AudioManifest.loadBundled()
        XCTAssertTrue(m.statement.lowercased().contains("placeholder"))
        XCTAssertTrue(m.entries.allSatisfy { $0.status == .placeholder && $0.file == nil })
    }
}
