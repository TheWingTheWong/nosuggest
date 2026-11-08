import Foundation

public enum Stats {
    /// Wilson score interval for a binomial proportion. Behaves sensibly at
    /// 0 and n successes, unlike the normal approximation.
    public static func wilson(successes k: Int, trials n: Int, z: Double = 1.96) -> (low: Double, high: Double) {
        guard n > 0 else { return (0, 1) }
        let p = Double(k) / Double(n)
        let z2 = z * z
        let denom = 1 + z2 / Double(n)
        let centre = (p + z2 / (2 * Double(n))) / denom
        let half = z * ((p * (1 - p) / Double(n) + z2 / (4 * Double(n) * Double(n))).squareRoot()) / denom
        return (max(0, centre - half), min(1, centre + half))
    }

    /// Deterministic 64-bit PRNG (SplitMix64) so samples are reproducible
    /// across machines and Swift versions.
    public struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        public init(seed: UInt64) { state = seed }
        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
