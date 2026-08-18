//
//  TrackSection.swift
//  ProjectApexCore
//
//  The 12 reusable track section types and their stat demand weights
//  (Balance Sheet §5). Weights are basis points summing to 10_000 per
//  section. Inverted stats (weight, heatGeneration) carry the inversion
//  in StatKey.isInverted — SimulationEngine (Phase 1) is responsible for
//  scoring them as "lower is better".
//
//  Full Circuit / CircuitArchetype / TrackGenerator models arrive in
//  Phase 1; the demand data is locked now because it's part of the
//  Phase 0 balance sheet.
//

public nonisolated enum TrackSectionType: String, Codable, CaseIterable, Sendable {
    case longStraight
    case shortStraight
    case heavyBrakingZone
    case hairpin
    case slowCorner
    case mediumCorner
    case fastCorner
    case technicalSector
    case elevationClimb
    case elevationDrop
    case bumpySector
    case finalStraight

    public var displayName: String {
        switch self {
        case .longStraight: return "Long Straight"
        case .shortStraight: return "Short Straight"
        case .heavyBrakingZone: return "Heavy Braking Zone"
        case .hairpin: return "Hairpin"
        case .slowCorner: return "Slow Corner"
        case .mediumCorner: return "Medium Corner"
        case .fastCorner: return "Fast Corner"
        case .technicalSector: return "Technical Sector"
        case .elevationClimb: return "Elevation Climb"
        case .elevationDrop: return "Elevation Drop"
        case .bumpySector: return "Bumpy Sector"
        case .finalStraight: return "Final Straight"
        }
    }

    /// Stat demand weights in basis points. Each section sums to 10_000.
    public var demandWeightsBP: [StatKey: Int] {
        switch self {
        case .longStraight:
            return [.topSpeed: 4_000, .power: 3_000, .aeroEfficiency: 3_000]
        case .shortStraight:
            return [.acceleration: 4_000, .power: 3_500, .topSpeed: 2_500]
        case .heavyBrakingZone:
            return [.braking: 4_500, .stability: 3_000, .tireDurability: 2_500]
        case .hairpin:
            return [.grip: 3_300, .acceleration: 3_500, .braking: 3_200]
        case .slowCorner:
            return [.grip: 3_600, .acceleration: 3_200, .stability: 3_200]
        case .mediumCorner:
            return [.grip: 3_700, .stability: 3_500, .aeroEfficiency: 2_800]
        case .fastCorner:
            return [.grip: 3_300, .stability: 3_500, .aeroEfficiency: 3_200]
        case .technicalSector:
            return [.grip: 3_200, .stability: 3_500, .braking: 3_300]
        case .elevationClimb:
            return [.power: 4_000, .cooling: 3_000, .weight: 3_000]
        case .elevationDrop:
            return [.braking: 4_000, .stability: 3_500, .grip: 2_500]
        case .bumpySector:
            return [.stability: 4_500, .grip: 3_000, .reliability: 2_500]
        case .finalStraight:
            return [.topSpeed: 4_500, .power: 3_000, .aeroEfficiency: 2_500]
        }
    }
}
