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

    // ── THE LAST RUN, AND WHAT IT WAS A RUN OF ─────────────────────
    //
    // These used to be thrown away by select(): change one option and
    // the result, the solve and the engineer's advice were all set to
    // nil. Changing BACK did not bring them back, because loadAdvice()
    // guards on lastResult and there was no longer a result to guard
    // on — so the read stayed gone until another run, which is the bug
    // Sedar hit by toggling Suspension to Stiff and back to Balanced.
    //
    // Discarding was never right. This simulation is deterministic: a
    // result computed for a setup is correct for that setup forever,
    // which is the same property run() already relies on. So the run is
    // KEPT, along with the selections that produced it, and the
    // accessors below simply stop reporting it while the car on screen
    // is a different car. Wander off, come back, and your read is
    // waiting where you left it.
    private var storedResult: SimulationResult?
    private var storedAnalysis: DayAnalysis?
    private var storedAdvice: EngineerAdvice?
    /// The setup `storedResult` was simulated from.
    private var runSelections: [EngineeringCategoryID: EngineeringOptionID] = [:]

    /// Whether the last run still describes what is on screen.
    var isRunCurrent: Bool {
        storedResult != nil && runSelections == selections
    }

    var lastResult: SimulationResult? { isRunCurrent ? storedResult : nil }
    /// Set when a run should present the replay ceremony; the view
    /// observes this and clears it when the replay is dismissed.
    var replayResult: SimulationResult?
    private(set) var bestAverageMillis: Int?
    private(set) var runCount = 0
    /// Every run this session, most recent first — so the player can
    /// see each attempt's time, not just the latest and the best.
    private(set) var runHistory: [SessionRun] = []

    /// One recorded run, carrying an identity the SIMULATION cannot
    /// supply.
    ///
    /// The history used to be `[SimulationResult]`, keyed in the view by
    /// `resultHash`. That is a content hash, and the simulation is
    /// deterministic — so re-running a setup you tried earlier in the
    /// session produces a byte-identical result and therefore a
    /// DUPLICATE SwiftUI identity. Duplicate ids in a ForEach are
    /// undefined behaviour: observed live, a 10-run session rendered
    /// runs 3 and 4 twice each and dropped 6 and 7 entirely, with the
    /// numbering scrambled to 10,9,8,3,4,5,4,3,2,1.
    ///
    /// The app's central promise — same setup, same result, forever —
    /// is exactly what made the content hash unusable as an identity.
    /// `number` is assigned once when the run is recorded and never
    /// derived from position, so it is stable no matter what else
    /// enters the list.
    struct SessionRun: Identifiable, Sendable {
        /// Monotonic within a session, 1-based. Also the "Run N" label —
        /// the label used to be `runHistory.count - index`, which made
        /// it depend on the same unstable index.
        let number: Int
        let result: SimulationResult

        var id: Int { number }
    }

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
    /// Cached for the same reason the Daily's is — see DailyViewModel.
    /// This one also has to key on the CONDITIONS, because the lab can
    /// reroll them under an unchanged result.
    @ObservationIgnored private var feedbackCache: (key: String, value: EngineerFeedback)?

    var feedback: EngineerFeedback? {
        guard let lastResult else { return nil }
        let key = "\(lastResult.resultHash)|\(circuit.id)|\(conditions.weather.rawValue)"
            + "|\(conditions.budget)|\(analysis == nil ? "pending" : "solved")"
        if let cached = feedbackCache, cached.key == key { return cached.value }
        let generated = FeedbackEngine.generate(
            result: lastResult,
            challenge: challengeAdapter,
            // Was nil, which sent the whole practice mode down the
            // NEUTRAL-CAR fallback: all twelve stats at 1000 and no
            // options. That car is not in the legal space — every setup
            // must pick eight options — so nobody can build it and
            // every real car beats it by seconds. The result was lines
            // like "6.148s quicker than the neutral car": always large,
            // always positive, carrying no information.
            //
            // The Daily had exactly this bug in its sector chart and it
            // was fixed there; see the comment on
            // RaceDebriefView.sectorsSection. The practice modes were
            // the last place the old baseline survived, which also made
            // the two screens incomparable while speaking in the same
            // Chief Engineer voice.
            optimalSectorTotalsMillis: analysis?.optimalSectorTotalsMillis
        )
        feedbackCache = (key, generated)
        return generated
    }

    // MARK: - Exhaustive analysis (the real baseline)

    /// The optimal legal setup for the CURRENT conditions.
    ///
    /// Same exhaustive solve the Daily runs. It is affordable here for
    /// the same reason it is affordable there — the publish tool solves
    /// a full day in 12–45ms — and it buys the practice modes a target
    /// worth measuring against, plus a real gap and "possible setups
    /// beaten".
    var analysis: DayAnalysis? { isRunCurrent ? storedAnalysis : nil }
    private var isAnalysisLoading = false

    /// Off the main actor: the solve walks the whole legal space, and
    /// the run bar has to stay responsive.
    // ── WHY THESE CARRY A GENERATION TOKEN ─────────────────────────
    // Both loaders await a detached solve and then ASSIGN the answer.
    // Nothing checked that the question was still the same one. The lab
    // lets you reroll the circuit or run again while a solve is in
    // flight, so a slow answer could land on a newer run and attach
    // last setup's advice to this setup's result — silently, and
    // looking entirely plausible.
    //
    // `isAnalysisLoading` did not prevent it: it stops a SECOND solve
    // starting, not the first one from finishing into a changed world.
    // DailyCoordinator already uses this exact pattern for overlapping
    // challenge loads; this is the same idea for the same reason.
    // Raised in review 2026-09-17.
    private var solveGeneration = 0

    /// Call whenever the question changes: a new run, or new conditions.
    private func invalidateSolves() {
        solveGeneration += 1
    }

    func loadAnalysis() async {
        guard lastResult != nil, analysis == nil, !isAnalysisLoading else { return }
        isAnalysisLoading = true
        defer { isAnalysisLoading = false }
        // ── A DISCARDED ANSWER MUST BE REPLACED, NOT JUST DROPPED ──
        // The generation token stopped a stale solve overwriting a newer
        // run, but it introduced the opposite failure: the new request
        // returns early while this one is still loading, then this one
        // finishes, sees the mismatch and throws its answer away — and
        // nothing is left to ask the question again. Stale answers
        // became missing answers.
        //
        // Looping here means whoever is already inside carries the new
        // question rather than abandoning it. Bounded, because the
        // generation only moves on a user action and spinning the solver
        // forever would be worse than a missing read.
        for _ in 0..<4 {
            guard let current = lastResult, storedAnalysis == nil else { return }
            let generation = solveGeneration
            let challenge = challengeAdapter
            let playerAverage = current.averageLapTimeMillis
            let solved = await Task.detached(priority: .userInitiated) {
                DayAnalyzer.analyze(
                    challenge: challenge,
                    playerAverageLapMillis: playerAverage
                )
            }.value
            if generation == solveGeneration {
                storedAnalysis = solved
                return
            }
        }
    }

    /// Sector deltas against the optimal setup, per lap — the same
    /// quantity the Daily debrief charts. nil until the solve lands.
    var sectorsLostToOptimal: [Int]? {
        guard let lastResult, let analysis else { return nil }
        return FeedbackEngine.sectorsLostToOptimal(
            result: lastResult,
            optimalSectorTotalsMillis: analysis.optimalSectorTotalsMillis
        )
    }

    /// The computed next test for the current run. nil while it's being
    /// worked out, or when nothing meaningful improves the setup.
    var advice: EngineerAdvice? { isRunCurrent ? storedAdvice : nil }
    private var isAdviceLoading = false

    /// ~128 simulations. Off the main actor so the run bar stays live.
    func loadAdvice() async {
        guard lastResult != nil, advice == nil, !isAdviceLoading else { return }
        isAdviceLoading = true
        defer { isAdviceLoading = false }
        // Same loop, same reason as loadAnalysis.
        for _ in 0..<4 {
            guard let current = lastResult, storedAdvice == nil else { return }
            let generation = solveGeneration
            let challenge = challengeAdapter
            let leading = FeedbackEngine.leadingEvent(in: current)
            let solved = await Task.detached(priority: .userInitiated) {
                SetupAdvisor.bestAdvice(
                    for: current.setup, challenge: challenge, leadingEvent: leading
                )
            }.value
            if generation == solveGeneration {
                storedAdvice = solved
                return
            }
        }
    }

    /// The lab's whole point: take the engineer's suggestion and run it
    /// immediately. In the Daily this has to go through the unofficial
    /// Experiment sandbox; here there's nothing to protect.
    func applyAdvice() {
        guard let advice else { return }
        selections = advice.resultingSelections
        run()   // records the new run and the setup it belongs to
    }

    func selectedOption(in category: EngineeringCategoryID) -> EngineeringOptionID? {
        selections[category]
    }

    /// The delta an option row should PRINT — nil before anything is
    /// chosen in the category, or when the swap is free. The lab has a
    /// budget too, so the number means exactly what it means in the Bay.
    func costDeltaIfComparable(for option: EngineeringOption) -> Int? {
        guard let current = selections[option.category] else { return nil }
        let change = option.cost - OptionLibrary.option(current).cost
        return change == 0 ? nil : change
    }

    /// Live Vehicle Profile as you build, against the bench's circuit.
    /// The Bay has drawn this since pass 7; the lab is where you are
    /// most likely to be testing a theory about it.
    var livePreview: VehicleProfile {
        let setup = PlayerSetup(challengeId: circuit.id, selectedOptions: selections)
        return VehicleProfile.from(setup: setup, circuit: circuit)
    }

    /// What the car on the bench currently IS, before it has run.
    ///
    /// `SimulationResult` already carries a `setupIdentity`, but only
    /// once a run exists. The lab is for trying things, so the identity
    /// has to update as you try them — same derivation the Daily bay
    /// uses for its own preview.
    var identityPreview: SetupIdentity? {
        guard isComplete else { return nil }
        let setup = PlayerSetup(challengeId: circuit.id, selectedOptions: selections)
        return SetupIdentity.derive(from: VehicleBuilder.build(from: setup))
    }

    // MARK: - Actions

    func select(_ optionID: EngineeringOptionID) {
        let option = OptionLibrary.option(optionID)
        selections[option.category] = optionID
        // Nothing is discarded. `isRunCurrent` now reports false, which
        // hides the run and its read; restoring this option restores
        // them, because the result was never destroyed.
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
            // ── ONLY DISCARD WHEN THE CAR ACTUALLY CHANGED ─────────
            // The view's task is keyed on the result hash, deliberately,
            // so that re-running an identical setup does not repeat a
            // few-thousand-simulation search. But this cleared the
            // advice and the analysis unconditionally — so a repeat run
            // wiped the Engineer's read and then the task did NOT
            // re-fire, because the hash was the same. The read simply
            // vanished until the player changed something.
            //
            // The intent was right and the implementation contradicted
            // it. An identical hash under unchanged conditions means an
            // identical car, so the solve is still exactly correct:
            // keep it, and the task's own de-duplication does the rest.
            // Rerolling the circuit clears everything separately.
            let carChanged = result.resultHash != storedResult?.resultHash

            storedResult = result
            runSelections = selections
            replayResult = result
            if carChanged {
                invalidateSolves()   // any solve in flight is for the previous car
                storedAdvice = nil   // recomputed by the view's task
            }

            // Every run is recorded, repeats included.
            //
            // This used to skip a run whose result matched the PREVIOUS
            // one, to keep the log free of indistinguishable rows. Two
            // problems: it only compared against `runHistory.first`, so
            // A → B → A slipped through and produced the duplicate-id
            // crash described on SessionRun; and the premise was wrong.
            // A repeat that returns an identical time is not noise — in
            // a deterministic simulation it is the proof, and the Lab is
            // a notebook, so the honest record is every attempt.
            // A new result means the previous solve describes a
            // different car. The conditions are unchanged, so the
            // OPTIMUM is unchanged too — but DayAnalyzer folds the
            // player's own average into beatPercent and the gap, so it
            // has to be recomputed.
            if carChanged { storedAnalysis = nil }

            runCount += 1
            runHistory.insert(SessionRun(number: runCount, result: result), at: 0)

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
        storedResult = nil
        storedAdvice = nil
        storedAnalysis = nil
        runSelections = [:]
        invalidateSolves()   // the circuit changed under any in-flight solve
        bestAverageMillis = nil
        runCount = 0
        runHistory = []
    }
}
