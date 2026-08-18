//
//  VehicleStats.swift
//  ProjectApexCore
//
//  The 12 hidden vehicle stats, fixed-point millipoints (baseline 1000).
//  Named struct per the design doc, plus StatKey subscript access so the
//  simulation and section-demand math can iterate stats generically.
//

public nonisolated enum StatKey: String, Codable, CaseIterable, Sendable, Comparable {
    case power
    case acceleration
    case topSpeed
    case grip
    case braking
    case stability
    case cooling
    case reliability
    case tireDurability
    case weight
    case aeroEfficiency
    case heatGeneration

    /// Inverted stats: lower is better. The simulation must account
    /// for this when scoring section demands.
    public var isInverted: Bool {
        switch self {
        case .weight, .heatGeneration: return true
        default: return false
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public nonisolated struct VehicleStats: Codable, Hashable, Sendable {
    public var power: Int
    public var acceleration: Int
    public var topSpeed: Int
    public var grip: Int
    public var braking: Int
    public var stability: Int
    public var cooling: Int
    public var reliability: Int
    public var tireDurability: Int
    public var weight: Int
    public var aeroEfficiency: Int
    public var heatGeneration: Int

    /// All twelve stats at the fixed-point baseline (1000 = 1.0).
    public static let baseline = VehicleStats(uniform: FixedPoint.statBaseline)

    public init(uniform value: Int) {
        power = value; acceleration = value; topSpeed = value; grip = value
        braking = value; stability = value; cooling = value; reliability = value
        tireDurability = value; weight = value; aeroEfficiency = value
        heatGeneration = value
    }

    public init(
        power: Int, acceleration: Int, topSpeed: Int, grip: Int,
        braking: Int, stability: Int, cooling: Int, reliability: Int,
        tireDurability: Int, weight: Int, aeroEfficiency: Int, heatGeneration: Int
    ) {
        self.power = power; self.acceleration = acceleration
        self.topSpeed = topSpeed; self.grip = grip
        self.braking = braking; self.stability = stability
        self.cooling = cooling; self.reliability = reliability
        self.tireDurability = tireDurability; self.weight = weight
        self.aeroEfficiency = aeroEfficiency; self.heatGeneration = heatGeneration
    }

    public subscript(key: StatKey) -> Int {
        get {
            switch key {
            case .power: return power
            case .acceleration: return acceleration
            case .topSpeed: return topSpeed
            case .grip: return grip
            case .braking: return braking
            case .stability: return stability
            case .cooling: return cooling
            case .reliability: return reliability
            case .tireDurability: return tireDurability
            case .weight: return weight
            case .aeroEfficiency: return aeroEfficiency
            case .heatGeneration: return heatGeneration
            }
        }
        set {
            switch key {
            case .power: power = newValue
            case .acceleration: acceleration = newValue
            case .topSpeed: topSpeed = newValue
            case .grip: grip = newValue
            case .braking: braking = newValue
            case .stability: stability = newValue
            case .cooling: cooling = newValue
            case .reliability: reliability = newValue
            case .tireDurability: tireDurability = newValue
            case .weight: weight = newValue
            case .aeroEfficiency: aeroEfficiency = newValue
            case .heatGeneration: heatGeneration = newValue
            }
        }
    }
}
