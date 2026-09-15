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

// MARK: - Families

/// The coarse grouping a player actually thinks in when choosing parts:
/// is this lap mostly flat out, mostly braking, or mostly turning?
///
/// It exists so the UI's circuit bar strip and the sentence printed under
/// it describe ONE taxonomy. The strip used to group `hairpin` with
/// braking zones purely because both looked like caution; a hairpin's
/// demand is grip and acceleration first, so it belongs with the corners
/// and now sits there.
public nonisolated enum TrackSectionFamily: String, CaseIterable, Sendable {
    case straight
    case braking
    case corner
    case elevation
    case bumpy

    public var singular: String {
        switch self {
        case .straight:  return "straight"
        case .braking:   return "braking zone"
        case .corner:    return "corner"
        case .elevation: return "elevation change"
        case .bumpy:     return "bumpy sector"
        }
    }

    public var plural: String {
        switch self {
        case .straight:  return "straights"
        case .braking:   return "braking zones"
        case .corner:    return "corners"
        case .elevation: return "elevation changes"
        case .bumpy:     return "bumpy sectors"
        }
    }
}

extension TrackSectionType {
    public var family: TrackSectionFamily {
        switch self {
        case .longStraight, .shortStraight, .finalStraight:
            return .straight
        case .heavyBrakingZone:
            return .braking
        case .hairpin, .slowCorner, .mediumCorner, .fastCorner, .technicalSector:
            return .corner
        case .elevationClimb, .elevationDrop:
            return .elevation
        case .bumpySector:
            return .bumpy
        }
    }
}

extension Sequence where Element == TrackSectionType {
    /// Families present, most common first. Ties break on
    /// `TrackSectionFamily.allCases` order, so one circuit always yields
    /// one sentence.
    public var composition: [(family: TrackSectionFamily, count: Int)] {
        var counts: [TrackSectionFamily: Int] = [:]
        for section in self { counts[section.family, default: 0] += 1 }
        return TrackSectionFamily.allCases
            .enumerated()
            .compactMap { order, family in
                counts[family].map { (order: order, family: family, count: $0) }
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.order < $1.order }
            .map { (family: $0.family, count: $0.count) }
    }

    /// What this circuit is made of, in the words a player would use:
    /// "4 corners · 3 straights · 2 braking zones".
    ///
    /// The bar strip in the UI cannot explain itself — no row of eleven
    /// rectangles can, and the person who designed it still had to ask
    /// what it meant. This is the line that decodes it, and the bars are
    /// coloured by the families it names.
    public func compositionSummary(limit: Int = 3) -> String {
        composition.prefix(limit)
            .map { "\($0.count) \($0.count == 1 ? $0.family.singular : $0.family.plural)" }
            .joined(separator: " · ")
    }
}
