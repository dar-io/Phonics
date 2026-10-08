import Foundation

/// Deterministic SplitMix64 generator. The engine never uses system randomness: every
/// random choice comes from one of these so that equal seeds give equal results.
public struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    /// Derives an independent stream from a seed plus a text salt (stable across processes).
    public init(seed: UInt64, salt: String) {
        self.state = seed ^ SeededRNG.stableHash(salt)
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// FNV-1a over UTF-8. Unlike `hashValue` this is identical in every process.
    public static func stableHash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// Uniform-ish integer in 0..<n (returns 0 when n <= 1).
    public mutating func int(below n: Int) -> Int {
        if n <= 1 { return 0 }
        return Int(next() % UInt64(n))
    }

    public mutating func bool() -> Bool {
        return next() & 1 == 1
    }

    /// Returns a shuffled copy (Fisher-Yates).
    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        var a: [T] = array
        if a.count < 2 { return a }
        var i: Int = a.count - 1
        while i > 0 {
            let j: Int = int(below: i + 1)
            if i != j { a.swapAt(i, j) }
            i -= 1
        }
        return a
    }

    public mutating func pick<T>(_ array: [T]) -> T? {
        if array.isEmpty { return nil }
        return array[int(below: array.count)]
    }

    /// Up to `n` distinct elements (by position) in random order.
    public mutating func sample<T>(_ array: [T], _ n: Int) -> [T] {
        if n <= 0 { return [] }
        return Array(shuffled(array).prefix(n))
    }
}
