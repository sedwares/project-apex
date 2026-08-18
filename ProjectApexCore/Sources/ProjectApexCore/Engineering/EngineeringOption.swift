//
//  EngineeringOption.swift
//  ProjectApexCore
//
//  Model types for engineering categories and options.
//  The actual 24-option data lives in OptionLibrary.swift.
//

public nonisolated struct EngineeringOption: Codable, Hashable, Sendable, Identifiable {
    public let id: EngineeringOptionID
    public let category: EngineeringCategoryID
    public let displayName: String
    /// Budget cost in engineering credits.
    public let cost: Int
    /// Stat deltas in millipoints, added to the baseline of 1000.
    /// Only affected stats are listed; absent keys mean zero.
    public let statEffects: [StatKey: Int]

    public init(
        id: EngineeringOptionID,
        category: EngineeringCategoryID,
        displayName: String,
        cost: Int,
        statEffects: [StatKey: Int]
    ) {
        self.id = id
        self.category = category
        self.displayName = displayName
        self.cost = cost
        self.statEffects = statEffects
    }
}

public nonisolated struct EngineeringCategory: Codable, Hashable, Sendable, Identifiable {
    public let id: EngineeringCategoryID
    public let displayName: String
    /// Exactly three options, in fixed display order (option 1, 2, 3).
    public let options: [EngineeringOption]

    public init(id: EngineeringCategoryID, options: [EngineeringOption]) {
        self.id = id
        self.displayName = id.displayName
        self.options = options
    }
}
