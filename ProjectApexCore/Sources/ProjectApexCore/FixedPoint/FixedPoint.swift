//
//  FixedPoint.swift
//  ProjectApexCore
//
//  Normative fixed-point math for the entire simulation.
//  NO Double or Float anywhere in the simulation path.
//  NO Foundation — pure Swift, deterministic on every platform.
//
//  Conventions (see Balance Sheet §1):
//  - Stats: millipoints. Baseline 1000 = 1.0.
//  - Time: integer milliseconds.
//  - Modifiers: basis points. 10_000 = no change.
//
//  NORMATIVE ROUNDING RULE:
//  Every modifier application is (value * modifier) / 10_000 using Int
//  division, which truncates toward zero. This rule must never vary —
//  result hashes and cross-platform re-simulation depend on it.
//

public nonisolated enum FixedPoint {

    /// Basis-point denominator. A modifier of 10_000 leaves the value unchanged.
    public static let basisPointScale: Int = 10_000

    /// Millipoint baseline for all vehicle stats (1000 = 1.0).
    public static let statBaseline: Int = 1_000

    /// The one and only modifier application in the codebase.
    /// (value * modifier) / 10_000, Int division, truncation toward zero.
    @inlinable
    public static func applyBasisPoints(_ value: Int, _ modifierBP: Int) -> Int {
        (value * modifierBP) / basisPointScale
    }

    /// Applies a sequence of basis-point modifiers in order.
    /// Order matters under truncation, so callers must pass modifiers
    /// in a documented, stable order.
    @inlinable
    public static func applyBasisPoints(_ value: Int, sequence modifiersBP: [Int]) -> Int {
        var v = value
        for m in modifiersBP {
            v = applyBasisPoints(v, m)
        }
        return v
    }

    /// Clamps a stat so degradation can never push it below zero.
    @inlinable
    public static func clampStat(_ value: Int) -> Int {
        max(0, value)
    }

    /// Formats integer milliseconds as "M:SS.mmm" for the display layer.
    /// Pure Swift (no Foundation), locale-independent.
    /// Display-only: never feed formatted values back into simulation.
    public static func formatLapTime(millis: Int) -> String {
        let clamped = max(0, millis)
        let minutes = clamped / 60_000
        let seconds = (clamped % 60_000) / 1_000
        let thousandths = clamped % 1_000
        return "\(minutes):\(padded(seconds, width: 2)).\(padded(thousandths, width: 3))"
    }

    /// Zero-pads a non-negative integer to the given width.
    private static func padded(_ value: Int, width: Int) -> String {
        let raw = String(value)
        let missing = width - raw.count
        return missing > 0 ? String(repeating: "0", count: missing) + raw : raw
    }
}
