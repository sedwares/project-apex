//
//  SetupIdentity.swift
//  ProjectApexCore
//
//  Plain-language summary of a built vehicle ("High Speed / Heat Risk").
//  Thresholds come from Balance Sheet §7. Max 3 tags, fixed priority
//  order, deterministic. "Balanced" only when nothing else fires.
//

public nonisolated enum IdentityTag: String, Codable, CaseIterable, Sendable {
    case highSpeed
    case cornerFocused
    case tireFriendly
    case stable
    case reliable
    case heatRisk
    case fragile
    case balanced

    public var displayName: String {
        switch self {
        case .highSpeed: return "High Speed"
        case .cornerFocused: return "Corner Focused"
        case .tireFriendly: return "Tire Friendly"
        case .stable: return "Stable"
        case .reliable: return "Reliable"
        case .heatRisk: return "Heat Risk"
        case .fragile: return "Fragile"
        case .balanced: return "Balanced"
        }
    }
}

public nonisolated struct SetupIdentity: Codable, Hashable, Sendable {
    /// 1–3 tags in fixed priority order.
    public let tags: [IdentityTag]

    /// "High Speed / Heat Risk" — the debrief and share-text form.
    public var displayText: String {
        tags.map(\.displayName).joined(separator: " / ")
    }

    /// Priority order for tag selection (first three that fire win).
    private static let priorityOrder: [IdentityTag] = [
        .highSpeed, .cornerFocused, .tireFriendly, .stable,
        .reliable, .heatRisk, .fragile
    ]

    private static let maxTags = 3

    public static func derive(from stats: VehicleStats) -> SetupIdentity {
        var fired: [IdentityTag] = []

        for tag in priorityOrder {
            let fires: Bool
            switch tag {
            case .highSpeed:      fires = stats.topSpeed >= 1150
            case .cornerFocused:  fires = stats.grip >= 1120
            case .tireFriendly:   fires = stats.tireDurability >= 1120
            case .stable:         fires = stats.stability >= 1100
            case .reliable:       fires = stats.reliability >= 1120
            case .heatRisk:       fires = stats.heatGeneration >= 1150
            case .fragile:        fires = stats.reliability <= 860
            case .balanced:       fires = false
            }
            if fires {
                fired.append(tag)
                if fired.count == maxTags { break }
            }
        }

        if fired.isEmpty {
            fired = [.balanced]
        }
        return SetupIdentity(tags: fired)
    }
}
