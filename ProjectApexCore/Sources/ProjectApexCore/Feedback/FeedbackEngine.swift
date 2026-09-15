//
//  FeedbackEngine.swift
//  ProjectApexCore
//
//  The rule-based Race Engineer (NOT a chatbot — design doc §24).
//  Converts simulation events + sector gaps + conditions into a
//  structured debrief: strengths, weaknesses, one recommendation.
//
//  Deterministic: same result + conditions → same words, always.
//  Decoupled from DailyChallenge so Test Session / Quick Race reuse it.
//
//  PASS 6: the recommendation is now computed by SetupAdvisor whenever
//  the caller can supply the challenge, instead of being prescribed
//  from the leading event. See SetupAdvisor for the measurements that
//  forced the change. The event-only path below is retained for
//  contexts with no challenge in hand, and is documented as the
//  weaker one.
//

public nonisolated struct EngineerFeedback: Codable, Hashable, Sendable {
    public let strengths: [String]
    public let weaknesses: [String]
    /// Exactly one actionable line, priority-ordered by biggest problem.
    public let recommendation: String

    /// The debrief as one Chief Engineer paragraph — top strength, top
    /// weakness, then the recommendation.
    ///
    /// Single implementation: this used to exist twice, here and as
    /// FeedbackEngine.reportText(for:), and the two had drifted (only
    /// one had the empty-strengths fallback). This is the version with
    /// the fallback; the static one now delegates here.
    public var reportText: String {
        var sentences: [String] = [observationText]
        sentences.append(recommendation)
        return sentences.joined(separator: " ")
    }

    /// Strength and weakness only, with the recommendation left out.
    ///
    /// Use this wherever the UI ALSO renders the recommendation as its
    /// own affordance. The debrief shipped briefly with the prose ending
    /// "Next test: Aerodynamics to Low Drag, funded by dropping Gear
    /// Ratio…" and then a card immediately beneath repeating all three
    /// facts. The prose should carry the reading of the race; the card
    /// carries the action.
    public var observationText: String {
        var sentences: [String] = []
        sentences.append(strengths.first ?? "A quiet, tidy run — nothing broke, nothing shone.")
        if let weakness = weaknesses.first { sentences.append(weakness) }
        return sentences.joined(separator: " ")
    }
}

