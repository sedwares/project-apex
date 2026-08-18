//
//  TestSessionViewModel.swift
//  ProjectApex
//
//  The laboratory (design doc §5.2). Deliberately NOT DailyViewModel:
//  no lock, no persistence, no streak — unlimited runs, rerollable
//  conditions, session-best tracking. Knowledge transfers to the
//  Daily; nothing else does.
//

import Foundation
import Observation
import ProjectApexCore

@MainActor
@Observable
final class TestSessionViewModel {

    enum Mode: Equatable {
        /// Mystery conditions — read-only, reroll only. Race day
        /// doesn't let you pick the weather.
        case quickRace
        /// Full control panel — the lab proper.
        case customTest
    }

    struct Conditions: Equatable {
        var archetype: CircuitArchetype
        var weather: Weather
        var budget: Int
    }

    /// Custom Test allows a wider budget range than the daily
    /// generator (92–108) — it's a lab, let people probe the edges.
    static let customBudgetRange = 80...120

    // MARK: - State

    let mode: Mode
    private(set) var conditions: Conditions
    private(set) var circuit: Circuit
    private(set) var selections: [EngineeringCategoryID: EngineeringOptionID] = [:]
    private(set) var lastResult: SimulationResult?
    /// Set when a run should present the replay ceremony; the view
    /// observes this and clears it when the replay is dismissed.
    var replayResult: SimulationResult?
    private(set) var bestAverageMillis: Int?
    private(set) var runCount = 0
    /// Every run this session, most recent first — so the player can
    /// see each attempt's time, not just the latest and the best.
    private(set) var runHistory: [SimulationResult] = []

    private var rng: SplitMix64

    // MARK: - Init

    init(conditions: Conditions, seed: UInt64, mode: Mode = .customTest) {
        self.mode = mode
        self.conditions = conditions
        // Local rng first: @Observable backs properties with macro
        // storage, so `&self.rng` counts as touching self before all
        // stored properties are initialized. Build locally, assign last.
        var rng = SplitMix64(seed: seed)
        self.circuit = Self.makeCircuit(archetype: conditions.archetype, rng: &rng)
        self.rng = rng
    }

    /// Quick Race: random conditions, one tap to the Bay.
    static func quickRace(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) -> TestSessionViewModel {
        var rng = SplitMix64(seed: seed)
        let conditions = Conditions(
            archetype: rng.pick(CircuitArchetype.allCases),
            weather: rng.pick(Weather.allCases),
            budget: ChallengeGenerator.budgetRange.lowerBound
                + rng.next(upperBound: ChallengeGenerator.budgetRange.count)
        )
        return TestSessionViewModel(conditions: conditions, seed: seed &+ 1, mode: .quickRace)
    }

    /// Quick Race reroll: entirely new random race (conditions +
    /// layout). Selections survive; results and best reset.
    func newQuickRace() {
        conditions = Conditions(
            archetype: rng.pick(CircuitArchetype.allCases),
            weather: rng.pick(Weather.allCases),
            budget: ChallengeGenerator.budgetRange.lowerBound
                + rng.next(upperBound: ChallengeGenerator.budgetRange.count)
        )
        circuit = Self.makeCircuit(archetype: conditions.archetype, rng: &rng)
        resetSession()
    }

    private static func makeCircuit(archetype: CircuitArchetype, rng: inout SplitMix64) -> Circuit {
        TrackGenerator.generate(
            archetype: archetype,
            id: "test-\(rng.next())",
            name: "Test Circuit",
            rng: &rng
        )
    }

    // MARK: - Derived

    var budget: Int { conditions.budget }

    /// Adapts the current lab conditions into a DailyChallenge so the
    /// shared replay + context header work without special-casing.
    /// minPossibleAverageLapMillis is 0 (unused off the leaderboard).
    var challengeAdapter: DailyChallenge {
        DailyChallenge(
            id: circuit.id,
            dateKey: "test-\(circuit.id)",
            seed: 0,
            circuit: circuit,
            weather: conditions.weather,
            budget: conditions.budget,
            simulationVersion: ResultHasher.simulationVersion,
            minPossibleAverageLapMillis: 0
        )
    }
    var totalCost: Int {
        selections.values.map { OptionLibrary.option($0).cost }.reduce(0, +)
    }
    var remainingCredits: Int { budget - totalCost }
    var isOverBudget: Bool { totalCost > budget }
    var isComplete: Bool { selections.count == EngineeringCategoryID.allCases.count }
    var canRun: Bool { isComplete && !isOverBudget }

