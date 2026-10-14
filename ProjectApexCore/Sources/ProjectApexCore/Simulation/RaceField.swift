//
//  RaceField.swift
//  ProjectApexCore
//
//  The other cars in the replay, and where every car is at any moment.
//
//  ── WHY ────────────────────────────────────────────────────────────
//  The replay was one car on an empty circuit, so it read as a chart
//  rather than a race. Players asked to "feel the race". The race is
//  against DESIGN PHILOSOPHIES, not drivers: five fixed rival builds —
//  Low Drag, High Downforce, Endurance, Balanced, All Attack — run
//  through the same deterministic simulation on today's circuit. "You
//  beat the Downforce car but lost to Low Drag" is a lesson about the
//  track, delivered as a result.
//
//  ── HONESTY ────────────────────────────────────────────────────────
//  · Rivals obey the same rules as the player: today's budget and
//    today's regulation. A template that does not fit is trimmed,
//    deterministically, by stepping its dearest system down.
//  · Rivals are NOT the solver's answer and never reveal it. They are
//    fixed templates; their setups are never shown, only their names.
//  · ORDER IS EXACT, SPACING IS NOT. Real gaps over a 3-lap race are
//    1–3% of the distance — on a phone screen every car would sit on
//    top of every other. So each car's distance from the field average
//    is magnified by one common factor. A single positive factor
//    applied to every car preserves the order at every sector line and
//    at the flag, so positions, overtakes and the result are true; only
//    the gaps are drawn larger. The classification uses real times.
//

public nonisolated struct RaceEntrant: Sendable, Equatable {
    public let id: String
    public let name: String
    public let isPlayer: Bool
    public let result: SimulationResult

    public init(id: String, name: String, isPlayer: Bool, result: SimulationResult) {
        self.id = id
        self.name = name
        self.isPlayer = isPlayer
        self.result = result
    }

    /// Ranking key, same as the leaderboard: average lap.
    public var averageLapMillis: Int { result.averageLapTimeMillis }
}

public nonisolated enum RivalField {

    /// The five philosophies, in a fixed order.
    static let templates: [(id: String, name: String, picks: [EngineeringCategoryID: EngineeringOptionID])] = [
        ("low-drag", "Low Drag", [
            .engineMode: .enginePower, .tires: .tiresMedium, .aerodynamics: .aeroLowDrag,
            .suspension: .suspensionBalanced, .gearRatio: .gearLong, .cooling: .coolingStandard,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityBalanced
        ]),
        ("downforce", "High Downforce", [
            .engineMode: .engineBalanced, .tires: .tiresSoft, .aerodynamics: .aeroHighDownforce,
            .suspension: .suspensionStiff, .gearRatio: .gearShort, .cooling: .coolingStandard,
            .brakes: .brakesAggressive, .reliabilityFocus: .reliabilityBalanced
        ]),
        ("endurance", "Endurance", [
            .engineMode: .engineEfficient, .tires: .tiresHard, .aerodynamics: .aeroBalanced,
            .suspension: .suspensionSoft, .gearRatio: .gearBalanced, .cooling: .coolingHeavy,
            .brakes: .brakesConservative, .reliabilityFocus: .reliabilitySafe
        ]),
        ("balanced", "Balanced", [
            .engineMode: .engineBalanced, .tires: .tiresMedium, .aerodynamics: .aeroBalanced,
            .suspension: .suspensionBalanced, .gearRatio: .gearBalanced, .cooling: .coolingStandard,
            .brakes: .brakesBalanced, .reliabilityFocus: .reliabilityBalanced
        ]),
        ("all-attack", "All Attack", [
            .engineMode: .enginePower, .tires: .tiresSoft, .aerodynamics: .aeroBalanced,
            .suspension: .suspensionStiff, .gearRatio: .gearShort, .cooling: .coolingLight,
            .brakes: .brakesAggressive, .reliabilityFocus: .reliabilityRisky
        ])
    ]

    /// The five rivals for this challenge, simulated. Deterministic.
    public static func rivals(for challenge: DailyChallenge) -> [RaceEntrant] {
        templates.map { template in
            let picks = legalize(template.picks, budget: challenge.budget, banned: challenge.bannedOption)
            let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: picks)
            let result = SimulationEngine.simulate(
                setup: setup, circuit: challenge.circuit, weather: challenge.weather
            )
            return RaceEntrant(id: template.id, name: template.name, isPlayer: false, result: result)
        }
    }

    /// Fit a template to today's rules. A banned pick moves to the
    /// cheaper neighbour if there is one, else the dearer. While over
    /// budget, the dearest system steps down one option (ties broken by
    /// category order). Cheap and fully deterministic.
    static func legalize(
        _ picks: [EngineeringCategoryID: EngineeringOptionID],
        budget: Int,
        banned: EngineeringOptionID?
    ) -> [EngineeringCategoryID: EngineeringOptionID] {
        var picks = picks
        func ordered(_ c: EngineeringCategoryID) -> [EngineeringOption] {
            OptionLibrary.options(in: c).sorted { $0.cost < $1.cost }
        }
        if let banned {
            for c in EngineeringCategoryID.allCases.sorted() where picks[c] == banned {
                let options = ordered(c)
                let i = options.firstIndex { $0.id == banned } ?? 0
                let fallback = (i > 0 ? options[i - 1] : options[min(i + 1, options.count - 1)]).id
                picks[c] = fallback
            }
        }
        func cost() -> Int { picks.values.reduce(0) { $0 + OptionLibrary.option($1).cost } }
        var guardCount = 0
        while cost() > budget, guardCount < 32 {
            guardCount += 1
            // Dearest step-down available.
            var best: (category: EngineeringCategoryID, to: EngineeringOptionID, saving: Int)?
            for c in EngineeringCategoryID.allCases.sorted() {
                guard let current = picks[c] else { continue }
                let options = ordered(c).filter { $0.id != banned }
                guard let i = options.firstIndex(where: { $0.id == current }), i > 0 else { continue }
                let saving = OptionLibrary.option(current).cost - options[i - 1].cost
                if best == nil || saving > best!.saving {
                    best = (c, options[i - 1].id, saving)
                }
            }
            guard let step = best else { break }
            picks[step.category] = step.to
        }
        return picks
    }
}

