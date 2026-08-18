//
//  PlayerSetup.swift
//  ProjectApexCore
//

public nonisolated struct PlayerSetup: Codable, Hashable, Sendable {
    public let challengeId: String
    /// One selected option per category. String-backed enum keys encode
    /// as a keyed JSON object (CodingKeyRepresentable), so Firestore
    /// documents stay readable and queryable.
    public let selectedOptions: [EngineeringCategoryID: EngineeringOptionID]
    public let totalCost: Int

    public init(
        challengeId: String,
        selectedOptions: [EngineeringCategoryID: EngineeringOptionID]
    ) {
        self.challengeId = challengeId
        self.selectedOptions = selectedOptions
        self.totalCost = selectedOptions.values
            .map { OptionLibrary.option($0).cost }
            .reduce(0, +)
    }
}
