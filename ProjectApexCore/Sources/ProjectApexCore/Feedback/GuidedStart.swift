//
//  GuidedStart.swift
//  ProjectApexCore
//
//  The first assignment a new player ever sees.
//
//  Eight systems and twenty-four options is a lot to meet cold. On day
//  one, five systems arrive already fitted with the Balanced team's
//  baseline (the same rival the player races), and three are left open:
//  the three whose options swing what this circuit asks for most. The
//  player makes the decisions that matter and reaches the race in
//  about a minute. Everything stays editable.
//
//  The three are chosen ONLY from on-screen information — the circuit's
//  two leading demands and each option's printed ± effects — never from
//  the solver, so it points at where the decision is, not at an answer.
//

public nonisolated enum GuidedStart {

    public struct Plan: Sendable, Equatable {
        /// The five systems fitted for the player.
        public let prefilled: [EngineeringCategoryID: EngineeringOptionID]
        /// The three left open, in board order.
        public let focus: [EngineeringCategoryID]
    }

    public static let focusCount = 3

    public static func plan(for challenge: DailyChallenge) -> Plan {
        let deciding = challenge.circuit.decidingStats(limit: 2)

        // How far a system's options move today's leading demands.
        func swing(_ category: EngineeringCategoryID) -> Int {
            let options = OptionLibrary.options(in: category)
            return deciding.reduce(0) { sum, demand in
                let values = options.map { $0.statEffects[demand.key] ?? 0 }
                let range = (values.max() ?? 0) - (values.min() ?? 0)
                return sum + range * demand.shareBP
            }
        }

        let order = OptionLibrary.categories.map(\.id)
        let ranked = order.enumerated().sorted { a, b in
            let sa = swing(a.element), sb = swing(b.element)
            return sa != sb ? sa > sb : a.offset < b.offset
        }
        let focus = Set(ranked.prefix(focusCount).map(\.element))

        // The Balanced rival's car, fitted to today's budget and rules.
        // Legal as a whole, so whatever the player picks in the three
        // open systems, the cheapest option always still fits.
        let balanced = RivalField.templates.first { $0.id == "balanced" }!.picks
        let legal = RivalField.legalize(balanced, budget: challenge.budget, banned: challenge.bannedOption)
        let prefilled = legal.filter { !focus.contains($0.key) }

        return Plan(prefilled: prefilled, focus: order.filter(focus.contains))
    }
}