// MARK: - Where everyone is

public nonisolated struct RaceTimeline: Sendable {

    public let entrants: [RaceEntrant]
    public let laps: Int
    /// Sectors per lap (the sim's coarse three).
    public let sectorsPerLap: Int
    /// The common magnification applied to every car's gap. ≥ 1.
    public let gapScale: Double

    /// Per entrant, the VISUAL clock (ms) at which each sector line is
    /// crossed. Index 0 is the start (0); the last is the flag.
    private let lines: [[Double]]

    public init(entrants: [RaceEntrant], targetSpreadOfLap: Double = 0.3) {
        self.entrants = entrants
        let laps = entrants.map { $0.result.lapResults.count }.min() ?? 0
        self.laps = laps
        self.sectorsPerLap = 3

        // True crossing times.
        let real: [[Double]] = entrants.map { e in
            var t = 0.0
            var out = [0.0]
            for lap in e.result.lapResults.prefix(laps) {
                for s in lap.sectorTimesMillis.prefix(3) {
                    t += Double(s)
                    out.append(t)
                }
            }
            return out
        }
        let count = real.map(\.count).min() ?? 1
        let n = Double(max(entrants.count, 1))
        let mean: [Double] = (0..<count).map { k in real.reduce(0) { $0 + $1[k] } / n }

        // One factor for everyone. Aim the biggest gap from the average
        // at `targetSpreadOfLap` of a lap; never shrink a gap (≥1); cap
        // so an all-but-tied field is not blown apart.
        let finish = count - 1
        let spread = real.map { abs($0[finish] - mean[finish]) }.max() ?? 0
        let lapLength = laps > 0 ? mean[finish] / Double(laps) : 1
        var scale = spread > 0 ? min(14, max(1, targetSpreadOfLap * lapLength / spread)) : 1

        // Every car must still move FORWARD through every sector.
        func visual(_ s: Double) -> [[Double]] {
            real.map { r in (0..<count).map { k in mean[k] + s * (r[k] - mean[k]) } }
        }
        var v = visual(scale)
        while scale > 1, v.contains(where: { line in
            zip(line, line.dropFirst()).contains { $1 - $0 <= 0 }
        }) {
            scale = max(1, scale * 0.8)
            v = visual(scale)
        }
        self.gapScale = scale
        self.lines = v
    }

    /// Visual clock at which the given entrant takes the flag.
    public func finishClock(of index: Int) -> Double { lines[index].last ?? 0 }

    /// When the last car finishes.
    public var lastFinishClock: Double { lines.map { $0.last ?? 0 }.max() ?? 0 }

    /// Progress in SECTORS (0 … laps×3) for an entrant at a visual
    /// clock, linear within each sector. Clamped at the flag.
    public func sectorProgress(of index: Int, at clock: Double) -> Double {
        let line = lines[index]
        guard let last = line.last, clock < last else { return Double(line.count - 1) }
        guard clock > 0 else { return 0 }
        for k in 0..<(line.count - 1) where clock < line[k + 1] {
            let span = line[k + 1] - line[k]
            return Double(k) + (span > 0 ? (clock - line[k]) / span : 0)
        }
        return Double(line.count - 1)
    }

    /// Visual duration of each of an entrant's laps.
    public func lapDurations(of index: Int) -> [Double] {
        let line = lines[index]
        return (0..<laps).map { lap in
            let a = lap * sectorsPerLap, b = a + sectorsPerLap
            guard b < line.count else { return 0 }
            return line[b] - line[a]
        }
    }

    /// Running order at a visual clock: indices into `entrants`, leader
    /// first. Finished cars rank by when they finished; the rest by
    /// distance covered. Ties break on entrant order, so it is stable.
    public func order(at clock: Double) -> [Int] {
        entrants.indices.sorted { a, b in
            let fa = finishClock(of: a), fb = finishClock(of: b)
            let doneA = clock >= fa, doneB = clock >= fb
            if doneA && doneB { return fa != fb ? fa < fb : a < b }
            if doneA != doneB { return doneA }
            let pa = sectorProgress(of: a, at: clock), pb = sectorProgress(of: b, at: clock)
            return pa != pb ? pa > pb : a < b
        }
    }

    /// The final classification by REAL average lap time.
    public var classification: [Int] {
        entrants.indices.sorted { a, b in
            let ta = entrants[a].averageLapMillis, tb = entrants[b].averageLapMillis
            return ta != tb ? ta < tb : a < b
        }
    }
}
