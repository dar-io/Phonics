import XCTest
@testable import StorySoundsCore

final class VersionTests: XCTestCase {
    func testSchemaVersion() { XCTAssertEqual(CurriculumSchema.version, 1) }
}
