//
//  OptionEffectSummary.swift
//  ProjectApexCore
//
//  Trade-off directions for option rows (design doc §7): the biggest
//  upside and biggest downside of an option, as words, no numbers.
//  "Positive" respects stat semantics: more heat and more weight are
//  downsides even though their deltas are positive numbers.
//

public nonisolated enum OptionEffectSummary {

    /// Stats where a positive delta hurts you.
    private static let negativeIsGood: Set<StatKey> = [.heatGeneration, .weight]

    /// Label sign shows the stat's DIRECTION; the UI colors goodness.
    /// Efficient engine → upside "−Heat" (less heat, shown green).
    /// Power engine → downside "+Heat" (more heat, shown orange).
    public static func topUpside(of option: EngineeringOption) -> String? {
        best(of: option, wantGood: true).map(label(for:))
    }

    public static func topDownside(of option: EngineeringOption) -> String? {
        best(of: option, wantGood: false).map(label(for:))
    }

    private static func label(for entry: (key: StatKey, value: Int)) -> String {
        "\(entry.value > 0 ? "+" : "−")\(entry.key.friendlyName)"
    }

    private static func best(of option: EngineeringOption, wantGood: Bool) -> (key: StatKey, value: Int)? {
        option.statEffects
            .filter { key, value in
                let helps = negativeIsGood.contains(key) ? value < 0 : value > 0
                return helps == wantGood && value != 0
            }
            .max { abs($0.value) < abs($1.value) }
            .map { (key: $0.key, value: $0.value) }
    }
}

public extension EngineeringOption {
    /// Member-style conveniences — both call styles are supported:
    /// `option.topUpside` and `OptionEffectSummary.topUpside(of:)`.
    var topUpside: String? { OptionEffectSummary.topUpside(of: self) }
    var topDownside: String? { OptionEffectSummary.topDownside(of: self) }
}

public extension StatKey {
    /// Player-facing stat names for captions and reports.
    var friendlyName: String {
        switch self {
        case .power: return "Power"
        case .acceleration: return "Acceleration"
        case .topSpeed: return "Top Speed"
        case .grip: return "Corner Grip"
        case .stability: return "Stability"
        case .braking: return "Braking"
        case .tireDurability: return "Tire Life"
        case .heatGeneration: return "Heat"
        case .cooling: return "Cooling"
        case .reliability: return "Reliability"
        case .weight: return "Weight"
        case .aeroEfficiency: return "Aero Efficiency"
        }
    }
}
