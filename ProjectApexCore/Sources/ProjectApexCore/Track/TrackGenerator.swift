//
//  TrackGenerator.swift
//  ProjectApexCore
//
//  Seeded circuit generation from archetype-weighted section pools.
//  Duplicated entries in a pool = higher draw probability. Every
//  generated circuit ends with a Final Straight (start/finish line).
//  11–13 sections per circuit.
//

public nonisolated enum TrackGenerator {

    /// Weighted section pools per archetype (duplicates = weight).
    static func pool(for archetype: CircuitArchetype) -> [TrackSectionType] {
        switch archetype {
        case .highSpeed:
            return [.longStraight, .longStraight, .shortStraight, .shortStraight,
                    .fastCorner, .fastCorner, .mediumCorner, .mediumCorner,
                    .heavyBrakingZone, .hairpin]
        case .technical:
            return [.technicalSector, .technicalSector, .slowCorner, .slowCorner,
                    .hairpin, .mediumCorner, .mediumCorner, .shortStraight,
                    .longStraight, .fastCorner]
        case .street:
            return [.heavyBrakingZone, .heavyBrakingZone, .shortStraight, .shortStraight,
                    .slowCorner, .slowCorner, .bumpySector, .bumpySector,
                    .hairpin, .mediumCorner]
        case .mountain:
            return [.elevationClimb, .elevationClimb, .elevationDrop, .elevationDrop,
                    .technicalSector, .bumpySector, .longStraight, .mediumCorner,
                    .fastCorner, .shortStraight]
        case .balanced:
            return [.longStraight, .shortStraight, .heavyBrakingZone, .hairpin,
                    .slowCorner, .mediumCorner, .fastCorner, .technicalSector,
                    .elevationClimb, .elevationDrop, .bumpySector]
        }
    }

    /// Deterministically generates a circuit for an archetype.
    public static func generate(
        archetype: CircuitArchetype,
        id: String,
        name: String,
        rng: inout SplitMix64
    ) -> Circuit {
        let sectionPool = pool(for: archetype)
        let sectionCount = 11 + rng.next(upperBound: 3) // 11...13 incl. final straight

        var sections: [TrackSectionType] = []
        for _ in 0..<(sectionCount - 1) {
            sections.append(rng.pick(sectionPool))
        }
        sections.append(.finalStraight)

        return Circuit(id: id, name: name, archetype: archetype, sections: sections)
    }
}
