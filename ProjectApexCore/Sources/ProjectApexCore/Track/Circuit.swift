//
//  Circuit.swift
//  ProjectApexCore
//
//  Circuit model: an ordered list of track sections grouped into three
//  sectors. Per-section base times live here (balance data — tune
//  alongside OptionLibrary).
//

public nonisolated enum CircuitArchetype: String, Codable, CaseIterable, Sendable {
    case highSpeed
    case technical
    case street
    case mountain
    case balanced

    public var displayName: String {
        switch self {
        case .highSpeed: return "High-Speed Circuit"
        case .technical: return "Technical Circuit"
        case .street: return "Street Circuit"
        case .mountain: return "Mountain Circuit"
        case .balanced: return "Balanced Circuit"
        }
    }
}

extension TrackSectionType {
    /// Neutral base time in milliseconds for a baseline (1000-perf) car.
    /// Balance data — part of the Phase 0 sheet.
    public var baseTimeMillis: Int {
        switch self {
        case .longStraight: return 12_000
        case .shortStraight: return 7_000
        case .heavyBrakingZone: return 6_000
        case .hairpin: return 8_000
        case .slowCorner: return 7_500
        case .mediumCorner: return 7_000
        case .fastCorner: return 6_500
        case .technicalSector: return 9_000
        case .elevationClimb: return 8_000
        case .elevationDrop: return 6_500
        case .bumpySector: return 7_500
        case .finalStraight: return 10_000
        }
    }
}

public nonisolated struct Circuit: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let archetype: CircuitArchetype
    /// Ordered sections, lap start to lap finish.
    public let sections: [TrackSectionType]

    public init(id: String, name: String, archetype: CircuitArchetype, sections: [TrackSectionType]) {
        precondition(sections.count >= 3, "a circuit needs at least 3 sections")
        self.id = id
        self.name = name
        self.archetype = archetype
        self.sections = sections
    }

    /// Splits sections into 3 sectors, front-loading remainders
    /// (12 → 4/4/4, 10 → 4/3/3). Deterministic.
    public var sectorRanges: [Range<Int>] {
        let n = sections.count
        let base = n / 3
        let remainder = n % 3
        var ranges: [Range<Int>] = []
        var start = 0
        for i in 0..<3 {
            let size = base + (i < remainder ? 1 : 0)
            ranges.append(start..<(start + size))
            start += size
        }
        return ranges
    }

    /// Neutral lap time: sum of section base times (perf exactly 1000).
    public var baselineLapMillis: Int {
        sections.map(\.baseTimeMillis).reduce(0, +)
    }

    // MARK: - Demand profile

    /// Which stats actually decide THIS circuit, in basis points of the
    /// lap, strongest first.
    ///
    /// Weighted by section base time, not section count: a Long Straight
    /// occupies 12 s of a ~95 s lap and a Heavy Braking Zone 6 s, so the
    /// straight's demands are worth twice as much to the lap even though
    /// each section contributes one entry.
    ///
    /// This exists because the build screen was lying by omission. The
    /// player-facing Vehicle Profile showed five axes while the
    /// simulation runs on twelve — braking carries 4,500 bp in a Heavy
    /// Braking Zone and acceleration 4,000 bp in a Short Straight, and
    /// neither appeared anywhere in the UI. On a street circuit the
    /// player was building against an axis the app never showed them.
    ///
    /// Ties break on StatKey order so the result is stable.
    public var statDemandBP: [(key: StatKey, shareBP: Int)] {
        var weighted: [StatKey: Int] = [:]
        for section in sections {
            let sectionMillis = section.baseTimeMillis
            for (key, weightBP) in section.demandWeightsBP {
                weighted[key, default: 0] += weightBP * sectionMillis
            }
        }
        let total = weighted.values.reduce(0, +)
        guard total > 0 else { return [] }
        return weighted
            .map { (key: $0.key, shareBP: $0.value * FixedPoint.basisPointScale / total) }
            .sorted { lhs, rhs in
                lhs.shareBP != rhs.shareBP ? lhs.shareBP > rhs.shareBP : lhs.key < rhs.key
            }
    }

    /// The stats worth showing the player before they build, strongest
    /// first. Four is the honest number: on every generated circuit the
    /// top four cover 55–70% of the lap's demand, and a fifth axis adds
    /// noise rather than information.
    public func decidingStats(limit: Int = 4) -> [(key: StatKey, shareBP: Int)] {
        Array(statDemandBP.prefix(limit))
    }

    /// Hand-built balanced circuit used by tests and early prototypes.
    /// Baseline lap: 95_000 ms (1:35.000).
    public static let reference = Circuit(
        id: "circuit-reference-001",
        name: "Reference Ring",
        archetype: .balanced,
        sections: [
            .longStraight,      // 12_000
            .mediumCorner,      //  7_000
            .heavyBrakingZone,  //  6_000
            .hairpin,           //  8_000
            .shortStraight,     //  7_000
            .fastCorner,        //  6_500
            .technicalSector,   //  9_000
            .elevationClimb,    //  8_000
            .elevationDrop,     //  6_500
            .bumpySector,       //  7_500
            .slowCorner,        //  7_500
            .finalStraight      // 10_000
        ]
    )
}

// MARK: - Composition

extension Circuit {
    /// See `Sequence.compositionSummary(limit:)`. Sugar so views can say
    /// `circuit.compositionSummary()` beside the bar strip.
    public func compositionSummary(limit: Int = 3) -> String {
        sections.compositionSummary(limit: limit)
    }
}
