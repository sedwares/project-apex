//
//  ChallengeSeed.swift
//  ProjectApexCore
//
//  Deterministic seeding for daily challenges.
//  - SplitMix64: the portfolio-standard PRNG (same as BottleCode/Gridway).
//  - Day numbering: Day 1 = 2026-01-01 (UTC dateKey), computed with the
//    civil-calendar algorithm — no Foundation, no Calendar, no time zones.
//

/// SplitMix64 PRNG. Deterministic, fast, no Foundation.
public nonisolated struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform-ish value in 0..<upperBound (modulo; bias negligible for
    /// gameplay-sized bounds).
    public mutating func next(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    /// Picks one element deterministically.
    public mutating func pick<T>(_ array: [T]) -> T {
        array[next(upperBound: array.count)]
    }
}

public nonisolated enum ChallengeSeed {

    /// Day 1 of Project Apex = 2026-01-01 (UTC).
    public static let epochDateKey = "2026-01-01"

    /// Days since 1970-01-01 for a civil date (Howard Hinnant's
    /// days_from_civil). Pure integer math, valid across the Gregorian
    /// calendar, no Foundation.
    public static func daysSinceUnixEpoch(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Parses a "yyyy-MM-dd" UTC dateKey. Returns nil if malformed.
    public static func parse(dateKey: String) -> (year: Int, month: Int, day: Int)? {
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }

    /// Day number for a dateKey. Day 1 = 2026-01-01. Nil if malformed.
    public static func dayNumber(fromDateKey dateKey: String) -> Int? {
        guard let date = parse(dateKey: dateKey),
              let epoch = parse(dateKey: epochDateKey)
        else { return nil }
        let days = daysSinceUnixEpoch(year: date.year, month: date.month, day: date.day)
        let epochDays = daysSinceUnixEpoch(year: epoch.year, month: epoch.month, day: epoch.day)
        return days - epochDays + 1
    }

    /// Root RNG for a given day.
    ///
    /// `nonce` re-rolls a day that failed the validation gate. Nonce 0
    /// reproduces the original seed exactly, so every already-published
    /// day is untouched by the addition of this parameter. Non-zero
    /// nonces are mixed with the golden-ratio constant so consecutive
    /// re-rolls land far apart in the sequence rather than adjacent.
    public static func rng(forDayNumber dayNumber: Int, nonce: Int = 0) -> SplitMix64 {
        let base = UInt64(bitPattern: Int64(dayNumber))
        guard nonce != 0 else { return SplitMix64(seed: base) }
        let mixed = base ^ (UInt64(bitPattern: Int64(nonce)) &* 0x9E3779B97F4A7C15)
        return SplitMix64(seed: mixed)
    }
}
