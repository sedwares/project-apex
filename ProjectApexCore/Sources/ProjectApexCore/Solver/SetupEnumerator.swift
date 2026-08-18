//
//  SetupEnumerator.swift
//  ProjectApexCore
//
//  Enumerates the full setup space (3^8 = 6,561) in deterministic
//  odometer order. Small enough that Phase 2 validation is exhaustive
//  rather than sampled — the diversity gate and minimum-time
//  computation are exact, not estimates.
//
//  With a technical regulation in force one category drops to two
//  options, so the space shrinks to 2 × 3^7 = 4,374 before the budget
//  filter. Still exhaustively solvable in well under a second.
//

public nonisolated enum SetupEnumerator {

    /// Total setup space size with no regulation: 3^8.
    public static let totalSetupCount = 6_561

    /// Size of the structural space once a regulation is applied.
    public static func setupCount(banned: EngineeringOptionID?) -> Int {
        EngineeringCategoryID.allCases
            .map { OptionLibrary.options(in: $0, banned: banned).count }
            .reduce(1, *)
    }

    /// Calls body for every possible setup, in stable odometer order
    /// (categories sorted, options in display order). Options removed by
    /// the day's regulation are never emitted, so callers can treat
    /// every emitted setup as structurally legal.
    public static func forEachSetup(
        challengeId: String,
        banned: EngineeringOptionID? = nil,
        _ body: (PlayerSetup) -> Void
    ) {
        let categories = EngineeringCategoryID.allCases.sorted()
        let optionsPerCategory = categories.map { OptionLibrary.options(in: $0, banned: banned) }

        // A regulation can never empty a category (3 options, 1 banned),
        // but guard anyway so a future library change fails loudly here
        // rather than producing a silently empty enumeration.
        precondition(
            optionsPerCategory.allSatisfy { !$0.isEmpty },
            "regulation left a category with no options"
        )

        var indices = [Int](repeating: 0, count: categories.count)

        while true {
            var selection: [EngineeringCategoryID: EngineeringOptionID] = [:]
            selection.reserveCapacity(categories.count)
            for (i, category) in categories.enumerated() {
                selection[category] = optionsPerCategory[i][indices[i]].id
            }
            body(PlayerSetup(challengeId: challengeId, selectedOptions: selection))

            var pos = indices.count - 1
            while pos >= 0 {
                indices[pos] += 1
                if indices[pos] < optionsPerCategory[pos].count { break }
                indices[pos] = 0
                pos -= 1
            }
            if pos < 0 { break }
        }
    }

    /// All setups legal under the given budget and regulation.
    public static func legalSetups(
        challengeId: String,
        budget: Int,
        banned: EngineeringOptionID? = nil
    ) -> [PlayerSetup] {
        var result: [PlayerSetup] = []
        result.reserveCapacity(setupCount(banned: banned))
        forEachSetup(challengeId: challengeId, banned: banned) { setup in
            if setup.totalCost <= budget {
                result.append(setup)
            }
        }
        return result
    }
}
