//
//  SetupAdvisor.swift
//  ProjectApexCore
//
//  The engineer's "next test" — computed, not prescribed.
//
//  ── WHY THIS EXISTS ────────────────────────────────────────────────
//  FeedbackEngine.nextTestSuggestion used to map each simulation event
//  to one fixed swap: heat → Heavy Cooling, wear → Hard tires,
//  reliability → Safe, stability → Stiff. Measured over 472
//  event-firing setups across 30 days, taking that advice made the car
//  SLOWER 592 times and faster only 330 (mean +583 ms), and was over
//  budget — not even applicable — a further 225 times. It ranked a
//  median 9th of ~15 feasible single swaps, while a better swap existed
//  95% of the time.
//
//  The cause was structural: the fix was prescribed from the SYMPTOM
//  without consulting the circuit or the budget. Heavy Cooling costs 7
//  more credits than Light and adds 70 weight, which is a real penalty
//  on a mountain circuit where weight carries 3,000 bp. Hard tires
//  trade 40 grip for wear protection the circuit may not care about.
//
//  So: compute it. Evaluating every feasible single swap and every
//  funded two-swap is at most 128 simulations — roughly 5,000 section
//  calculations, microseconds — and it makes the engineer credible.
//
//  ── WHY TWO-SWAPS MATTER ───────────────────────────────────────────
//  From random legal starts, single-swap hill climbing reaches the true
//  optimum only ~2% of the time and lands a mean 1.3 s off, because the
//  budget binds: improving one system usually requires downgrading
//  another to pay for it. Recommending an upgrade without naming its
//  funding source teaches the wrong mental model. When the best change
//  is a pair, the advice says what to give up.
//
//  Deterministic by construction: fixed iteration order, integer math,
//  ties broken by canonical encoding. Same result → same words, always.
//

public nonisolated struct EngineerAdvice: Sendable, Equatable {

    public struct Change: Sendable, Equatable {
        public let category: EngineeringCategoryID
        public let from: EngineeringOptionID
        public let to: EngineeringOptionID

        public var costDelta: Int {
            OptionLibrary.option(to).cost - OptionLibrary.option(from).cost
        }
    }

    /// The change that buys the time. When `funding` is non-nil this is
    /// the more expensive half of the pair.
    public let upgrade: Change
    /// What to give up to afford the upgrade. nil when the upgrade fits
    /// the budget on its own.
    public let funding: Change?
    /// Time saved versus the setup that was actually raced, in ms.
    /// Always > 0 — no-gain advice is not returned.
    public let gainMillis: Int
    /// The full setup the advice produces, ready to pre-load into the
    /// Experiment sandbox.
    public let resultingSelections: [EngineeringCategoryID: EngineeringOptionID]
    /// One deterministic sentence for the debrief.
    public let text: String

    /// Both changes, upgrade first, for UI that lists them.
    public var changes: [Change] {
        funding.map { [upgrade, $0] } ?? [upgrade]
    }
}