public nonisolated enum FeedbackEngine {

    /// The pre-race Chief Engineer briefing — archetype character plus a
    /// weather warning, and the day's technical regulation when there is
    /// one. Same flavor for everyone on a given day (it derives only
    /// from public conditions).
    public static func preRaceBriefing(
        archetype: CircuitArchetype,
        weather: Weather,
        regulation: EngineeringOptionID? = nil
    ) -> String {
        let circuitLine: String
        switch archetype {
        case .highSpeed:
            circuitLine = "Long straights dominate today — top speed and gearing decide it."
        case .technical:
            circuitLine = "Corner after corner. Grip and stability carry the lap."
        case .street:
            circuitLine = "Street circuits reward precision under braking."
        case .mountain:
            circuitLine = "Climbs and drops — cooling, weight, and brakes all earn their credits."
        case .balanced:
            circuitLine = "A bit of everything. Budget allocation decides today."
        }
        let weatherLine: String
        switch weather {
        case .sunny: weatherLine = "Clear conditions — pure setup racing."
        case .hot: weatherLine = "Heat will punish aggressive engines on Lap 3."
        case .cold: weatherLine = "Cold start — expect a slow warm-up lap."
        case .rain: weatherLine = "Rain cuts grip everywhere; stability pays."
        case .windy: weatherLine = "Wind taxes unstable cars through the fast corners."
        }
        var lines = [circuitLine, weatherLine]
        if let regulation {
            let option = OptionLibrary.option(regulation)
            lines.append(
                "Stewards have outlawed \(option.displayName) \(option.category.displayName) for this event."
            )
        }
        lines.append("Multiple competitive solutions exist.")
        return lines.joined(separator: " ")
    }

    // MARK: - Generation

    /// Preferred entry point: the challenge is available, so the
    /// recommendation is the genuinely fastest change rather than a
    /// symptom-driven guess.
    ///
    /// - Parameter optimalSectorTotalsMillis: from DayAnalysis, once the
    ///   exhaustive solve completes. When supplied, the sector strength
    ///   and weakness lines are measured against the OPTIMAL car instead
    ///   of the neutral one. This matters more than it sounds: against
    ///   the neutral car no sector gap is ever positive, so the weakness
    ///   line could never fire and the debrief never told a player what
    ///   went wrong. Nil falls back to the neutral comparison.
    public static func generate(
        result: SimulationResult,
        challenge: DailyChallenge,
        optimalSectorTotalsMillis: [Int]? = nil
    ) -> EngineerFeedback {
        let weather = challenge.weather
        let archetype = challenge.circuit.archetype
        let advice = SetupAdvisor.bestAdvice(
            for: result.setup,
            challenge: challenge,
            leadingEvent: leadingEvent(in: result)
        )
        let lost = sectorsLostToOptimal(
            result: result, optimalSectorTotalsMillis: optimalSectorTotalsMillis
        )
        return EngineerFeedback(
            strengths: strengths(result: result, lostToOptimal: lost),
            weaknesses: weaknesses(result: result, weather: weather, lostToOptimal: lost),
            recommendation: advice?.text
                ?? cleanRunRecommendation(archetype: archetype, exhaustive: true)
        )
    }

    /// Per-sector, PER-LAP milliseconds versus the optimal setup.
    /// Negative means you were quicker there than the optimal car.
    /// nil when the solve hasn't finished.
    ///
    /// Two things this gets right that the first version didn't:
    ///
    /// 1. NO CLAMPING. The original did `max(0, …)` on the claim that
    ///    "nothing beats the optimum". That's false. The optimal setup
    ///    minimises the AVERAGE LAP, not every sector — a different car
    ///    can be quicker through one sector and lose more elsewhere.
    ///    Clamping labelled those sectors "optimal" when the player had
    ///    actually beaten the optimal car, and it broke the arithmetic.
    ///
    /// 2. PER LAP, not per run. SectorResult.totalMillis sums all three
    ///    laps, so the raw difference sits on a different scale from
    ///    `gapToOptimalMillis`, which is a per-lap average. Shown side
    ///    by side that read as a contradiction: a +0.831s gap next to a
    ///    sector claiming +3.737s.
    ///
    /// With both fixed, these three numbers SUM TO THE GAP (to within a
    /// millisecond of integer truncation). That's the property that makes
    /// the chart checkable by anyone who cares to add it up — and this
    /// game's whole promise is that the numbers never lie.
    ///
    /// `public` because the app layer needs it too — the debrief's sector
    /// chart renders the same numbers the feedback prose describes, and
    /// they must not be computed two different ways.
    public static func sectorsLostToOptimal(
        result: SimulationResult,
        optimalSectorTotalsMillis: [Int]?
    ) -> [Int]? {
        guard let optimal = optimalSectorTotalsMillis,
              optimal.count == result.sectorResults.count,
              !result.lapResults.isEmpty
        else { return nil }
        let laps = result.lapResults.count
        return result.sectorResults.enumerated().map { index, sector in
            (sector.totalMillis - optimal[index]) / laps
        }
    }

    /// Total time given up, ignoring sectors where the player was ahead.
    /// The denominator for "x% of everything you gave up".
    static func totalGivenUp(_ deltas: [Int]) -> Int {
        deltas.filter { $0 > 0 }.reduce(0, +)
    }

    /// Event-only fallback for contexts with no challenge in hand.
    ///
    /// Weaker by design: with no circuit and no budget it cannot know
    /// which change is actually fastest, so it describes the problem
    /// rather than prescribing a cure. Prefer `generate(result:challenge:)`.
    public static func generate(
        result: SimulationResult,
        weather: Weather,
        archetype: CircuitArchetype
    ) -> EngineerFeedback {
        EngineerFeedback(
            strengths: strengths(result: result),
            weaknesses: weaknesses(result: result, weather: weather),
            recommendation: recommendation(result: result, weather: weather, archetype: archetype)
        )
    }

    /// The event that most explains the lap time, in the same priority
    /// order the debrief uses. nil on a clean run.
    public static func leadingEvent(in result: SimulationResult) -> SimulationEvent? {
        let priority: [SimulationEvent] = [
            .engineHeatHigh, .tireWearHigh, .reliabilityConcern, .cornerStabilityWeak
        ]
        return priority.first { result.events.contains($0) }
    }

    // MARK: - Engineer radio (simulation replay)

    /// A timed radio message during the replay ceremony.
    public struct RadioMessage: Sendable, Equatable {
        /// 1-based lap the message belongs to.
        public let lap: Int
        /// When within the lap it fires (0...1 of lap progress).
        public let atFraction: Double
        public let text: String
    }

    /// Deterministic radio feed derived from the actual result — the
    /// engineer never says anything the telemetry can't back up.
    public static func radioMessages(
        for result: SimulationResult,
        weather: Weather
    ) -> [RadioMessage] {
        var feed: [RadioMessage] = []
        let events = result.events

        // Lap 1: warm-up talk.
        feed.append(RadioMessage(
            lap: 1, atFraction: 0.15,
            text: weather == .cold
                ? "Cold track. Long warm-up — take care."
                : "Tires coming in. Build the rhythm."
        ))

        // Lap 2: peak pace + the car's genuine strength.
        feed.append(RadioMessage(lap: 2, atFraction: 0.1, text: "Peak pace. Push now."))
        if events.contains(.straightLineSpeedStrong) {
            feed.append(RadioMessage(lap: 2, atFraction: 0.55, text: "Strong on the straights."))
        } else if events.contains(.gripStrong) {
            feed.append(RadioMessage(lap: 2, atFraction: 0.55, text: "Good grip through the corners."))
        } else if events.contains(.brakingPerformanceStrong) {
            feed.append(RadioMessage(lap: 2, atFraction: 0.55, text: "Braking is working for us."))
        } else if let best = result.sectorResults.min(by: { $0.gapMillis < $1.gapMillis }),
                  best.gapMillis < 0 {
            feed.append(RadioMessage(lap: 2, atFraction: 0.55, text: "We're quick in Sector \(best.index + 1)."))
        }

        // Lap 3: decay truth.
        if events.contains(.tireWearHigh) {
            feed.append(RadioMessage(lap: 3, atFraction: 0.3, text: "Rear tires going off."))
        }
        if events.contains(.engineHeatHigh) {
            feed.append(RadioMessage(lap: 3, atFraction: 0.5, text: "Temps climbing — power's fading."))
        }
        if events.contains(.reliabilityConcern) {
            feed.append(RadioMessage(lap: 3, atFraction: 0.7, text: "Reliability flag. Nurse it home."))
        }
        let decay: Set<SimulationEvent> = [.tireWearHigh, .engineHeatHigh, .reliabilityConcern]
        if events.allSatisfy({ !decay.contains($0) }) {
            feed.append(RadioMessage(lap: 3, atFraction: 0.4, text: "Car's holding together. Bring it home."))
        }
        return feed
    }

    // MARK: - Prose report (debrief)

    /// Retained for callers that pass the struct around; delegates to
    /// EngineerFeedback.reportText so there is one implementation.
    public static func reportText(for feedback: EngineerFeedback) -> String {
        feedback.reportText
    }

    // MARK: - Strengths

    static func strengths(result: SimulationResult, lostToOptimal: [Int]? = nil) -> [String] {
        var lines: [String] = []
        let events = result.events

        if events.contains(.straightLineSpeedStrong) {
            lines.append("Strong straight-line speed — the car flew down the straights.")
        }
        if events.contains(.gripStrong) {
            lines.append("Excellent mechanical grip through the corners.")
        }
        if events.contains(.brakingPerformanceStrong) {
            lines.append("Braking was a clear strength into the heavy zones.")
        }

        if let lost = lostToOptimal,
           let best = lost.indices.min(by: { lost[$0] < lost[$1] }) {
            // Measured against the optimal car, so "strongest" means
            // closest to perfect rather than "beat a car with no parts".
            // And beating it outright is now sayable, which is the best
            // sentence this engine can produce.
            let tier = SectorTier.of(deltaMillis: lost[best])
            switch tier {
            case .ahead:
                lines.append("Sector \(best + 1) beat the optimal car — \(formatGap(-lost[best])) quicker through there.")
            case .optimal:
                lines.append("Sector \(best + 1) was perfect — you matched the optimal car there.")
            default:
                // Ask the tier itself whether this is sayable as praise,
                // rather than re-listing the bad cases here. Restating
                // them was a second copy of the boundary that SectorTier
                // exists to own — the exact drift that let the prose and
                // the debrief chart contradict each other in the first
                // place.
                if tier.isCreditable {
                    lines.append("Sector \(best + 1) was your strongest — only \(formatGap(lost[best])) off the optimal car.")
                } else {
                    // The best sector on the lap is STILL off the pace, so
                    // "your strongest" would be praise the lap has not
                    // earned — and it used to print directly above a red
                    // WEAK label carrying the identical number. Say what is
                    // actually true: it held up best, and the lap was poor.
                    lines.append("Sector \(best + 1) held up best, but the whole lap was off the pace — \(formatGap(lost[best])) down there alone.")
                }
            }
        } else if let best = result.sectorResults.min(by: { $0.gapMillis < $1.gapMillis }),
                  best.gapMillis < 0 {
            lines.append("Sector \(best.index + 1) was your strongest — \(formatGap(-best.gapMillis)) quicker than the neutral car.")
        }

        // Consistency: Lap 3 held within 0.6s of peak with no decay events.
        let decayEvents: Set<SimulationEvent> = [.engineHeatHigh, .tireWearHigh, .reliabilityConcern]
        if result.lapResults.count == 3,
           events.allSatisfy({ !decayEvents.contains($0) }),
           result.lapResults[2].timeMillis - result.lapResults[1].timeMillis < 600 {
            lines.append("The car held together — Lap 3 barely dropped off from peak pace.")
        }
        return lines
    }

    // MARK: - Weaknesses

    static func weaknesses(
        result: SimulationResult,
        weather: Weather,
        lostToOptimal: [Int]? = nil
    ) -> [String] {
        var lines: [String] = []
        let events = result.events

        if events.contains(.engineHeatHigh) {
            lines.append(weather == .hot
                ? "The engine overheated — the hot conditions compounded your heat generation on Lap 3."
                : "Cooling couldn't match heat generation — power faded on Lap 3.")
        }
        if events.contains(.tireWearHigh) {
            lines.append(weather == .hot
                ? "Tire degradation bit hard in the heat, costing grip late in the run."
                : "Heavy tire degradation cost grip in the final lap.")
        }
        if events.contains(.reliabilityConcern) {
            lines.append("Reliability issues added raw time on the final lap.")
        }
        if events.contains(.cornerStabilityWeak) {
            lines.append(weather == .windy
                ? "Low stability hurt badly in the wind through the fast corners."
                : "Weak stability cost time through the fast corners.")
        }

        // Worst sector. Against the optimal car this always has
        // something to say once the gap is non-zero — which is the
        // point: the neutral-car version could never fire, so the
        // debrief had no way to name what went wrong.
        if let lost = lostToOptimal,
           let worst = lost.indices.max(by: { lost[$0] < lost[$1] }),
           lost[worst] > 0 {
            let share = totalGivenUp(lost) > 0 ? lost[worst] * 100 / totalGivenUp(lost) : 0
            lines.append("Sector \(worst + 1) is where the lap went — \(formatGap(lost[worst])) behind the optimal car, \(share)% of everything you gave up.")
        } else if let worst = result.sectorResults.max(by: { $0.gapMillis < $1.gapMillis }),
                  worst.gapMillis > 0 {
            lines.append("Sector \(worst.index + 1) cost you \(formatGap(worst.gapMillis)) against the neutral car.")
        }
        return lines
    }


    // MARK: - Next Test suggestion

    /// A single category/option swap matching the recommendation.
    ///
    /// - Warning: this is the pass-5 behaviour and it is measurably
    ///   poor advice — across 472 event-firing setups it made the car
    ///   slower 592 times versus faster 330, and was over budget a
    ///   further 225 times. It is kept only so existing tests and any
    ///   caller without a DailyChallenge still compile.
    ///   Use `SetupAdvisor.bestAdvice(for:challenge:)`.
    @available(*, deprecated, message: "Symptom-driven and usually wrong. Use SetupAdvisor.bestAdvice(for:challenge:), which searches the feasible changes.")
    public static func nextTestSuggestion(
        for result: SimulationResult
    ) -> (category: EngineeringCategoryID, option: EngineeringOptionID, label: String)? {
        let events = result.events
        if events.contains(.engineHeatHigh) {
            return (.cooling, .coolingHeavy, "Try Heavy Cooling")
        }
        if events.contains(.tireWearHigh) {
            return (.tires, .tiresHard, "Try Hard tires")
        }
        if events.contains(.reliabilityConcern) {
            return (.reliabilityFocus, .reliabilitySafe, "Try Safe reliability")
        }
        if events.contains(.cornerStabilityWeak) {
            return (.suspension, .suspensionStiff, "Try Stiff suspension")
        }
        return nil
    }

    // MARK: - Recommendation (event-only fallback)

    static func recommendation(
        result: SimulationResult,
        weather: Weather,
        archetype: CircuitArchetype
    ) -> String {
        let events = result.events

        if events.contains(.engineHeatHigh) {
            return weather == .hot
                ? "On hot days the heat tax is quadratic — cooling capacity or a calmer engine has to come from somewhere in the budget."
                : "Heat is eating Lap 3. Cooling capacity or a calmer engine mode, paid for elsewhere."
        }
        if events.contains(.tireWearHigh) {
            return "The tires are the limit late in the run — a harder compound trades peak grip for a stronger average, if this circuit lets you."
        }
        if events.contains(.reliabilityConcern) {
            return "Reliability is bleeding raw time, and the penalty steepens fast the further under you go."
        }
        if events.contains(.cornerStabilityWeak) {
            return weather == .windy
                ? "Windy circuits reward stability — stiffer suspension or more downforce would settle it."
                : "Stiffer suspension or higher downforce would settle the fast corners."
        }
        return cleanRunRecommendation(archetype: archetype, exhaustive: false)
    }

    /// Clean-run flavour. `exhaustive` means the advisor searched every
    /// feasible change and found nothing worth doing — a much stronger
    /// statement than "no events fired", and worth saying out loud.
    static func cleanRunRecommendation(archetype: CircuitArchetype, exhaustive: Bool) -> String {
        let lead = exhaustive
            ? "No single change to this setup makes it faster within the budget — that's a well-solved day."
            : "Clean run."
        switch archetype {
        case .mountain:
            return "\(lead) On mountain circuits every kilogram and cooling point matters — refine there."
        case .highSpeed:
            return "\(lead) High-speed circuits reward top-end — squeeze the gear ratio and aero balance."
        case .technical:
            return "\(lead) Technical circuits live on grip and stability — refine the corner package."
        case .street:
            return "\(lead) Street circuits are won under braking — sharpen that end of the car."
        case .balanced:
            return "\(lead) On balanced circuits the edge comes from budget allocation — spend smarter, not more."
        }
    }

    // MARK: - Helpers

    private static func formatGap(_ millis: Int) -> String {
        let a = abs(millis)
        return "\(a / 1000).\(pad3(a % 1000))s"
    }

    private static func pad3(_ value: Int) -> String {
        let raw = String(value)
        return String(repeating: "0", count: max(0, 3 - raw.count)) + raw
    }
}
