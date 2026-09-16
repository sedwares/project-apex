//
//  DailyViewModelTests.swift
//  ProjectApexTests
//
//  Full state-machine coverage for the Daily loop. Replaces the
//  autocreated example() test. Uses a fixed challenge (day 1) so
//  every assertion is deterministic.
//

import XCTest
import ProjectApexCore
@testable import ProjectApex

/// In-memory store: tests never touch real UserDefaults.
@MainActor
final class InMemorySaveStore: DailySaveStore {
    var records: [String: DailyRecord] = [:]
    var lastDay = 0
    var streak = 0

    func loadRecord(forDateKey dateKey: String) -> DailyRecord? { records[dateKey] }
    func saveRecord(_ record: DailyRecord) { records[record.dateKey] = record }
    func registerCompletion(dayNumber: Int) {
        guard dayNumber != lastDay else { return }
        streak = (dayNumber == lastDay + 1) ? streak + 1 : 1
        lastDay = dayNumber
    }
    func currentStreak(asOfDayNumber dayNumber: Int) -> Int {
        (lastDay == dayNumber || lastDay == dayNumber - 1) ? streak : 0
    }
}

@MainActor
final class DailyViewModelTests: XCTestCase {

    /// `store` defaults to nil (not `InMemorySaveStore()`) — default
    /// arguments evaluate nonisolated, same rule as the ViewModel.
    private func makeViewModel(
        budget: Int? = nil,
        store: DailySaveStore? = nil
    ) -> DailyViewModel {
        let store = store ?? InMemorySaveStore()
        var challenge = ChallengeGenerator.generate(dayNumber: 1, dateKey: "test-day-1")
        if let budget {
            challenge = DailyChallenge(
                id: challenge.id, dateKey: challenge.dateKey, seed: challenge.seed,
                circuit: challenge.circuit, weather: challenge.weather,
                budget: budget, simulationVersion: challenge.simulationVersion
            )
        }
        return DailyViewModel(challenge: challenge, store: store)
    }

    private func selectAllBalanced(_ vm: DailyViewModel) {
        // 88 credits total (engineBalanced 13).
        vm.select(.engineBalanced)
        vm.select(.tiresMedium)
        vm.select(.aeroBalanced)
        vm.select(.suspensionBalanced)
        vm.select(.gearBalanced)
        vm.select(.coolingStandard)
        vm.select(.brakesBalanced)
        vm.select(.reliabilityBalanced)
    }

    // MARK: - Initial state

