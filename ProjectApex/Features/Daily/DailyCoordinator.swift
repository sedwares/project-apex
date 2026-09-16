//
//  DailyCoordinator.swift
//  ProjectApex
//
//  Owns the async lifecycle of the Daily: sign in, fetch the official
//  challenge, build the DailyViewModel. The Home view renders whatever
//  state this is in. Protocol-injected so tests drive every state.
//
//  Also owns yesterday's optimal-setup reveal — deliberately NOT part
//  of State, so a failure there can never take today's brief down.
//

import Foundation
import Observation
import ProjectApexCore

@MainActor
@Observable
final class DailyCoordinator {

    enum State {
        case loading
        case ready(DailyViewModel)
        case unavailable(message: String)
        case updateRequired
    }

    /// Yesterday's answer, unlocked. nil means no card, for any reason:
    /// didn't play, simulation version moved, official document not
    /// cached, regeneration failed.
    struct YesterdayReveal: Equatable {
        let dayNumber: Int
        let optimalSelections: [EngineeringCategoryID: EngineeringOptionID]
        /// What the player actually raced, for side-by-side comparison.
        let yourSelections: [EngineeringCategoryID: EngineeringOptionID]
        let optimalAverageLapMillis: Int
        let yourAverageLapMillis: Int
        let beatPercent: Int
        /// The regulation that was in force, if any — without it the
        /// card can look wrong ("why didn't it pick Soft?").
        let bannedOption: EngineeringOptionID?

        var gapMillis: Int { yourAverageLapMillis - optimalAverageLapMillis }

        /// Systems where the player picked the optimal option.
        var matchedCount: Int {
            EngineeringCategoryID.allCases.reduce(into: 0) { count, category in
                if let optimal = optimalSelections[category],
                   yourSelections[category] == optimal {
                    count += 1
                }
            }
        }
    }

    /// DEBUG-only: flip to true to develop without the backend.
    /// Off by default so real-path bugs aren't masked (Decision 4).
    ///
    /// Back to false now that apex-publish has republished every day at
    /// sim-1.1.0 with a `bannedOption` field. It was briefly true so the
    /// simulator could play the new simulation against old documents —
    /// and that is exactly the hazard this flag carries: with it on, the
    /// app generates its own challenge and never notices that the
    /// published one is stale, missing, or rejected. Turn it on only to
    /// work offline, and turn it off before believing anything about the
    /// leaderboard.
    static let useLocalFallbackInDebug = false

    private(set) var state: State = .loading
    /// R4: each load claims a generation; only the newest may write
    /// state, so overlapping retries / a UTC rollover can't let a
    /// stale response stomp fresh state.
    private var loadGeneration = 0
    private(set) var uid: String?
    private(set) var displayName: String?

    private(set) var yesterdayReveal: YesterdayReveal?
    private var yesterdayLoading = false

    private let challengeProvider: ChallengeProviding?
    private let leaderboard: LeaderboardServicing?
    private let store: DailySaveStore?
    private let signIn: (() async throws -> (uid: String, displayName: String))?

    /// Production init: nils resolve to live services at load time.
    /// Tests inject all four.
    init(
        challengeProvider: ChallengeProviding? = nil,
        leaderboard: LeaderboardServicing? = nil,
        store: DailySaveStore? = nil,
        signIn: (() async throws -> (uid: String, displayName: String))? = nil
    ) {
        self.challengeProvider = challengeProvider
        self.leaderboard = leaderboard
        self.store = store
        self.signIn = signIn
    }

    /// nonisolated: pure date math, and it's used as a default
    /// argument (default args evaluate outside the actor).
    nonisolated static func todayDateKey(now: Date = Date()) -> String {
        UTCDateKey.make(from: now)
    }

    /// The dateKey the current `state` was built for. Compared against
    /// the wall clock to notice a rollover.
    private(set) var loadedDateKey: String?

    /// True when UTC has moved past the day we loaded.
    var hasRolledOver: Bool {
        guard let loadedDateKey else { return false }
        return loadedDateKey != Self.todayDateKey()
    }

    /// Reload only if the calendar moved. Cheap to call on every
    /// foreground: on the overwhelmingly common path it does nothing.
    ///
    /// Without this the app had no lifecycle at all — no scenePhase
    /// observer, no timer, nothing — so a session left open across
    /// 00:00 UTC kept yesterday's challenge indefinitely.
    func reloadIfDayChanged() async {
        guard hasRolledOver else { return }
        DebugLog.log("UTC rollover: \(loadedDateKey ?? "-") -> \(Self.todayDateKey())")
        // Yesterday is a different yesterday now. Clearing alone was a
        // bug: `loadYesterdayReveal` returns early unless the reveal is
        // nil AND nothing else is loading, and nothing re-calls it on
        // this path — the home view's `.task` already ran and will not
        // run again — so the card simply vanished until the next cold
        // start. Clear, then refetch.
        yesterdayReveal = nil
        await load()
        await loadYesterdayReveal()
    }

    func load(dateKey: String = DailyCoordinator.todayDateKey()) async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        // Identity first (anonymous, cached after first launch).
        do {
            let identity = try await (signIn ?? { try await FirebaseBootstrap.ensureSignedIn() })()
            guard generation == loadGeneration else { return }
            uid = identity.uid
            displayName = identity.displayName
            CrashReporting.setUserID(identity.uid)
        } catch {
            DebugLog.log("sign-in failed", error)
            guard generation == loadGeneration else { return }
            state = .unavailable(message: "Couldn't reach the paddock. Check your connection and try again.")
            return
        }

