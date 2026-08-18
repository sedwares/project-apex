//
//  EngineeringIDs.swift
//  ProjectApexCore
//
//  Stable identifiers for the 8 categories and 24 options.
//
//  Both IDs are String-backed enums. Because RawValue == String, they
//  conform to CodingKeyRepresentable, so a [EngineeringCategoryID:
//  EngineeringOptionID] dictionary encodes as a keyed JSON object
//  ("engineMode": "enginePower") instead of Codable's flat-array fallback.
//  That keeps Firestore documents readable and queryable.
//
//  RAW VALUES ARE WIRE FORMAT. They appear in canonical setup encodings,
//  result hashes, and stored leaderboard entries. Never rename a raw value
//  after launch; add new cases instead.
//

public nonisolated enum EngineeringCategoryID: String, Codable, CaseIterable, Sendable, Comparable {
    case engineMode
    case tires
    case aerodynamics
    case suspension
    case gearRatio
    case cooling
    case brakes
    case reliabilityFocus

    /// Canonical ordering = raw-value lexicographic order.
    /// Used by CanonicalSetupEncoder; must be deterministic forever.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Display name for UI. Localization happens in the app layer.
    public var displayName: String {
        switch self {
        case .engineMode: return "Engine Mode"
        case .tires: return "Tires"
        case .aerodynamics: return "Aerodynamics"
        case .suspension: return "Suspension"
        case .gearRatio: return "Gear Ratio"
        case .cooling: return "Cooling"
        case .brakes: return "Brakes"
        case .reliabilityFocus: return "Reliability Focus"
        }
    }
}

public nonisolated enum EngineeringOptionID: String, Codable, CaseIterable, Sendable {
    // Engine Mode
    case engineEfficient
    case engineBalanced
    case enginePower
    // Tires
    case tiresHard
    case tiresMedium
    case tiresSoft
    // Aerodynamics
    case aeroLowDrag
    case aeroBalanced
    case aeroHighDownforce
    // Suspension
    case suspensionSoft
    case suspensionBalanced
    case suspensionStiff
    // Gear Ratio
    case gearShort
    case gearBalanced
    case gearLong
    // Cooling
    case coolingLight
    case coolingStandard
    case coolingHeavy
    // Brakes
    case brakesConservative
    case brakesBalanced
    case brakesAggressive
    // Reliability Focus
    case reliabilityRisky
    case reliabilityBalanced
    case reliabilitySafe
}