public nonisolated enum SetupAdvisor {

    /// Gains smaller than this aren't worth a recommendation — they read
    /// as noise to a player and would make the engineer sound fussy.
    static let minimumWorthwhileGainMillis = 25

    /// The best change available to this setup under today's budget and
    /// regulation, or nil if nothing meaningful improves it.
    ///
    /// Searches every feasible one- and two-category change: at most
    /// 16 + 112 = 128 simulations. Cheap enough for the main thread,
    /// but the caller may hop it off if it prefers.
    public static func bestAdvice(
        for setup: PlayerSetup,
        challenge: DailyChallenge,
        leadingEvent: SimulationEvent? = nil
    ) -> EngineerAdvice? {
        let categories = EngineeringCategoryID.allCases.sorted()
        let current = setup.selectedOptions

        // Every category must be filled for the advice to be meaningful.
        guard current.count == categories.count else { return nil }

        let baseline = SimulationEngine.averageLapMillis(
            setup: setup, circuit: challenge.circuit, weather: challenge.weather
        )

        struct Candidate {
            let changes: [EngineerAdvice.Change]
            let selections: [EngineeringCategoryID: EngineeringOptionID]
            let gain: Int
            let encoding: String
        }
        var best: Candidate?

        func consider(_ changes: [EngineerAdvice.Change]) {
            var selections = current
            var cost = 0
            for change in changes { selections[change.category] = change.to }
            for optionID in selections.values { cost += OptionLibrary.option(optionID).cost }
            guard cost <= challenge.budget else { return }

            let candidateSetup = PlayerSetup(
                challengeId: setup.challengeId, selectedOptions: selections
            )
            let time = SimulationEngine.averageLapMillis(
                setup: candidateSetup, circuit: challenge.circuit, weather: challenge.weather
            )
            let gain = baseline - time
            guard gain >= minimumWorthwhileGainMillis else { return }

            let encoding = CanonicalSetupEncoder.encode(candidateSetup)
            // Prefer more gain; then fewer changes (simpler advice is
            // better advice); then canonical encoding so ties are stable.
            if let existing = best {
                if gain < existing.gain { return }
                if gain == existing.gain {
                    if changes.count > existing.changes.count { return }
                    if changes.count == existing.changes.count, encoding >= existing.encoding { return }
                }
            }
            best = Candidate(
                changes: changes, selections: selections, gain: gain, encoding: encoding
            )
        }

        // Single changes, in fixed order.
        for category in categories {
            guard let from = current[category] else { continue }
            for option in OptionLibrary.options(in: category, banned: challenge.bannedOption)
            where option.id != from {
                consider([EngineerAdvice.Change(category: category, from: from, to: option.id)])
            }
        }

        // Two-category changes: the upgrade plus whatever pays for it.
        for (i, first) in categories.enumerated() {
            guard let firstFrom = current[first] else { continue }
            for second in categories[(i + 1)...] {
                guard let secondFrom = current[second] else { continue }
                for a in OptionLibrary.options(in: first, banned: challenge.bannedOption)
                where a.id != firstFrom {
                    for b in OptionLibrary.options(in: second, banned: challenge.bannedOption)
                    where b.id != secondFrom {
                        consider([
                            EngineerAdvice.Change(category: first, from: firstFrom, to: a.id),
                            EngineerAdvice.Change(category: second, from: secondFrom, to: b.id)
                        ])
                    }
                }
            }
        }

        guard let winner = best else { return nil }

        // The upgrade is the change that costs more; the other funds it.
        let ordered = winner.changes.sorted { lhs, rhs in
            if lhs.costDelta != rhs.costDelta { return lhs.costDelta > rhs.costDelta }
            return lhs.category < rhs.category
        }
        let upgrade = ordered[0]
        let funding = ordered.count > 1 ? ordered[1] : nil

        return EngineerAdvice(
            upgrade: upgrade,
            funding: funding,
            gainMillis: winner.gain,
            resultingSelections: winner.selections,
            text: prose(
                upgrade: upgrade, funding: funding,
                gainMillis: winner.gain, leadingEvent: leadingEvent
            )
        )
    }

    // MARK: - Prose

    /// The event explains WHY the car was slow; the computed change is
    /// WHAT to do about it. Keeping those separate is the whole point —
    /// the old engine let the symptom dictate the cure.
    static func prose(
        upgrade: EngineerAdvice.Change,
        funding: EngineerAdvice.Change?,
        gainMillis: Int,
        leadingEvent: SimulationEvent?
    ) -> String {
        var sentence = ""

        if let leadingEvent {
            switch leadingEvent {
            case .engineHeatHigh:
                sentence += "Temps ran away on Lap 3, but more cooling isn't the cheapest cure here. "
            case .tireWearHigh:
                sentence += "The tires went off late, and the fix isn't simply a harder compound. "
            case .reliabilityConcern:
                sentence += "Reliability cost you raw time on the final lap. "
            case .cornerStabilityWeak:
                sentence += "The car was unsettled through the quick corners. "
            case .straightLineSpeedStrong, .brakingPerformanceStrong, .gripStrong:
                sentence += "The car had a real strength to build on. "
            }
        }

        let toName = OptionLibrary.option(upgrade.to).displayName
        let fromName = OptionLibrary.option(upgrade.from).displayName
        sentence += "Next test: \(upgrade.category.displayName) to \(toName), from \(fromName)"

        if let funding {
            let fundedName = OptionLibrary.option(funding.to).displayName
            sentence += ", funded by dropping \(funding.category.displayName) to \(fundedName)"
        }

        sentence += " — worth about \(formatSeconds(gainMillis)) on this circuit."
        return sentence
    }

    static func formatSeconds(_ millis: Int) -> String {
        let value = abs(millis)
        let whole = value / 1_000
        let fraction = value % 1_000
        var digits = String(fraction)
        while digits.count < 3 { digits = "0" + digits }
        return "\(whole).\(digits)s"
    }
}
