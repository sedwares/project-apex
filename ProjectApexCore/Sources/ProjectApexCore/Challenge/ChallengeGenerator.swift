//
//  ChallengeGenerator.swift
//  ProjectApexCore
//
//  Deterministic daily challenge generation. Same day number → same
//  challenge, always. In production this runs in the backend publishing
//  job; on device it powers Test Session and validation tooling.
//

public nonisolated enum ChallengeGenerator {

    /// Budget range for daily challenges (reference budget 100 ± 8).
    public static let budgetRange = 92...108

    /// Options eligible to be banned, in raw-value order.
    ///
    /// Deliberately NOT `allCases` order: raw values are wire format and
    /// new cases get appended, which would silently reshuffle every
    /// future day's regulation. Sorting by raw value means adding an
    /// option only shifts days after the point it sorts into, and the
    /// publishing job's stored documents remain the source of truth
    /// regardless.
    static let bannableOptions: [EngineeringOptionID] =
        EngineeringOptionID.allCases.sorted { $0.rawValue < $1.rawValue }

    /// Generates the challenge for a UTC dateKey ("yyyy-MM-dd").
    /// Returns nil for a malformed dateKey.
    public static func generate(dateKey: String, nonce: Int = 0) -> DailyChallenge? {
        guard let dayNumber = ChallengeSeed.dayNumber(fromDateKey: dateKey) else { return nil }
        return generate(dayNumber: dayNumber, dateKey: dateKey, nonce: nonce)
    }

    /// Core generator keyed by day number. dateKey is carried through
    /// for identifiers; validation batches may use synthetic keys.
    ///
    /// `nonce` re-rolls a day that failed the validation gate. 0 is the
    /// canonical draw. The nonce that was actually published must be
    /// recorded alongside the document — a re-rolled day cannot be
    /// reconstructed from its date alone, which is exactly why the
    /// client fetches challenges instead of generating them
    /// (Decision 4), and why the yesterday reveal must read the cached
    /// official document rather than regenerate.
    public static func generate(dayNumber: Int, dateKey: String, nonce: Int = 0) -> DailyChallenge {
        var rng = ChallengeSeed.rng(forDayNumber: dayNumber, nonce: nonce)

        let archetype = rng.pick(CircuitArchetype.allCases)
        let weather = rng.pick(Weather.allCases)
        let budget = budgetRange.lowerBound
            + rng.next(upperBound: budgetRange.count)

        let circuit = TrackGenerator.generate(
            archetype: archetype,
            id: "circuit-\(dateKey)",
            name: "\(archetype.displayName) — Day \(dayNumber)",
            rng: &rng
        )

        // The day's technical regulation is drawn LAST, deliberately:
        // every draw before this point consumes the same RNG sequence
        // it did before pass 6, so a given day keeps the circuit,
        // weather and budget it always had. Only the regulation is new.
        //
        // Re-draw if the ban would price the day out of its own budget
        // (banning the cheapest option in a category raises the floor).
        // The loop is bounded in practice — most bans don't move the
        // floor at all — but the guard keeps it total.
        var banned = rng.pick(bannableOptions)
        var attempts = 0
        while OptionLibrary.minimumTotalCost(banned: banned) > budget, attempts < 32 {
            banned = rng.pick(bannableOptions)
            attempts += 1
        }
        let regulation: EngineeringOptionID? =
            OptionLibrary.minimumTotalCost(banned: banned) <= budget ? banned : nil

        return DailyChallenge(
            id: "apex-\(dateKey)",
            dateKey: dateKey,
            seed: UInt64(bitPattern: Int64(dayNumber)),
            circuit: circuit,
            weather: weather,
            budget: budget,
            simulationVersion: ResultHasher.simulationVersion,
            bannedOption: regulation
        )
    }
}
