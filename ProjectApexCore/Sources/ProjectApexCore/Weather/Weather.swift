//
//  Weather.swift
//  ProjectApexCore
//
//  Weather types and their stat modifiers in basis points.
//  Values from Balance Sheet §6. Applied via FixedPoint.applyBasisPoints
//  in StatKey sorted order (normative — truncation makes order matter).
//
//  Note: Cold's extra Lap-1 warmup grip penalty is a lap-scoped effect
//  that lives in SimulationEngine (Phase 1), not here.
//

public nonisolated enum Weather: String, Codable, CaseIterable, Sendable {
    case sunny
    case hot
    case cold
    case rain
    case windy

    public var displayName: String {
        switch self {
        case .sunny: return "Sunny"
        case .hot: return "Hot"
        case .cold: return "Cold"
        case .rain: return "Rain"
        case .windy: return "Windy"
        }
    }

    /// Basis-point stat modifiers (absent key = 10_000, no change).
    public var statModifiersBP: [StatKey: Int] {
        switch self {
        case .sunny:
            return [:]
        case .hot:
            return [.heatGeneration: 11_500, .tireDurability: 9_200]
        case .cold:
            return [.grip: 9_400, .heatGeneration: 9_200]
        case .rain:
            return [.grip: 8_200, .braking: 9_000]
        case .windy:
            // Pass 5: softened (9200/9500 → 9400/9600). The harsher tax
            // made stability-hungry technical circuits lock aero+tires
            // in the top 1% — wind should matter, not railroad.
            return [.stability: 9_500, .aeroEfficiency: 9_600]
        }
    }

    /// Applies this weather's modifiers to vehicle stats.
    /// Iterates StatKey in sorted order for determinism.
    public func apply(to stats: VehicleStats) -> VehicleStats {
        var result = stats
        let modifiers = statModifiersBP
        for key in StatKey.allCases.sorted() {
            if let bp = modifiers[key] {
                result[key] = FixedPoint.clampStat(
                    FixedPoint.applyBasisPoints(result[key], bp)
                )
            }
        }
        return result
    }
}
