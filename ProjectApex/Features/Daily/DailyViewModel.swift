//
//  DailyViewModel.swift
//  ProjectApex
//
//  The @MainActor observable bridge between ProjectApexCore and SwiftUI.
//  State machine: building → submitted, plus post-submit analysis
//  (exhaustive, async) and the unofficial Experiment sandbox.
//
//  Locked design decisions:
//  - Over-budget selections ALLOWED; Submit gates, never the tap.
//  - Official submission locks forever; Experiment re-simulation is
//    clearly unofficial and never touches the official result.
//
//  PASS 6 additions:
//  - The day's technical regulation: banned options can't be selected.
//  - The live preview is circuit-relative (today's deciding stats).
//  - "Next test" comes from SetupAdvisor, computed off the main actor.
//

import Foundation
import Observation
import ProjectApexCore

@MainActor
@Observable
final class DailyViewModel {

    enum Phase: Equatable {
        case building
        case submitted
    }

    enum StandingState: Equatable {
        case idle          // no leaderboard wired (tests / offline)
        case loading
        case loaded(LeaderboardStanding)
        /// Carries WHY. Permission-denied, a missing composite index and
        /// a dead network all rendered as one sentence before, and they
        /// need completely different fixes — the reason was caught and
        /// discarded without even a log line.
        case failed(reason: String)
    }

    // MARK: - State

    private let store: DailySaveStore
    private let leaderboard: LeaderboardServicing?
    /// Exposed for the leaderboard's YOU-row highlight.
    let uid: String?
    /// R3: exposed so views inject the same service instead of
    /// constructing Firebase directly.
    var leaderboardService: LeaderboardServicing? { leaderboard }
    private let displayName: String?
    let challenge: DailyChallenge

    /// Global standing (Phase 5). Idle when no leaderboard is injected.
    private(set) var standingState: StandingState = .idle
    private(set) var selections: [EngineeringCategoryID: EngineeringOptionID] = [:]
    private(set) var phase: Phase = .building
    private(set) var result: SimulationResult?

    /// Exhaustive-solver analysis (optimum, gap, beat-%). Loaded async
    /// after submission; nil while computing.
    private(set) var analysis: DayAnalysis?

    /// The engineer's computed next test. Loaded async after
    /// submission; nil while computing or when nothing improves.
    private(set) var advice: EngineerAdvice?

    /// Experiment sandbox (post-submit only). Seeded from the official
    /// selections; freely editable; results are unofficial.
    private(set) var experimentSelections: [EngineeringCategoryID: EngineeringOptionID] = [:]
    private(set) var experimentResult: SimulationResult?

    /// `store` defaults to nil rather than `UserDefaultsSaveStore()`
    /// because default arguments evaluate in a nonisolated context —
    /// the store is created inside the (MainActor) body instead.
    init(
        challenge: DailyChallenge,
        store: DailySaveStore? = nil,
        leaderboard: LeaderboardServicing? = nil,
        uid: String? = nil,
        displayName: String? = nil
    ) {
        self.challenge = challenge
        self.store = store ?? UserDefaultsSaveStore()
        self.leaderboard = leaderboard
        self.uid = uid
        self.displayName = displayName
        restoreIfSubmitted()
    }

    /// Restores a previously submitted day: determinism guarantees the
    /// stored result is byte-identical to re-simulation, so we trust it.
    private func restoreIfSubmitted() {
        guard let record = store.loadRecord(forDateKey: challenge.dateKey) else { return }
        // R6: a record from a different simulation is not this day's
        // record. nil = pre-versioning legacy, treated as current.
        if let recordVersion = record.simulationVersion,
           recordVersion != challenge.simulationVersion {
            DebugLog.log("ignoring saved record: version \(recordVersion) vs \(challenge.simulationVersion)")
            return
        }
        selections = record.selections
        result = record.result
        phase = .submitted
        experimentSelections = record.selections
    }

