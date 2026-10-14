//
//  PitWallRemark.swift
//  ProjectApexCore
//
//  One line from the pit wall after every pick in the Engineering Bay.
//
//  ── WHY ────────────────────────────────────────────────────────────
//  Players said the idea was good but the Bay "doesn't feel like a
//  game". Making a choice changed a radio button and nothing answered.
//  A voice that reacts to each pick turns the form into a conversation
//  with someone who is watching you build.
//
//  ── THE ONE RULE: IT MAY NOT KNOW THE ANSWER ───────────────────────
//  The setup IS the puzzle. Every remark is built only from what the
//  player can already see on screen:
//
//    · the circuit's demand shares ("What decides today")
//    · the weather, and its stated effect
//    · the budget and what is left of it
//    · the option's own ± stat effects (its row captions)
//
//  It never calls the solver, the simulation, or SetupAdvisor, and it
//  never says "optimal", "best" or "right". It tells you what a pick
//  DOES against today's demands — not whether it is the winning one.
//  A test pins the vocabulary.
//
//  Deterministic: stat ties break on StatKey order, never on dictionary
//  iteration order.
//

public nonisolated enum PitWallRemark {

    /// The remark after `optionID` was just picked, given the whole
    /// setup as it now stands.
    public static func after(
        picking optionID: EngineeringOptionID,
        selections: [EngineeringCategoryID: EngineeringOptionID],
        circuit: Circuit,
        weather: Weather,
        budget: Int,
        banned: EngineeringOptionID? = nil
    ) -> String {
        let option = OptionLibrary.option(optionID)
        let name = qualifiedName(option)

        let spent = selections.values.reduce(0) { $0 + OptionLibrary.option($1).cost }
        let remaining = budget - spent
        let open = EngineeringCategoryID.allCases.filter { selections[$0] == nil }

        // 1. Over budget beats everything — it blocks the submission.
        if remaining < 0 {
            return "That's \(-remaining) over the budget. Something has to give."
        }

        // Cheapest legal way to fill what is still open — plain
        // arithmetic on prices the player can see.
        let cheapestRest = open.reduce(0) { $0 + cheapestCost(in: $1, banned: banned) }

        // 2. Can the rest still fit?
        if !open.isEmpty {
            if remaining < cheapestRest {
                return "\(credits(remaining)) for \(open.count) more \(systems(open.count)) — even the cheapest options won't fit."
            }
        }

        // 3. The car is complete.
        if open.isEmpty {
            return remaining == 0
                // "Ready when you are", not "lock it in": the same garage
                // runs Quick Race and the Lab, where nothing is locked.
                ? "All eight systems, every credit spent. Ready when you are."
                : "All eight systems fitted, \(credits(remaining)) in hand. Ready when you are."
        }

        // 4. Budget getting tight.
        if remaining - cheapestRest <= 3 {
            return "\(credits(remaining)) for \(open.count) more \(systems(open.count)). Tight from here."
        }

        let upside = strongestEffect(of: option, helping: true)
        let downside = strongestEffect(of: option, helping: false)

        // 5. Weather the player was told about in the brief.
        switch weather {
        case .hot:
            if let heat = option.statEffects[.heatGeneration], heat > 0 {
                return "\(name) runs hot, and it's a hot day. Lap 3 will feel that."
            }
            if let cooling = option.statEffects[.cooling], cooling > 0 {
                return "More cooling on a hot day. Lap 3 is where that gets paid back."
            }
        case .rain:
            if let stability = option.statEffects[.stability], stability > 0 {
                return "Rain today. Stability is what keeps it on the road."
            }
            if let stability = option.statEffects[.stability], stability < 0 {
                return "\(name) gives up stability, on a wet track. Brave."
            }
        case .sunny, .cold, .windy:
            break
        }

        let deciding = circuit.decidingStats(limit: 4)
        func rank(_ key: StatKey) -> Int? { deciding.firstIndex { $0.key == key } }
        func percent(_ key: StatKey) -> Int { (deciding.first { $0.key == key }?.shareBP ?? 0) / 100 }

        // 6. Giving up something this circuit leans on.
        if let down = downside, let r = rank(down), r < 2 {
            let stat = down.friendlyName
            let verb = down.isInverted ? "adds" : "costs you"
            return "\(name) \(verb) \(stat.lowercased()), and \(stat) is \(percent(down))% of this lap. Make sure it's worth it."
        }

        // 7. Buying something this circuit leans on.
        if let up = upside, let r = rank(up), r < 2 {
            return "\(up.friendlyName) is \(percent(up))% of this lap. That's where \(name) earns its credits."
        }

        // 8. Buying something this circuit barely asks for.
        if let up = upside, rank(up) == nil, option.cost > cheapestCost(in: option.category, banned: banned) {
            return "\(up.friendlyName) barely features on this circuit. \(name) won't get much of it back here."
        }

        // 9. Nothing notable — keep it short and keep the count going.
        return "\(name) fitted. \(open.count) to go."
    }

    // MARK: - Helpers

    /// "Soft tires", "Heavy cooling", "Low Drag aero" — option names
    /// alone collide ("Balanced" exists in six categories).
    static func qualifiedName(_ option: EngineeringOption) -> String {
        let noun: String
        switch option.category {
        case .engineMode: noun = "engine"
        case .tires: noun = "tires"
        case .aerodynamics: noun = "aero"
        case .suspension: noun = "suspension"
        case .gearRatio: noun = "gearing"
        case .cooling: noun = "cooling"
        case .brakes: noun = "brakes"
        case .reliabilityFocus: noun = "reliability"
        }
        return "\(option.displayName) \(noun)"
    }

    /// The largest effect that helps (or hurts) the car, respecting
    /// inverted stats. Same semantics as OptionEffectSummary, but
    /// returns the key rather than a label.
    static func strongestEffect(of option: EngineeringOption, helping: Bool) -> StatKey? {
        var best: (key: StatKey, magnitude: Int)?
        for key in option.statEffects.keys.sorted() {
            guard let value = option.statEffects[key], value != 0 else { continue }
            let helps = key.isInverted ? value < 0 : value > 0
            guard helps == helping else { continue }
            if best == nil || abs(value) > best!.magnitude {
                best = (key, abs(value))
            }
        }
        return best?.key
    }

    private static func cheapestCost(in category: EngineeringCategoryID, banned: EngineeringOptionID?) -> Int {
        OptionLibrary.options(in: category, banned: banned).map(\.cost).min() ?? 0
    }

    private static func systems(_ n: Int) -> String { n == 1 ? "system" : "systems" }

    /// "1 credit", "4 credits".
    private static func credits(_ n: Int) -> String { n == 1 ? "1 credit" : "\(n) credits" }
}
