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
        /// Today's record was submitted by an account this device no
        /// longer has. There is a row on the board, it is just not
        /// ours to claim — and re-submitting would add a second one.
        case belongsToPreviousAccount
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
    // MARK: - The day closing under you

    /// True once UTC has moved past the day this challenge belongs to.
    ///
    /// Leave the app open overnight and the loaded challenge becomes
    /// yesterday's. Before this existed nothing noticed: the bay still
    /// accepted a submission, `submit()` wrote a local record and bumped
    /// the streak, and only then did Firestore reject the write against
    /// a closed day — leaving a player who did everything right with a
    /// result that never ranked and a streak built on it.
    ///
    /// Stored rather than computed from `Date()` on read, because a
    /// computed clock is not observable: the badge and the Submit button
    /// have to change AT midnight for someone sitting on the screen, not
    /// the next time something else happens to redraw. `refreshDayState`
    /// is driven by the scene becoming active and by a timer armed for
    /// the next UTC midnight — see DailyHomeView.
    private(set) var isClosed = false

    /// Recomputes `isClosed`. Returns true if it changed, so the caller
    /// can decide whether a full reload is warranted.
    @discardableResult
    func refreshDayState(now: Date = Date()) -> Bool {
        // A challenge whose dateKey is not a real UTC date key cannot be
        // held against the calendar. That only ever happens for a
        // SYNTHETIC challenge — the lab's adapter, a test fixture —
        // never a published day, so the honest answer is "open" rather
        // than locking a screen out on an unparseable string. Writing
        // the regression test is what surfaced this: the fixtures use
        // "test-day-1", which compares unequal to every real date and
        // would have closed every test's assignment on construction.
        let closed = ChallengeSeed.parse(dateKey: challenge.dateKey) != nil
            && UTCDateKey.make(from: now) != challenge.dateKey
        guard closed != isClosed else { return false }
        isClosed = closed
        return true
    }

    var canSubmit: Bool {
        phase == .building && isComplete && !isOverBudget
            && !usesBannedOption && !isClosed
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

    /// The delta an option row prints: the cost change if this option
    /// replaced the current pick in its category — "+9 / −4" beside the
    /// price.
    ///
    /// Nil when there is nothing to compare against yet, or when the
    /// swap is free. This used to return a plain Int against an assumed
    /// current cost of zero, so an untouched category printed "+34" —
    /// the option's own price, dressed up as a change.
    func costDeltaIfComparable(for option: EngineeringOption) -> Int? {
        Self.delta(for: option, against: selections)
    }

    static func delta(for option: EngineeringOption,
                      against picks: [EngineeringCategoryID: EngineeringOptionID]) -> Int? {
        guard let current = picks[option.category] else { return nil }
        let change = option.cost - OptionLibrary.option(current).cost
        return change == 0 ? nil : change
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
        // Re-checked here, not just in canSubmit: the button may have
        // been on screen when the day was still open. One tap after
        // midnight must not write a record the server will refuse.
        refreshDayState()
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
            simulationVersion: ResultHasher.simulationVersion,
            submittedByUID: uid
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

        // The record may predate this account. See DailyRecord
        // .submittedByUID: the uid lives in the keychain and the record
        // in UserDefaults, so a server-side account deletion or a
        // restored backup can leave today's result on the device under
        // an identity that is gone. Submitting it again would write a
        // SECOND entry for the same lap on the same day.
        //
        // A record with no owner is legacy, not foreign — those predate
        // the field and are still ours.
        if let owner = record.submittedByUID, owner != uid {
            DebugLog.log("standing skipped: record belongs to \(owner), signed in as \(uid)")
            standingState = .belongsToPreviousAccount
            return
        }

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
        // The solve landing changes the feedback's cache key, so rebuild
        // it here rather than letting the next `body` pay for it.
        await primeFeedback()
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
        await primeFeedback()
    }

    /// Build the feedback OFF the main actor and leave it in the cache.
    ///
    /// Caching alone only fixed the repeat cost: the first `body` after
    /// a change still ran the 128-simulation advisor inline, which is
    /// mitigation rather than a fix (noted in review 2026-09-17). Doing
    /// the work here means the getter is a dictionary hit on every path
    /// the debrief actually takes. The synchronous fallback stays, so a
    /// view that renders before this lands still shows real feedback
    /// instead of a hole.
    func primeFeedback() async {
        guard let result else { return }
        let challenge = self.challenge
        let sectors = analysis?.optimalSectorTotalsMillis
        let key = feedbackKey(for: result)
        if feedbackCache?.key == key { return }
        let generated = await Task.detached(priority: .userInitiated) {
            FeedbackEngine.generate(
                result: result,
                challenge: challenge,
                optimalSectorTotalsMillis: sectors
            )
        }.value
        feedbackCache = (key, generated)
    }

    private func feedbackKey(for result: SimulationResult) -> String {
        "\(result.resultHash)|\(analysis == nil ? "pending" : "solved")"
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
    /// ── WHY THIS IS CACHED ─────────────────────────────────────────
    /// `FeedbackEngine.generate` calls `SetupAdvisor.bestAdvice`, which
    /// is 128 simulations. SetupAdvisor's own comment says "cheap enough
    /// for the main thread", and that is true of ONE call — but this is
    /// a computed property read from `body` inside a scrolling List, so
    /// it ran the advisor again on every single view invalidation, on
    /// the main actor, while the same advice was ALSO being computed off
    /// the main actor a few lines away.
    ///
    /// Found in external review 2026-09-16. A performance audit of this
    /// file had earlier called the debrief clean because the properties
    /// beside this one are populated by `.task`; this one is not.
    ///
    /// The cache key is the result hash plus whether the exhaustive
    /// solve has landed, because those are the only two things the
    /// feedback depends on. @ObservationIgnored is load-bearing: writing
    /// to an observed property from inside a getter that runs during
    /// `body` would invalidate the view that is currently evaluating.
    @ObservationIgnored private var feedbackCache: (key: String, value: EngineerFeedback)?

    var feedback: EngineerFeedback? {
        guard let result else { return nil }
        let key = feedbackKey(for: result)
        if let cached = feedbackCache, cached.key == key { return cached.value }
        let generated = FeedbackEngine.generate(
            result: result,
            challenge: challenge,
            optimalSectorTotalsMillis: analysis?.optimalSectorTotalsMillis
        )
        feedbackCache = (key, generated)
        return generated
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

    /// Open the sandbox on the car you actually raced.
    ///
    /// This screen has always described itself as "edit a copy of the
    /// locked setup", but the sandbox started EMPTY unless you arrived
    /// by the engineer's "Next test" shortcut. The plain Experiment
    /// button therefore asked you to rebuild all eight choices from
    /// nothing before anything could be run — and, now that the screen
    /// draws the car, to stare at an empty chassis while doing it.
    ///
    /// Idempotent, so navigating away and back keeps what you were
    /// trying rather than resetting you to the official setup.
    func beginExperimentIfNeeded() {
        guard phase == .submitted, experimentSelections.isEmpty else { return }
        experimentSelections = selections
        experimentResult = nil
    }

    func experimentSelectedOption(in category: EngineeringCategoryID) -> EngineeringOptionID? {
        experimentSelections[category]
    }

    func experimentCostDeltaIfComparable(for option: EngineeringOption) -> Int? {
        Self.delta(for: option, against: experimentSelections)
    }

    /// The sandbox car's profile against today's circuit — same chart
    /// the Bay draws while you build, so the read you carried out of
    /// the Bay still means the same thing here.
    var experimentLivePreview: VehicleProfile {
        let setup = PlayerSetup(challengeId: challenge.id, selectedOptions: experimentSelections)
        return VehicleProfile.from(setup: setup, circuit: challenge.circuit)
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
