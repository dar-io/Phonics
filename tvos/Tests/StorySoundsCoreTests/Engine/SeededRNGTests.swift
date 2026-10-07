import XCTest
@testable import StorySoundsCore

final class SeededRNGTests: XCTestCase {
    func testSameSeedSameSequence() {
        var a: SeededRNG = SeededRNG(seed: 42)
        var b: SeededRNG = SeededRNG(seed: 42)
        for _ in 0..<50 { XCTAssertEqual(a.next(), b.next()) }
    }

    func testDifferentSeedsDiffer() {
        var a: SeededRNG = SeededRNG(seed: 1)
        var b: SeededRNG = SeededRNG(seed: 2)
        var same: Int = 0
        for _ in 0..<20 {
            let x: UInt64 = a.next()
            let y: UInt64 = b.next()
            if x == y { same += 1 }
        }
        XCTAssertLessThan(same, 2)
    }

    func testSaltChangesStreamButIsStable() {
        var a: SeededRNG = SeededRNG(seed: 7, salt: "x")
        var b: SeededRNG = SeededRNG(seed: 7, salt: "x")
        var c: SeededRNG = SeededRNG(seed: 7, salt: "y")
        var d: SeededRNG = SeededRNG(seed: 7, salt: "x")
        XCTAssertEqual(a.next(), b.next())
        XCTAssertNotEqual(d.next(), c.next())
        XCTAssertEqual(SeededRNG.stableHash("abc"), SeededRNG.stableHash("abc"))
        XCTAssertNotEqual(SeededRNG.stableHash("abc"), SeededRNG.stableHash("abd"))
    }

    func testIntBelowStaysInRange() {
        var rng: SeededRNG = SeededRNG(seed: 99)
        for n in 1..<20 {
            for _ in 0..<50 {
                let v: Int = rng.int(below: n)
                XCTAssertTrue(v >= 0 && v < n)
            }
        }
        XCTAssertEqual(rng.int(below: 0), 0)
    }

    func testShuffleIsAPermutationAndDeterministic() {
        let items: [Int] = Array(0..<30)
        var a: SeededRNG = SeededRNG(seed: 5)
        var b: SeededRNG = SeededRNG(seed: 5)
        let s1: [Int] = a.shuffled(items)
        let s2: [Int] = b.shuffled(items)
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1.sorted(), items)
        XCTAssertNotEqual(s1, items)
    }

    func testPickAndSample() {
        var rng: SeededRNG = SeededRNG(seed: 3)
        XCTAssertNil(rng.pick([Int]()))
        XCTAssertNotNil(rng.pick([1, 2, 3]))
        let s: [Int] = rng.sample([1, 2, 3, 4, 5], 3)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(Set(s).count, 3)
        XCTAssertEqual(rng.sample([1, 2], 5).count, 2)
    }
}
