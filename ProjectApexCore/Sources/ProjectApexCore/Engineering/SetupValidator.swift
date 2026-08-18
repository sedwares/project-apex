//
//  SetupValidator.swift
//  ProjectApexCore
//
//  Validates a PlayerSetup against the option library, a budget, and
//  the day's technical regulation. Used by the Engineering Bay (live UI
//  feedback), the solver (legal-setup enumeration), and backend sanity
//  checks.
//

public nonisolated enum SetupValidationError: Error, Equatable, Sendable {
    /// A category has no selected option.
    case missingCategory(EngineeringCategoryID)
    /// The selected option does not belong to the category it's keyed under.
    case optionCategoryMismatch(category: EngineeringCategoryID, option: EngineeringOptionID)
    /// Total cost exceeds the challenge budget.
    case overBudget(totalCost: Int, budget: Int)
    /// Stored totalCost doesn't match the recomputed cost (tampering or stale data).
    case costMismatch(stored: Int, computed: Int)
    /// The setup uses the option banned by the day's regulation.
    case bannedOption(EngineeringOptionID)
}

public nonisolated enum SetupValidator {

    /// Full validation. Returns all failures, not just the first,
    /// so the Engineering Bay can show every problem at once.
    public static func validate(
        _ setup: PlayerSetup,
        budget: Int,
        banned: EngineeringOptionID? = nil
    ) -> [SetupValidationError] {
        var errors: [SetupValidationError] = []

        // Every category must be present.
        for category in EngineeringCategoryID.allCases {
            if setup.selectedOptions[category] == nil {
                errors.append(.missingCategory(category))
            }
        }

        // Every selected option must belong to its keyed category, and
        // must not be the one the stewards disallowed.
        var computedCost = 0
        for (category, optionID) in setup.selectedOptions.sorted(by: { $0.key < $1.key }) {
            let option = OptionLibrary.option(optionID)
            if option.category != category {
                errors.append(.optionCategoryMismatch(category: category, option: optionID))
            }
            if let banned, optionID == banned {
                errors.append(.bannedOption(optionID))
            }
            computedCost += option.cost
        }

        // Stored cost must match recomputed cost.
        if setup.totalCost != computedCost {
            errors.append(.costMismatch(stored: setup.totalCost, computed: computedCost))
        }

        // Budget check uses the recomputed cost (trust nothing stored).
        if computedCost > budget {
            errors.append(.overBudget(totalCost: computedCost, budget: budget))
        }

        return errors
    }

    /// Convenience overload for a full challenge.
    public static func validate(_ setup: PlayerSetup, challenge: DailyChallenge) -> [SetupValidationError] {
        validate(setup, budget: challenge.budget, banned: challenge.bannedOption)
    }

    /// Convenience boolean for solver hot paths.
    public static func isLegal(
        _ setup: PlayerSetup,
        budget: Int,
        banned: EngineeringOptionID? = nil
    ) -> Bool {
        validate(setup, budget: budget, banned: banned).isEmpty
    }
}