    func testInitialState() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.phase, .building)
        XCTAssertTrue(vm.selections.isEmpty)
        XCTAssertEqual(vm.totalCost, 0)
        XCTAssertFalse(vm.isComplete)
        XCTAssertFalse(vm.canSubmit)
        XCTAssertNil(vm.result)
        XCTAssertNil(vm.identityPreview)
    }

    // MARK: - Selection semantics

    func testSelectionReplacesWithinCategory() {
        let vm = makeViewModel()
        vm.select(.tiresSoft)
        XCTAssertEqual(vm.selectedOption(in: .tires), .tiresSoft)
        vm.select(.tiresHard)
        XCTAssertEqual(vm.selectedOption(in: .tires), .tiresHard)
        XCTAssertEqual(vm.selections.count, 1, "replacement, not accumulation")
    }

    func testReselectingSameOptionIsNoOpNotDeselect() {
        let vm = makeViewModel()
        vm.select(.tiresMedium)
        vm.select(.tiresMedium)
        XCTAssertEqual(vm.selectedOption(in: .tires), .tiresMedium)
    }

    func testCompleteSelectionEnablesSubmit() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        XCTAssertTrue(vm.isComplete)
        XCTAssertEqual(vm.totalCost, 88)
        XCTAssertFalse(vm.isOverBudget)
        XCTAssertTrue(vm.canSubmit)
        XCTAssertNotNil(vm.identityPreview)
    }

    // MARK: - Over-budget design (locked decision)

    func testOverBudgetSelectionIsAllowedButGatesSubmit() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.select(.enginePower)   // 13 → 25: total 100 → wait for tires
        vm.select(.tiresSoft)     // 12 → 21: pushes over
        XCTAssertTrue(vm.isComplete)
        XCTAssertTrue(vm.isOverBudget)
        XCTAssertEqual(vm.totalCost, 109)
        XCTAssertEqual(vm.remainingCredits, -9)
        XCTAssertFalse(vm.canSubmit, "over budget gates Submit, never the tap")
    }

    func testDroppingExpensiveOptionRestoresSubmit() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.select(.enginePower)
        vm.select(.tiresSoft)
        XCTAssertFalse(vm.canSubmit)
        vm.select(.engineEfficient) // 25 → 7
        XCTAssertFalse(vm.isOverBudget)
        XCTAssertTrue(vm.canSubmit)
    }

    func testCostDelta() {
        let vm = makeViewModel()
        let soft = OptionLibrary.option(.tiresSoft)  // 21
        let hard = OptionLibrary.option(.tiresHard)  // 8
        let medium = OptionLibrary.option(.tiresMedium) // 12

        // Nothing chosen in the category yet, so there is no change to
        // report — the row must print nothing rather than the option's
        // own price with a plus sign in front of it.
        XCTAssertNil(vm.costDeltaIfComparable(for: soft))

        vm.select(.tiresMedium)
        XCTAssertEqual(vm.costDeltaIfComparable(for: soft), 9)
        XCTAssertEqual(vm.costDeltaIfComparable(for: hard), -4)
        // Swapping a thing for itself is free, and "+0" is noise.
        XCTAssertNil(vm.costDeltaIfComparable(for: medium))
    }

    /// The sandbox prices against the sandbox car, not the raced one —
    /// otherwise every delta in the Experiment is measured from a setup
    /// you have already moved away from.
    func testExperimentCostDeltaUsesExperimentSelections() {
        // budget: overrides the generated challenge and drops its
        // regulation, so no ban can refuse a selection here.
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.select(.tiresHard)   // official: 8
        vm.submit()

        vm.preloadExperiment(category: .tires, option: .tiresMedium) // sandbox: 12
        let soft = OptionLibrary.option(.tiresSoft) // 21
        XCTAssertEqual(vm.experimentCostDeltaIfComparable(for: soft), 9)
        XCTAssertEqual(vm.costDeltaIfComparable(for: soft), 13)
    }

    func testExperimentOpensOnTheRacedSetupAndKeepsYourWork() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()

        vm.beginExperimentIfNeeded()
        XCTAssertEqual(vm.experimentSelections, vm.selections)

        // Wander off and come back: the sandbox is yours, not a reset.
        vm.experimentSelect(.tiresSoft)
        vm.beginExperimentIfNeeded()
        XCTAssertEqual(vm.experimentSelectedOption(in: .tires), .tiresSoft)
    }

    func testExperimentDoesNotOpenBeforeSubmit() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.beginExperimentIfNeeded()
        XCTAssertTrue(vm.experimentSelections.isEmpty)
    }

    // MARK: - Upgrading from a build before the install marker

    /// The highest-severity bug of the whole launch, caught in review
    /// before it shipped: build 22 read an absent `apex.install.seen` as
    /// "fresh install" and signed the player out. No previous build
    /// wrote that key, so EVERY existing tester would have lost their
    /// identity on update — new uid, orphaned leaderboard rows, and
    /// records owned by an account they no longer were.
    ///
    /// Deleting an app takes UserDefaults with it and leaves the
    /// keychain, so prior local data is the thing that tells the two
    /// cases apart.
    func testUpgradeIsNotMistakenForAFreshInstall() {
        let suite = UserDefaults(suiteName: "apex.tests.install")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "apex.tests.install") }
        for key in suite.dictionaryRepresentation().keys { suite.removeObject(forKey: key) }

        // A clean container: nothing has ever run here.
        XCTAssertFalse(
            FirebaseBootstrap.isUpgradeFromPreMarkerBuild(defaults: suite),
            "an empty container is a fresh install"
        )

        // Any one of these proves the app has run here before.
        // apex.notifications.* is in the list deliberately: it SURVIVES
        // clearLocalData, which is precisely how relying on the install
        // marker's absence to mean "deleted account" fell over.
        for key in ["apex.daily.2026-07-16", "apex.streak.current",
                    "apex.onboarding.seen", "apex.analytics.firstOpenDayNumber",
                    "apex.notifications.didRequestAuthorization",
                    "apex.challengeCache.2026-07-16"] {
            suite.set("x", forKey: key)
            XCTAssertTrue(
                FirebaseBootstrap.isUpgradeFromPreMarkerBuild(defaults: suite),
                "\(key) means this install has run before"
            )
            suite.removeObject(forKey: key)
        }

        // The marker itself must not count, or the check answers its
        // own question and every fresh install reads as an upgrade.
        suite.set(true, forKey: FirebaseBootstrap.installMarker)
        XCTAssertFalse(
            FirebaseBootstrap.isUpgradeFromPreMarkerBuild(defaults: suite),
            "the marker is not evidence of prior play"
        )

        // Nor is the pending-deletion note: it is bookkeeping too, and
        // counting it would let a queued deletion masquerade as play.
        suite.removeObject(forKey: FirebaseBootstrap.installMarker)
        suite.set("uid-A", forKey: FirebaseBootstrap.pendingDeletionUIDKey)
        XCTAssertFalse(
            FirebaseBootstrap.isUpgradeFromPreMarkerBuild(defaults: suite),
            "the pending-deletion note is not evidence of prior play"
        )

        // Somebody else's key is not ours.
        suite.removeObject(forKey: FirebaseBootstrap.pendingDeletionUIDKey)
        suite.set("x", forKey: "unrelated.setting")
        XCTAssertFalse(
            FirebaseBootstrap.isUpgradeFromPreMarkerBuild(defaults: suite),
            "only this app's own keys count"
        )
    }

    /// A queued deletion has to be stated, not inferred. clearLocalData
    /// must leave the note intact — it is the only thing standing
    /// between a failed `user.delete()` and signing straight back in as
    /// the account the backend is erasing.
    func testPendingDeletionNoteSurvivesLocalCleanup() {
        let suite = UserDefaults(suiteName: "apex.tests.pending")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "apex.tests.pending") }
        for key in suite.dictionaryRepresentation().keys { suite.removeObject(forKey: key) }

        suite.set("uid-being-deleted", forKey: FirebaseBootstrap.pendingDeletionUIDKey)
        suite.set("x", forKey: "apex.daily.2026-07-16")
        suite.set("x", forKey: "apex.streak.current")
        suite.set(true, forKey: "apex.onboarding.seen")
        suite.set(true, forKey: "apex.notifications.didRequestAuthorization")

        AccountDeletionService(defaults: suite).clearLocalData()

        XCTAssertEqual(
            FirebaseBootstrap.pendingDeletionUID(defaults: suite), "uid-being-deleted",
            "the rejected identity must outlive the cleanup that creates the risk"
        )
        XCTAssertNil(suite.object(forKey: "apex.daily.2026-07-16"))
        XCTAssertNil(suite.object(forKey: "apex.onboarding.seen"))
    }

    // MARK: - Links

    /// AppLinks.privacyPolicy is force-unwrapped, and the same URL has
    /// to match what is typed into App Store Connect. A broken literal
    /// would crash the Settings screen on tap; a changed one would
    /// silently disagree with the store listing.
    func testPrivacyPolicyLinkIsWellFormedAndHTTPS() {
        let url = AppLinks.privacyPolicy
        XCTAssertEqual(url.scheme, "https", "Apple requires https for the policy URL")
        XCTAssertEqual(url.host, "sedwares.github.io")
        XCTAssertEqual(url.absoluteString, "https://sedwares.github.io/project-apex/")
    }

    // MARK: - Account deletion (local half)

    /// The prefix list is deliberately prefix-based because daily
    /// records are keyed by date, so an explicit list would rot. That
    /// makes it worth pinning what it reaches — including the install
    /// marker, without which a device that could not delete its own auth
    /// user signs straight back in as the account just deleted.
    func testClearLocalDataRemovesEverythingTheAccountOwns() {
        let suite = UserDefaults(suiteName: "apex.tests.deletion")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "apex.tests.deletion") }
        for key in suite.dictionaryRepresentation().keys { suite.removeObject(forKey: key) }

        let owned = [
            "apex.daily.2026-07-16", "apex.daily.2026-07-17",
            "apex.streak.current", "apex.challengeCache.2026-07-16",
            "apex.onboarding.seen"
        ]
        for key in owned { suite.set("x", forKey: key) }
        suite.set(true, forKey: FirebaseBootstrap.installMarker)
        suite.set("keep me", forKey: "unrelated.setting")

        AccountDeletionService(defaults: suite).clearLocalData()

        for key in owned {
            XCTAssertNil(suite.object(forKey: key), "\(key) survived deletion")
        }

        // ── THE INSTALL MARKER MUST SURVIVE ─────────────────────
        // This assertion is INVERTED from what it was, deliberately.
        //
        // Build 22 cleared the marker here so the next launch would look
        // like a fresh install and mint a new identity. That inference
        // died when the upgrade detector arrived: it counts any apex.*
        // key as prior use, and apex.notifications.didRequestAuthorization
        // survives this method — so the next launch read as an upgrade
        // and restored the session being deleted.
        //
        // The marker is a fact about the INSTALL, not about the account.
        // The app has run on this device; clearing it was always a lie
        // told to influence a downstream decision. That decision is now
        // made from FirebaseBootstrap.pendingDeletionUIDKey, which says
        // outright which identity is rejected.
        XCTAssertNotNil(
            suite.object(forKey: FirebaseBootstrap.installMarker),
            "the marker records that this install has run, which is still true"
        )
        XCTAssertNotNil(
            suite.object(forKey: "unrelated.setting"),
            "deletion must not reach beyond the app's own keys"
        )
    }

    // MARK: - The day closing under an open session

    /// The reported failure: leave the app open across 00:00 UTC, submit,
    /// get a local record and a streak bump, and have Firestore reject
    /// the write against a day that has closed.
    func testSubmitRefusedOnceTheDayHasClosed() {
        // A REAL dateKey, unlike the shared fixture's "test-day-1":
        // the rollover check is calendar arithmetic and has nothing to
        // compare a synthetic key against.
        let vm = viewModelForDateKey("2026-07-16", budget: 100)
        selectAllBalanced(vm)
        XCTAssertTrue(vm.canSubmit)
        XCTAssertFalse(vm.isClosed)

        let tomorrow = utcNoon(2026, 7, 17)
        XCTAssertTrue(vm.refreshDayState(now: tomorrow), "state should change")
        XCTAssertTrue(vm.isClosed)
        XCTAssertFalse(vm.canSubmit)

        vm.submit()
        XCTAssertEqual(vm.phase, .building, "a closed day must not accept a submission")
        XCTAssertNil(vm.result)
    }

    func testRefreshDayStateReportsOnlyRealChanges() {
        let vm = viewModelForDateKey("2026-07-16", budget: 100)
        XCTAssertFalse(vm.refreshDayState(now: utcNoon(2026, 7, 16)), "same day, no change")
        let later = utcNoon(2026, 7, 17)
        XCTAssertTrue(vm.refreshDayState(now: later))
        XCTAssertFalse(vm.refreshDayState(now: later), "second call is a no-op")
    }

    /// A synthetic challenge has no calendar day to be past, so it must
    /// never read as closed — otherwise every practice surface and every
    /// test fixture locks itself out on construction.
    func testSyntheticChallengeIsNeverClosed() {
        let vm = makeViewModel(budget: 100)   // dateKey "test-day-1"
        XCTAssertFalse(vm.refreshDayState(now: Date().addingTimeInterval(10 * 86_400)))
        XCTAssertFalse(vm.isClosed)
    }

    private func viewModelForDateKey(_ dateKey: String, budget: Int) -> DailyViewModel {
        let day = ChallengeSeed.dayNumber(fromDateKey: dateKey)!
        let generated = ChallengeGenerator.generate(dayNumber: day, dateKey: dateKey)
        let challenge = DailyChallenge(
            id: generated.id, dateKey: generated.dateKey, seed: generated.seed,
            circuit: generated.circuit, weather: generated.weather,
            budget: budget, simulationVersion: generated.simulationVersion
        )
        return DailyViewModel(challenge: challenge, store: InMemorySaveStore())
    }

    private func utcNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12))!
    }

    func testMidnightCountdownIsPositiveAndWithinADay() {
        let seconds = DailyHomeView.secondsUntilNextUTCMidnight()
        XCTAssertNotNil(seconds)
        if let seconds {
            XCTAssertGreaterThan(seconds, 0)
            XCTAssertLessThanOrEqual(seconds, 24 * 60 * 60)
        }
    }

    // MARK: - Submit lock semantics

    func testSubmitBlockedWhenIncomplete() {
        let vm = makeViewModel()
        vm.select(.tiresMedium)
        vm.submit()
        XCTAssertEqual(vm.phase, .building)
        XCTAssertNil(vm.result)
    }

    func testSubmitLocksSelectionsAndProducesResult() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()

        XCTAssertEqual(vm.phase, .submitted)
        XCTAssertNotNil(vm.result)

        // Locked: further selection attempts are ignored.
        vm.select(.enginePower)
        XCTAssertEqual(vm.selectedOption(in: .engineMode), .engineBalanced)

        // Double-submit is a no-op.
        let firstResult = vm.result
        vm.submit()
        XCTAssertEqual(vm.result, firstResult)
    }

    func testSubmittedResultMatchesDirectEngineCall() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()

        let setup = PlayerSetup(
            challengeId: vm.challenge.id,
            selectedOptions: vm.selections
        )
        let direct = SimulationEngine.simulate(
            setup: setup,
            circuit: vm.challenge.circuit,
            weather: vm.challenge.weather
        )
        XCTAssertEqual(vm.result, direct, "ViewModel adds no nondeterminism")
    }

    // MARK: - Experiment sandbox

    func testExperimentSeedsFromOfficialSelectionsOnSubmit() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()
        XCTAssertEqual(vm.experimentSelections, vm.selections)
    }

    func testExperimentSelectBeforeSubmitIsIgnored() {
        let vm = makeViewModel()
        vm.experimentSelect(.tiresSoft)
        XCTAssertTrue(vm.experimentSelections.isEmpty)
        XCTAssertFalse(vm.canRunExperiment)
    }

    func testExperimentRunIsUnofficialAndDoesNotTouchResult() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()
        let official = vm.result

        vm.experimentSelect(.tiresHard) // 12 → 8, still legal
        vm.runExperiment()

        XCTAssertNotNil(vm.experimentResult)
        XCTAssertEqual(vm.result, official, "official result is sacred")
        XCTAssertEqual(vm.phase, .submitted)
        XCTAssertNotNil(vm.experimentDeltaMillis)
    }

    func testExperimentResultInvalidatesOnEdit() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()
        vm.runExperiment()
        XCTAssertNotNil(vm.experimentResult)
        vm.experimentSelect(.tiresHard)
        XCTAssertNil(vm.experimentResult, "stale result cleared on edit")
    }

    func testExperimentOverBudgetGatesRun() {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()
        vm.experimentSelect(.enginePower) // 13 → 25
        vm.experimentSelect(.tiresSoft)   // 12 → 21: over
        XCTAssertTrue(vm.experimentIsOverBudget)
        XCTAssertFalse(vm.canRunExperiment)
        vm.runExperiment()
        XCTAssertNil(vm.experimentResult)
    }

    // MARK: - Analysis

    func testLoadAnalysisComputesOptimum() async {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()
        await vm.loadAnalysis()

        let analysis = try! XCTUnwrap(vm.analysis)
        XCTAssertLessThanOrEqual(
            analysis.minPossibleAverageLapMillis,
            vm.result!.averageLapTimeMillis,
            "optimum can't be slower than the player"
        )
        XCTAssertEqual(
            analysis.gapToOptimalMillis,
            vm.result!.averageLapTimeMillis - analysis.minPossibleAverageLapMillis
        )
        XCTAssertTrue((0...100).contains(analysis.beatPercent))
        XCTAssertLessThanOrEqual(analysis.optimalSetup.totalCost, vm.budget)
    }

    func testLoadAnalysisBeforeSubmitIsNoOp() async {
        let vm = makeViewModel()
        await vm.loadAnalysis()
        XCTAssertNil(vm.analysis)
    }

    // MARK: - Share

    func testShareTextNilBeforeSubmit() {
        let vm = makeViewModel()
        XCTAssertNil(vm.shareText)
    }

    func testShareTextContainsResultsButNeverThePicks() async {
        let vm = makeViewModel(budget: 100)
        selectAllBalanced(vm)
        vm.submit()
        await vm.loadAnalysis()

        let text = try! XCTUnwrap(vm.shareText)
        // What it must say:
        XCTAssertTrue(text.contains("Project Apex"))
        XCTAssertTrue(text.contains("Average Lap:"))
        XCTAssertTrue(text.contains("Better than \(vm.analysis!.beatPercent)% of possible setups"))
        XCTAssertTrue(text.contains(vm.result!.setupIdentity.displayText))
        XCTAssertTrue(text.contains("Did you do today's Apex?"))
        // What it must never leak — the actual option picks
        // (identity words like "Balanced" are fine; picks are not):
        XCTAssertFalse(text.contains("Medium"), "tire pick leaked")
        XCTAssertFalse(text.contains("Standard"), "cooling pick leaked")
        XCTAssertFalse(text.contains("Engine Mode"), "category detail leaked")
    }

    // MARK: - Reveal gating (competitive integrity)

    func testRevealGatedUntilDayCloses() {
        func viewModel(dateKey: String) -> DailyViewModel {
            let day = ChallengeSeed.dayNumber(fromDateKey: dateKey)!
            let challenge = ChallengeGenerator.generate(dayNumber: day, dateKey: dateKey)
            return DailyViewModel(challenge: challenge, store: InMemorySaveStore())
        }
        // "now" fixed at 2026-07-16 12:00 UTC.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))!

        XCTAssertFalse(viewModel(dateKey: "2026-07-16").isRevealAllowed(now: now), "live day stays sealed")
        XCTAssertFalse(viewModel(dateKey: "2026-07-17").isRevealAllowed(now: now), "future stays sealed")
        XCTAssertTrue(viewModel(dateKey: "2026-07-15").isRevealAllowed(now: now), "yesterday reveals")
    }

    // MARK: - Persistence

    func testSubmitPersistsRecord() {
        let store = InMemorySaveStore()
        let vm = makeViewModel(budget: 100, store: store)
        selectAllBalanced(vm)
        vm.submit()

        let record = store.records[vm.challenge.dateKey]
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.selections, vm.selections)
        XCTAssertEqual(record?.result, vm.result)
    }

    func testNoPersistenceBeforeSubmit() {
        let store = InMemorySaveStore()
        let vm = makeViewModel(budget: 100, store: store)
        selectAllBalanced(vm)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testRestoredDayIsSubmittedWithIdenticalResult() {
        let store = InMemorySaveStore()
        let first = makeViewModel(budget: 100, store: store)
        selectAllBalanced(first)
        first.submit()
        let officialResult = first.result

        // Fresh ViewModel, same store: relaunch simulation.
        let restored = makeViewModel(budget: 100, store: store)
        XCTAssertEqual(restored.phase, .submitted)
        XCTAssertEqual(restored.result, officialResult, "determinism: restored == raced")
        XCTAssertEqual(restored.selections, first.selections)
        XCTAssertFalse(restored.canSubmit, "no second official submission")
        XCTAssertEqual(restored.experimentSelections, first.selections,
                       "experiment re-seeded from the locked setup")
    }

    func testStreakCountsConsecutiveDaysAndResets() {
        let store = InMemorySaveStore()
        store.registerCompletion(dayNumber: 10)
        XCTAssertEqual(store.currentStreak(asOfDayNumber: 10), 1)
        store.registerCompletion(dayNumber: 11)
        XCTAssertEqual(store.currentStreak(asOfDayNumber: 11), 2)
        store.registerCompletion(dayNumber: 11) // duplicate: no-op
        XCTAssertEqual(store.currentStreak(asOfDayNumber: 11), 2)
        XCTAssertEqual(store.currentStreak(asOfDayNumber: 12), 2, "alive through 'yesterday'")
        XCTAssertEqual(store.currentStreak(asOfDayNumber: 14), 0, "gap kills it")
        store.registerCompletion(dayNumber: 14)
        XCTAssertEqual(store.currentStreak(asOfDayNumber: 14), 1, "reset, not resumed")
    }

    // MARK: - A record that belongs to a previous account

    /// Counts submissions, so a test can prove one did NOT happen.
    @MainActor
    private final class SpyLeaderboard: LeaderboardServicing {
        var submitCount = 0
        var standingCount = 0
        func submitAndStand(record: DailyRecord, uid: String,
                            displayName: String) async throws -> LeaderboardStanding {
            submitCount += 1
            return LeaderboardStanding(rank: 1, totalEntries: 1, tieCount: 1)
        }
        func standing(dateKey: String, uid: String) async throws -> LeaderboardStanding {
            standingCount += 1
            return LeaderboardStanding(rank: 1, totalEntries: 1, tieCount: 1)
        }
        func topEntries(dateKey: String, limit: Int,
                        uid: String) async throws -> [LeaderboardRow] { [] }
    }

    private func viewModelWithLeaderboard(
        store: DailySaveStore, leaderboard: LeaderboardServicing, uid: String
    ) -> DailyViewModel {
        let challenge = ChallengeGenerator.generate(dayNumber: 1, dateKey: "test-day-1")
        return DailyViewModel(
            challenge: challenge, store: store, leaderboard: leaderboard,
            uid: uid, displayName: "ENG-000000"
        )
    }

    /// The reported scenario: the account is deleted server-side, the
    /// next launch signs in as somebody new, and today's record is still
    /// on the device. Re-submitting it would put one person on the same
    /// day's board twice.
    func testStandingIsNotResubmittedUnderANewAccount() async {
        let store = InMemorySaveStore()
        let spy = SpyLeaderboard()

        let first = viewModelWithLeaderboard(store: store, leaderboard: spy, uid: "uid-A")
        selectAllBalanced(first)
        first.submit()
        XCTAssertEqual(store.records["test-day-1"]?.submittedByUID, "uid-A",
                       "submit must stamp the owner")

        // Same device, same record, different account.
        let second = viewModelWithLeaderboard(store: store, leaderboard: spy, uid: "uid-B")
        XCTAssertEqual(second.phase, .submitted, "the result is still this device's")
        let before = spy.submitCount
        await second.refreshStanding()

        XCTAssertEqual(spy.submitCount, before, "must not write a second entry")
        XCTAssertEqual(second.standingState, .belongsToPreviousAccount)
    }

    /// The same account still ranks normally — the guard must not break
    /// the ordinary path.
    func testStandingStillSubmitsForTheSameAccount() async {
        let store = InMemorySaveStore()
        let spy = SpyLeaderboard()
        let vm = viewModelWithLeaderboard(store: store, leaderboard: spy, uid: "uid-A")
        selectAllBalanced(vm)
        vm.submit()

        let again = viewModelWithLeaderboard(store: store, leaderboard: spy, uid: "uid-A")
        await again.refreshStanding()
        XCTAssertGreaterThan(spy.submitCount, 0, "the owner must still be able to rank")
    }

    /// Records written before build 24 carry no owner. They are legacy,
    /// not foreign, and must keep ranking.
    func testLegacyRecordWithoutAnOwnerStillRanks() async {
        let store = InMemorySaveStore()
        let spy = SpyLeaderboard()
        let vm = viewModelWithLeaderboard(store: store, leaderboard: spy, uid: "uid-A")
        selectAllBalanced(vm)
        vm.submit()

        let r = store.records["test-day-1"]!
        store.records["test-day-1"] = DailyRecord(
            dateKey: r.dateKey, selections: r.selections, result: r.result,
            submittedAt: r.submittedAt, simulationVersion: r.simulationVersion,
            submittedByUID: nil
        )

        let restored = viewModelWithLeaderboard(store: store, leaderboard: spy, uid: "uid-B")
        await restored.refreshStanding()
        XCTAssertGreaterThan(spy.submitCount, 0, "an unowned record is ours by default")
    }

    func testRestoreIgnoredOnSimulationVersionMismatch() {
        let store = InMemorySaveStore()
        let vm = makeViewModel(budget: 100, store: store)
        selectAllBalanced(vm)
        vm.submit()

        // Rewrite the stored record as if from an older simulation.
        let record = store.records[vm.challenge.dateKey]!
        store.records[vm.challenge.dateKey] = DailyRecord(
            dateKey: record.dateKey,
            selections: record.selections,
            result: record.result,
            submittedAt: record.submittedAt,
            simulationVersion: "sim-0.9.9"
        )

        let restored = makeViewModel(budget: 100, store: store)
        XCTAssertEqual(restored.phase, .building, "stale-version record must be ignored")
        XCTAssertNil(restored.result)
    }

    func testLegacyRecordWithoutVersionStillRestores() {
        let store = InMemorySaveStore()
        let vm = makeViewModel(budget: 100, store: store)
        selectAllBalanced(vm)
        vm.submit()

        let record = store.records[vm.challenge.dateKey]!
        store.records[vm.challenge.dateKey] = DailyRecord(
            dateKey: record.dateKey,
            selections: record.selections,
            result: record.result,
            submittedAt: record.submittedAt,
            simulationVersion: nil // pre-versioning legacy
        )
        let restored = makeViewModel(budget: 100, store: store)
        XCTAssertEqual(restored.phase, .submitted, "legacy records are trusted")
    }

}