        let provider = challengeProvider ?? liveProvider()
        do {
            let challenge = try await provider.challenge(forDateKey: dateKey)
            guard generation == loadGeneration else { return }

            // R5: never trust backend data blindly — the returned
            // document must be the day we asked for.
            guard challenge.dateKey == dateKey else {
                DebugLog.log("challenge dateKey mismatch: asked \(dateKey), got \(challenge.dateKey)")
                state = .unavailable(message: "Today's challenge isn't available right now. Quick Race works offline.")
                return
            }

            // A regulation that prices the day out of its own budget
            // would leave the player with no legal setup at all. The
            // publishing job checks this, but the client refusing to
            // render an impossible day is cheaper than a support ticket.
            guard challenge.isSatisfiable else {
                DebugLog.log("challenge not satisfiable: budget \(challenge.budget) below regulated minimum")
                state = .unavailable(message: "Today's challenge isn't available right now. Quick Race works offline.")
                return
            }

            let viewModel = DailyViewModel(
                challenge: challenge,
                store: store,
                leaderboard: leaderboard ?? FirestoreLeaderboardService(),
                uid: uid,
                displayName: displayName
            )
            viewModel.refreshDayState()
            loadedDateKey = dateKey
            state = .ready(viewModel)
        } catch ChallengeLoadError.updateRequired {
            guard generation == loadGeneration else { return }
            state = .updateRequired
        } catch {
            DebugLog.log("challenge load failed for \(dateKey)", error)
            guard generation == loadGeneration else { return }
            state = .unavailable(message: "Today's challenge isn't available right now. Quick Race works offline.")
        }
    }

    // MARK: - Yesterday's reveal (local, no network)

    /// Re-solves yesterday's challenge and compares it to what the
    /// player raced.
    ///
    /// PASS 6: reads the OFFICIAL document from the challenge cache
    /// rather than regenerating it with ChallengeGenerator. The old
    /// path worked only while every published day matched the
    /// generator's canonical draw — the moment a day is hand-tuned or
    /// re-rolled (ChallengeGenerator's `nonce`), regeneration produces
    /// a different circuit and the card confidently shows the optimal
    /// setup for a challenge nobody played. If yesterday isn't cached
    /// (fresh install, cache cleared), there's simply no card.
    ///
    /// Runs in its own Task from the view: a slow solve must never
    /// delay today's brief.
    func loadYesterdayReveal(now: Date = Date()) async {
        guard yesterdayReveal == nil, !yesterdayLoading else { return }
        yesterdayLoading = true
        defer { yesterdayLoading = false }

        // UTC arithmetic, matching todayDateKey()'s boundary. UTC has
        // no DST, so -86400 is exact — Calendar math would not be.
        let yesterdayKey = UTCDateKey.make(from: now.addingTimeInterval(-86_400))
        guard let day = ChallengeSeed.dayNumber(fromDateKey: yesterdayKey) else { return }

        // No record = didn't play yesterday. No card, no guilt trip.
        let saveStore = store ?? UserDefaultsSaveStore()
        guard let record = saveStore.loadRecord(forDateKey: yesterdayKey) else {
            DebugLog.log("yesterday reveal: no saved record for \(yesterdayKey)")
            return
        }

        do {
            let provider = challengeProvider ?? CachedOfficialChallengeService()
            let challenge = try await provider.challenge(forDateKey: yesterdayKey)
            guard challenge.dateKey == yesterdayKey else {
                DebugLog.log("yesterday dateKey mismatch: asked \(yesterdayKey), got \(challenge.dateKey)")
                return
            }

            // Same guard as restoreIfSubmitted: a record from another
            // simulation isn't comparable to this solve.
            if let recordVersion = record.simulationVersion,
               recordVersion != challenge.simulationVersion {
                DebugLog.log("yesterday reveal skipped: version \(recordVersion) vs \(challenge.simulationVersion)")
                return
            }

            let playerAverage = record.result.averageLapTimeMillis
            let analysis = await Task.detached(priority: .utility) {
                DayAnalyzer.analyze(
                    challenge: challenge,
                    playerAverageLapMillis: playerAverage
                )
            }.value

            yesterdayReveal = YesterdayReveal(
                dayNumber: day,
                optimalSelections: analysis.optimalSetup.selectedOptions,
                yourSelections: record.selections,
                optimalAverageLapMillis: analysis.minPossibleAverageLapMillis,
                yourAverageLapMillis: playerAverage,
                beatPercent: analysis.beatPercent,
                bannedOption: challenge.bannedOption
            )
        } catch {
            // Most often: the official document for yesterday was never
            // cached, because the app wasn't opened yesterday. Correct
            // behaviour — there is nothing trustworthy to reveal — but
            // worth logging, since "no card" and "broken card" look
            // identical from the outside.
            DebugLog.log("yesterday reveal: no cached official challenge for \(yesterdayKey)", error)
        }
    }

    private func liveProvider() -> ChallengeProviding {
        #if DEBUG
        if Self.useLocalFallbackInDebug { return LocalChallengeService() }
        #endif
        return FirestoreChallengeService()
    }
}