    /// Current streak for the Brief screen (0 = none/broken).
    var streak: Int {
        guard let day = ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey) else { return 0 }
        return store.currentStreak(asOfDayNumber: day)
    }

    // MARK: - The day's technical regulation

    var bannedOption: EngineeringOptionID? { challenge.bannedOption }

    func isBanned(_ optionID: EngineeringOptionID) -> Bool {
        challenge.bannedOption == optionID
    }

    /// Player-facing regulation line, nil on unrestricted days.
    var regulationText: String? { challenge.regulationText }

    // MARK: - Derived state (official build)

    var budget: Int { challenge.budget }

    var totalCost: Int { cost(of: selections) }
    var remainingCredits: Int { budget - totalCost }
    var isOverBudget: Bool { totalCost > budget }
    var isComplete: Bool { selections.count == EngineeringCategoryID.allCases.count }
    var usesBannedOption: Bool {
        guard let banned = challenge.bannedOption else { return false }
        return selections.values.contains(banned)
    }
    var canSubmit: Bool {
        phase == .building && isComplete && !isOverBudget && !usesBannedOption
    }

    var identityPreview: SetupIdentity? {
        guard isComplete else { return nil }
        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: selections)
        return SetupIdentity.derive(from: VehicleBuilder.build(from: setup))
    }

    /// Live Vehicle Profile as the player builds — the stats that decide
    /// THIS circuit, not a fixed five. Works with partial selections
    /// (unselected categories simply contribute no effect).
    var livePreview: VehicleProfile {
        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: selections)
        return VehicleProfile.from(setup: setup, circuit: challenge.circuit)
    }

    /// One-tap "Next Test": pre-loads the Experiment sandbox with the
    /// setup the engineer actually recommends.
    func preloadExperiment(_ advice: EngineerAdvice) {
        guard phase == .submitted else { return }
        experimentSelections = advice.resultingSelections
        experimentResult = nil
    }

    /// Manual variant, still used by any UI that offers a single swap.
    func preloadExperiment(category: EngineeringCategoryID, option: EngineeringOptionID) {
        guard phase == .submitted, !isBanned(option) else { return }
        experimentSelections = selections
        experimentSelections[category] = option
        experimentResult = nil
    }

    func selectedOption(in category: EngineeringCategoryID) -> EngineeringOptionID? {
        selections[category]
    }

    /// Cost change if this option replaced the current pick in its
    /// category. Drives "+9 / −4" labels in the Bay.
    func costDelta(for option: EngineeringOption) -> Int {
        let current = selections[option.category].map { OptionLibrary.option($0).cost } ?? 0
        return option.cost - current
    }

    // MARK: - Actions (official build)

    /// Always allowed while building — including into over-budget
    /// territory. Banned options are the one hard stop: the database
    /// will reject that submission, so letting it be selected would be
    /// a promise the backend breaks.
    func select(_ optionID: EngineeringOptionID) {
        guard phase == .building, !isBanned(optionID) else { return }
        let option = OptionLibrary.option(optionID)
        selections[option.category] = optionID
    }

    /// Locks the setup and runs the deterministic simulation.
    /// One official submission — no undo.
    func submit() {
        guard canSubmit else { return }
        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: selections)
        let simulationResult = SimulationEngine.simulate(
            setup: setup,
            circuit: challenge.circuit,
            weather: challenge.weather
        )
        result = simulationResult
        phase = .submitted
        experimentSelections = selections

        // Persist: the day is done.
        let record = DailyRecord(
            dateKey: challenge.dateKey,
            selections: selections,
            result: simulationResult,
            submittedAt: Date(),
            simulationVersion: ResultHasher.simulationVersion
        )
        store.saveRecord(record)
        if let day = ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey) {
            store.registerCompletion(dayNumber: day)
        }

        let dayNumber = ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey)
        Analytics.submitted(
            dayNumber: dayNumber,
            streak: streak,
            usedRegulation: challenge.bannedOption != nil
        )

        // Fire the global submission (local record stays source of truth).
        Task { await refreshStanding() }
        Task { await loadAdvice() }
        Task {
            // Ask for notifications only once the habit is real, then
            // rebuild the schedule so today — now raced — is skipped.
            let notifications = NotificationService.shared
            await notifications.requestAuthorizationIfEarned(completedDays: streak)
            await notifications.refreshSchedule(hasPlayedToday: true)
        }
    }

    // MARK: - Global standing (idempotent: retries cover past failures)

    func refreshStanding(force: Bool = false) async {
        guard let leaderboard, let uid, let displayName,
              phase == .submitted,
              let record = store.loadRecord(forDateKey: challenge.dateKey)
        else { return }
        if case .loading = standingState { return }

        // Captured BEFORE the .loading assignment below — checking it
        // afterwards is always false, which silently made the force path
        // dead code and turned pull-to-refresh into a no-op.
        let alreadyRanked: Bool
        if case .loaded = standingState { alreadyRanked = true } else { alreadyRanked = false }

        standingState = .loading
        do {
            let standing: LeaderboardStanding
            if force, alreadyRanked {
                // The entry already exists and is immutable; there is
                // nothing to submit, only a rank to recompute.
                standing = try await leaderboard.standing(
                    dateKey: challenge.dateKey, uid: uid, force: true
                )
            } else {
                standing = try await leaderboard.submitAndStand(
                    record: record, uid: uid, displayName: displayName
                )
            }
            standingState = .loaded(standing)
        } catch {
            // DebugLog prints; CrashReporting REPORTS.
            //
            // `.failed(reason:)` renders that reason only #if DEBUG, so
            // players never see a raw Firestore string — right for the
            // screen, and it meant a leaderboard failure in production
            // was completely invisible. One did occur on the first
            // TestFlight build (day 231, "Couldn't reach the leaderboard")
            // and could not be diagnosed at all, because the only copy of
            // the reason went to a console nobody was attached to.
            //
            // The friendly line stays exactly as it was; the reason now
            // also lands in Crashlytics as a non-fatal, with the day and
            // whether this was a forced refresh, so the next occurrence
            // arrives with its own evidence.
            DebugLog.log("standing failed for \(challenge.dateKey)", error)
            CrashReporting.log(
                "standing failed · day \(challenge.dateKey) · force=\(force) · \(Self.describe(error))",
                error: error
            )
            standingState = .failed(reason: Self.describe(error))
        }
    }

    /// Firestore's own wording is the useful part: "Missing or
    /// insufficient permissions" (rules), "The query requires an index"
    /// (missing composite index), "Failed to get document because the
    /// client is offline" (network). Keeping it lets one screenshot
    /// distinguish three unrelated failures.
    nonisolated static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        return text.isEmpty ? String(describing: error) : text
    }

    // MARK: - Analysis (post-submit, async)

    /// Runs the exhaustive solver off the main actor. Idempotent.
    private var isAnalysisLoading = false

    func loadAnalysis() async {
        guard phase == .submitted, analysis == nil, !isAnalysisLoading,
              let playerAverage = result?.averageLapTimeMillis else { return }
        isAnalysisLoading = true
        defer { isAnalysisLoading = false }
        let challenge = self.challenge
        analysis = await Task.detached(priority: .userInitiated) {
            DayAnalyzer.analyze(
                challenge: challenge,
                playerAverageLapMillis: playerAverage
            )
        }.value
    }

    /// Computes the engineer's next test. ~128 simulations — fast, but
    /// off the main actor anyway so the debrief never stutters.
    private var isAdviceLoading = false

    func loadAdvice() async {
        guard phase == .submitted, advice == nil, !isAdviceLoading,
              let result else { return }
        isAdviceLoading = true
        defer { isAdviceLoading = false }
        let challenge = self.challenge
        let leading = FeedbackEngine.leadingEvent(in: result)
        advice = await Task.detached(priority: .userInitiated) {
            SetupAdvisor.bestAdvice(
                for: result.setup, challenge: challenge, leadingEvent: leading
            )
        }.value
    }

    /// Optimal-setup reveal gates until the challenge day has closed
    /// (competitive integrity: the reveal is a social-contract measure —
    /// the sim is on-device, so this raises effort, not a cryptographic
    /// wall). Malformed/test dateKeys default to allowed.
    func isRevealAllowed(now: Date = Date()) -> Bool {
        guard let challengeDay = ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey) else {
            return true
        }
        let todayKey = UTCDateKey.make(from: now)
        guard let today = ChallengeSeed.dayNumber(fromDateKey: todayKey) else { return true }
        return challengeDay < today
    }

    /// The Race Engineer's structured debrief (rule-based, Core).
    /// Uses the challenge-aware path so the recommendation is the
    /// genuinely fastest change rather than a symptom-driven guess.
    ///
    /// Sector lines sharpen once `analysis` lands: before the solve
    /// finishes there's nothing to measure sectors against except the
    /// neutral car, which no real setup ever loses to.
    var feedback: EngineerFeedback? {
        guard let result else { return nil }
        return FeedbackEngine.generate(
            result: result,
            challenge: challenge,
            optimalSectorTotalsMillis: analysis?.optimalSectorTotalsMillis
        )
    }

    /// Per-sector milliseconds lost to the optimal setup, once known.
    /// Drives the debrief's sector chart.
    var sectorsLostToOptimal: [Int]? {
        guard let result, let analysis else { return nil }
        return FeedbackEngine.sectorsLostToOptimal(
            result: result,
            optimalSectorTotalsMillis: analysis.optimalSectorTotalsMillis
        )
    }

    // MARK: - Share

    /// The social artifact ("Did you do today's Apex?"). Deliberately
    /// reveals the identity and numbers, NEVER the option picks —
    /// the setup is the puzzle answer.
    var shareText: String? {
        guard phase == .submitted, let result else { return nil }
        let dayNumber = ChallengeSeed.dayNumber(fromDateKey: challenge.dateKey)
        let title = dayNumber.map { "Project Apex — Day \($0)" } ?? "Project Apex"

        var lines: [String] = [
            title,
            "\(challenge.circuit.archetype.displayName) · \(challenge.weather.displayName)"
        ]
        if let banned = challenge.bannedOption {
            let option = OptionLibrary.option(banned)
            lines.append("No \(option.displayName) \(option.category.displayName)")
        }
        lines.append("")
        lines.append("Average Lap: \(FixedPoint.formatLapTime(millis: result.averageLapTimeMillis))")

        if case .loaded(let standing) = standingState {
            lines.append("Top \(standing.topPercent)% of engineers today · Rank #\(standing.rank)")
        }
        if let analysis {
            lines.append("Better than \(analysis.beatPercent)% of possible setups")
            let gap = analysis.gapToOptimalMillis
            lines.append("Gap to perfect: +\(gap / 1000).\(String(format: "%03d", gap % 1000))s")
        }
        lines.append("Setup: \(result.setupIdentity.displayText)")
        lines.append("")
        lines.append("Did you do today's Apex?")
        return lines.joined(separator: "\n")
    }

    // MARK: - Experiment sandbox (post-submit, unofficial)

    var experimentTotalCost: Int { cost(of: experimentSelections) }
    var experimentIsOverBudget: Bool { experimentTotalCost > budget }
    var experimentRemainingCredits: Int { budget - experimentTotalCost }
    var experimentUsesBannedOption: Bool {
        guard let banned = challenge.bannedOption else { return false }
        return experimentSelections.values.contains(banned)
    }
    var canRunExperiment: Bool {
        phase == .submitted
            && experimentSelections.count == EngineeringCategoryID.allCases.count
            && !experimentIsOverBudget
            && !experimentUsesBannedOption
    }
    /// Experiment delta vs the official average (negative = faster).
    var experimentDeltaMillis: Int? {
        guard let official = result?.averageLapTimeMillis,
              let test = experimentResult?.averageLapTimeMillis else { return nil }
        return test - official
    }

    func experimentSelectedOption(in category: EngineeringCategoryID) -> EngineeringOptionID? {
        experimentSelections[category]
    }

    func experimentSelect(_ optionID: EngineeringOptionID) {
        guard phase == .submitted, !isBanned(optionID) else { return }
        let option = OptionLibrary.option(optionID)
        experimentSelections[option.category] = optionID
        experimentResult = nil // stale once the setup changes
    }

    func runExperiment() {
        guard canRunExperiment else { return }
        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: experimentSelections)
        experimentResult = SimulationEngine.simulate(
            setup: setup,
            circuit: challenge.circuit,
            weather: challenge.weather
        )
    }

    // MARK: - Helpers

    private func cost(of selections: [EngineeringCategoryID: EngineeringOptionID]) -> Int {
        selections.values.map { OptionLibrary.option($0).cost }.reduce(0, +)
    }
}