    /// PASS 6: uses the challenge-aware path via `challengeAdapter`.
    ///
    /// The lab was rendering the event-only fallback, which has no
    /// circuit and no budget and so can only describe the symptom —
    /// hence hedges like "if this circuit lets you" and "paid for
    /// elsewhere". Everything the advisor needs is right here.
    var feedback: EngineerFeedback? {
        guard let lastResult else { return nil }
        return FeedbackEngine.generate(result: lastResult, challenge: challengeAdapter)
    }

    /// The computed next test for the current run. nil while it's being
    /// worked out, or when nothing meaningful improves the setup.
    private(set) var advice: EngineerAdvice?
    private var isAdviceLoading = false

    /// ~128 simulations. Off the main actor so the run bar stays live.
    func loadAdvice() async {
        guard let lastResult, advice == nil, !isAdviceLoading else { return }
        isAdviceLoading = true
        defer { isAdviceLoading = false }
        let challenge = challengeAdapter
        let leading = FeedbackEngine.leadingEvent(in: lastResult)
        advice = await Task.detached(priority: .userInitiated) {
            SetupAdvisor.bestAdvice(
                for: lastResult.setup, challenge: challenge, leadingEvent: leading
            )
        }.value
    }

    /// The lab's whole point: take the engineer's suggestion and run it
    /// immediately. In the Daily this has to go through the unofficial
    /// Experiment sandbox; here there's nothing to protect.
    func applyAdvice() {
        guard let advice else { return }
        selections = advice.resultingSelections
        lastResult = nil
        self.advice = nil
        run()
    }

    func selectedOption(in category: EngineeringCategoryID) -> EngineeringOptionID? {
        selections[category]
    }

    // MARK: - Actions

    func select(_ optionID: EngineeringOptionID) {
        let option = OptionLibrary.option(optionID)
        selections[option.category] = optionID
        lastResult = nil // stale once the setup changes
        advice = nil     // and so is the advice derived from it
    }

    /// Unlimited, unofficial, instant.
        ///
        /// The sim is deterministic, so re-running an unchanged setup
        /// produces an identical result. Recording it would fill the
        /// session log with indistinguishable rows — so the run still
        /// happens (and still shows in the run bar and replay), but the
        /// history only gains an entry when something actually changed.
        func run() {
            guard canRun else { return }
            let setup = PlayerSetup(challengeId: circuit.id, selectedOptions: selections)
            let result = SimulationEngine.simulate(
                setup: setup, circuit: circuit, weather: conditions.weather
            )
            lastResult = result
            replayResult = result
            advice = nil   // recomputed for the new result by the view's task

            let isRepeat = runHistory.first?.resultHash == result.resultHash
            if !isRepeat {
                runCount += 1
                runHistory.insert(result, at: 0)
            }

            if bestAverageMillis == nil || result.averageLapTimeMillis < bestAverageMillis! {
                bestAverageMillis = result.averageLapTimeMillis
            }
        }

    /// Changing any condition invalidates results and session best —
    /// bests only mean something under fixed conditions.
    func setArchetype(_ archetype: CircuitArchetype) {
        guard archetype != conditions.archetype else { return }
        conditions.archetype = archetype
        circuit = Self.makeCircuit(archetype: archetype, rng: &rng)
        resetSession()
    }

    func setWeather(_ weather: Weather) {
        guard weather != conditions.weather else { return }
        conditions.weather = weather
        resetSession()
    }

    func setBudget(_ budget: Int) {
        let clamped = min(max(budget, Self.customBudgetRange.lowerBound), Self.customBudgetRange.upperBound)
        guard clamped != conditions.budget else { return }
        conditions.budget = clamped
        resetSession()
    }

    /// New layout, same archetype/weather/budget.
    func rerollCircuit() {
        circuit = Self.makeCircuit(archetype: conditions.archetype, rng: &rng)
        resetSession()
    }

    private func resetSession() {
        lastResult = nil
        advice = nil
        bestAverageMillis = nil
        runCount = 0
        runHistory = []
    }
}
