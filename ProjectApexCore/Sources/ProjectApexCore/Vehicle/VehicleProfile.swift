//
//  VehicleProfile.swift
//  ProjectApexCore
//
//  The showroom view of a setup: player-facing axes, no numbers,
//  weather-free (this is the car you BUILT; the race shows what the
//  conditions did to it).
//
//  PASS 6: the profile is now CIRCUIT-RELATIVE. The fixed five axes
//  (Top Speed, Cornering, Stability, Tire Life, Reliability) omitted
//  seven of the twelve stats the simulation actually runs on —
//  including braking, acceleration, power, cooling and weight, which
//  between them decide most circuits. A player on a street circuit was
//  building against demands the app never displayed.
//
//  `from(setup:circuit:)` shows the four stats that decide TODAY, in
//  demand order, each carrying its share of the lap. Same data the
//  simulation uses, surfaced instead of hidden — which also teaches the
//  model by playing it.
//
//  The fixed-axis `from(setup:)` is kept for the Test Lab and for any
//  context with no circuit in hand.
//

public nonisolated struct VehicleProfile: Sendable, Equatable {

    public struct Axis: Sendable, Equatable {
        public let name: String
        /// 0...1 for display bars.
        public let fraction: Double
        /// Share of this circuit's total demand, in basis points.
        /// nil for the circuit-free profile.
        public let demandShareBP: Int?
        /// True when the underlying stat is one where lower is better
        /// (weight, heat) and `fraction` has already been inverted, so
        /// a full bar always reads as "good".
        public let isInvertedStat: Bool

        public init(
            name: String,
            fraction: Double,
            demandShareBP: Int? = nil,
            isInvertedStat: Bool = false
        ) {
            self.name = name
            self.fraction = fraction
            self.demandShareBP = demandShareBP
            self.isInvertedStat = isInvertedStat
        }

        /// "18% of this lap" — the subtitle that makes the axis mean
        /// something. nil for the circuit-free profile.
        public var demandText: String? {
            guard let demandShareBP else { return nil }
            return "\(demandShareBP / 100)% of this lap"
        }
    }

    public let axes: [Axis]

    // MARK: - Shared stat math

    /// Base 1000 + the selected options' stat effects, matching
    /// VehicleBuilder, pre-weather. Partial setups are fine —
    /// unselected categories simply contribute nothing.
    static func totals(for setup: PlayerSetup) -> [StatKey: Int] {
        var totals: [StatKey: Int] = [:]
        for optionID in setup.selectedOptions.values {
            for (key, value) in OptionLibrary.option(optionID).statEffects {
                totals[key, default: 0] += value
            }
        }
        var stats: [StatKey: Int] = [:]
        for key in StatKey.allCases {
            stats[key] = FixedPoint.statBaseline + (totals[key] ?? 0)
        }
        return stats
    }

    /// Display normalization: option sums realistically span ~±250, so
    /// 750...1250 maps to an empty...full bar. Inverted stats are
    /// flipped so a full bar always means "this is good for you".
    static func fraction(_ value: Int, inverted: Bool) -> Double {
        let f = (Double(value) - 750.0) / 500.0
        let clamped = min(1.0, max(0.0, f))
        return inverted ? 1.0 - clamped : clamped
    }

    // MARK: - Circuit-relative (preferred)

    /// The four stats that decide this circuit, in demand order.
    public static func from(setup: PlayerSetup, circuit: Circuit, axisCount: Int = 4) -> VehicleProfile {
        let stats = totals(for: setup)
        let axes = circuit.decidingStats(limit: axisCount).map { entry -> Axis in
            Axis(
                name: entry.key.friendlyName,
                fraction: fraction(stats[entry.key] ?? FixedPoint.statBaseline,
                                   inverted: entry.key.isInverted),
                demandShareBP: entry.shareBP,
                isInvertedStat: entry.key.isInverted
            )
        }
        return VehicleProfile(axes: axes)
    }

    // MARK: - Fixed axes (circuit-free contexts)

    public static func from(setup: PlayerSetup) -> VehicleProfile {
        let stats = totals(for: setup)
        func axis(_ name: String, _ key: StatKey) -> Axis {
            Axis(
                name: name,
                fraction: fraction(stats[key] ?? FixedPoint.statBaseline, inverted: key.isInverted),
                demandShareBP: nil,
                isInvertedStat: key.isInverted
            )
        }
        return VehicleProfile(axes: [
            axis("Top Speed", .topSpeed),
            axis("Cornering", .grip),
            axis("Stability", .stability),
            axis("Tire Life", .tireDurability),
            axis("Reliability", .reliability)
        ])
    }
}
