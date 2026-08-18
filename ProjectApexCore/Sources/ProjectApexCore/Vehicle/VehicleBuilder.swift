//
//  VehicleBuilder.swift
//  ProjectApexCore
//
//  Converts a validated PlayerSetup into VehicleStats.
//  Pure additive model: baseline 1000 per stat + sum of option deltas,
//  clamped at zero. Deterministic by construction — iteration order is
//  fixed via sorted categories even though addition commutes, so the
//  code stays deterministic if the model ever becomes order-sensitive.
//

public nonisolated enum VehicleBuilder {

    public static func build(from setup: PlayerSetup) -> VehicleStats {
        var stats = VehicleStats.baseline

        for (_, optionID) in setup.selectedOptions.sorted(by: { $0.key < $1.key }) {
            let option = OptionLibrary.option(optionID)
            for key in StatKey.allCases.sorted() {
                if let delta = option.statEffects[key] {
                    stats[key] = FixedPoint.clampStat(stats[key] + delta)
                }
            }
        }
        return stats
    }
}
