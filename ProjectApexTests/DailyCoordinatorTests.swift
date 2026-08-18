//
//  DailyCoordinatorTests.swift
//  ProjectApexTests
//
//  Every coordinator state, driven by mocks — no Firebase in tests.
//

import XCTest
import ProjectApexCore
@testable import ProjectApex

@MainActor
final class MockChallengeProvider: ChallengeProviding {
    var result: Result<DailyChallenge, ChallengeLoadError>
    init(_ result: Result<DailyChallenge, ChallengeLoadError>) { self.result = result }
    func challenge(forDateKey dateKey: String) async throws -> DailyChallenge {
        try result.get()
    }
}

@MainActor
final class MockLeaderboard: LeaderboardServicing {
    var standing = LeaderboardStanding(rank: 7, totalEntries: 100, tieCount: 3)
    var submitCalls = 0
    var shouldFail = false

    func submitAndStand(record: DailyRecord, uid: String, displayName: String) async throws -> LeaderboardStanding {
        submitCalls += 1
        if shouldFail { throw ChallengeLoadError.unavailable }
        return standing
    }
    func standing(dateKey: String, uid: String) async throws -> LeaderboardStanding { standing }
    func topEntries(dateKey: String, limit: Int, uid: String) async throws -> [LeaderboardRow] { [] }
}

/// R4 test harness: first request parks on a continuation until
/// released; subsequent requests resolve instantly.
@MainActor
final class ControlledMockProvider: ChallengeProviding {
    var instant: Result<DailyChallenge, ChallengeLoadError>?
    private var parked: CheckedContinuation<DailyChallenge, Error>?
    private var requestedContinuation: CheckedContinuation<Void, Never>?
    private var hasParked = false

    func challenge(forDateKey dateKey: String) async throws -> DailyChallenge {
        if hasParked, let instant {
            return try instant.get()
        }
        hasParked = true
        requestedContinuation?.resume()
        requestedContinuation = nil
        return try await withCheckedThrowingContinuation { parked = $0 }
    }

    func waitUntilRequested() async {
        if hasParked { return }
        await withCheckedContinuation { requestedContinuation = $0 }
    }

    func release(with result: Result<DailyChallenge, ChallengeLoadError>) {
        switch result {
        case .success(let challenge): parked?.resume(returning: challenge)
        case .failure(let error): parked?.resume(throwing: error)
        }
        parked = nil
    }
}

@MainActor
final class DailyCoordinatorTests: XCTestCase {

    private var testChallenge: DailyChallenge {
        ChallengeGenerator.generate(dayNumber: 1, dateKey: "test-day-1")
    }

    private func makeCoordinator(
        provider: any ChallengeProviding,
        leaderboard: MockLeaderboard? = nil
    ) -> DailyCoordinator {
        let leaderboard = leaderboard ?? MockLeaderboard()
        return DailyCoordinator(
            challengeProvider: provider,
            leaderboard: leaderboard,
            store: InMemorySaveStore(),
            signIn: { (uid: "test-uid", displayName: "ENG-0001") }
        )
    }

    func testReadyStateOnSuccessfulFetch() async {
        let coordinator = makeCoordinator(provider: MockChallengeProvider(.success(testChallenge)))
        await coordinator.load(dateKey: "test-day-1")
        guard case .ready(let vm) = coordinator.state else {
            return XCTFail("expected .ready, got \(coordinator.state)")
        }
        XCTAssertEqual(vm.challenge, testChallenge)
        XCTAssertEqual(coordinator.uid, "test-uid")
        XCTAssertEqual(coordinator.displayName, "ENG-0001")
    }

    func testUnavailableStateOnFetchFailure() async {
        let coordinator = makeCoordinator(provider: MockChallengeProvider(.failure(.unavailable)))
        await coordinator.load(dateKey: "test-day-1")
        guard case .unavailable = coordinator.state else {
            return XCTFail("expected .unavailable, got \(coordinator.state)")
        }
    }

    func testUpdateRequiredState() async {
        let coordinator = makeCoordinator(provider: MockChallengeProvider(.failure(.updateRequired)))
        await coordinator.load(dateKey: "test-day-1")
        guard case .updateRequired = coordinator.state else {
            return XCTFail("expected .updateRequired, got \(coordinator.state)")
        }
    }

    func testUnavailableWhenSignInFails() async {
        let coordinator = DailyCoordinator(
            challengeProvider: MockChallengeProvider(.success(testChallenge)),
            leaderboard: MockLeaderboard(),
            store: InMemorySaveStore(),
            signIn: { throw ChallengeLoadError.unavailable }
        )
        await coordinator.load(dateKey: "test-day-1")
        guard case .unavailable = coordinator.state else {
            return XCTFail("expected .unavailable, got \(coordinator.state)")
        }
    }

    // MARK: - ViewModel standing flow (through the coordinator's wiring)

    func testSubmitUploadsAndLoadsStanding() async {
        let leaderboard = MockLeaderboard()
        let coordinator = makeCoordinator(
            provider: MockChallengeProvider(.success(testChallenge)),
            leaderboard: leaderboard
        )
        await coordinator.load(dateKey: "test-day-1")
        guard case .ready(let vm) = coordinator.state else { return XCTFail() }

        vm.select(.engineBalanced); vm.select(.tiresMedium)
        vm.select(.aeroBalanced); vm.select(.suspensionBalanced)
        vm.select(.gearBalanced); vm.select(.coolingStandard)
        vm.select(.brakesBalanced); vm.select(.reliabilityBalanced)
        vm.submit()
        await vm.refreshStanding() // deterministic wait (submit's Task races the test)

        XCTAssertGreaterThanOrEqual(leaderboard.submitCalls, 1)
        XCTAssertEqual(vm.standingState, .loaded(leaderboard.standing))
    }

    func testStandingFailureIsRetryable() async {
        let leaderboard = MockLeaderboard()
        leaderboard.shouldFail = true
        let coordinator = makeCoordinator(
            provider: MockChallengeProvider(.success(testChallenge)),
            leaderboard: leaderboard
        )
        await coordinator.load(dateKey: "test-day-1")
        guard case .ready(let vm) = coordinator.state else { return XCTFail() }

        vm.select(.engineBalanced); vm.select(.tiresMedium)
        vm.select(.aeroBalanced); vm.select(.suspensionBalanced)
        vm.select(.gearBalanced); vm.select(.coolingStandard)
        vm.select(.brakesBalanced); vm.select(.reliabilityBalanced)
        vm.submit()
        await vm.refreshStanding()
        // Match the case, not the value: .failed now carries Firestore's
        // own wording, which isn't a stable thing to assert on.
        guard case .failed = vm.standingState else {
            return XCTFail("expected .failed, got \(vm.standingState)")
        }

        leaderboard.shouldFail = false
        await vm.refreshStanding()
        XCTAssertEqual(vm.standingState, .loaded(leaderboard.standing))
    }

    // R5: never trust backend data blindly.
    func testMismatchedDateKeyBecomesUnavailable() async {
        // Provider returns day-1's challenge regardless of what we ask for.
        let coordinator = makeCoordinator(provider: MockChallengeProvider(.success(testChallenge)))
        await coordinator.load(dateKey: "some-other-day")
        guard case .unavailable = coordinator.state else {
            return XCTFail("expected .unavailable on dateKey mismatch, got \(coordinator.state)")
        }
    }

    // R4: only the newest load may write state.
    func testOverlappingLoadsNewestWins() async {
        let slowProvider = ControlledMockProvider()
        let coordinator = makeCoordinator(provider: slowProvider)

        // Load 1: will be held until we release it.
        let first = Task { await coordinator.load(dateKey: "test-day-1") }
        await slowProvider.waitUntilRequested()

        // Load 2: fails fast -> .unavailable is the NEWEST truth.
        slowProvider.instant = .failure(.unavailable)
        await coordinator.load(dateKey: "test-day-1")
        guard case .unavailable = coordinator.state else {
            return XCTFail("expected .unavailable from load 2")
        }

        // Release load 1 with a success; it must NOT overwrite load 2.
        slowProvider.release(with: .success(testChallenge))
        await first.value
        guard case .unavailable = coordinator.state else {
            return XCTFail("stale load 1 overwrote newer state: \(coordinator.state)")
        }
    }

    func testCallsignIsStablePerUid() {
        let a = FirebaseBootstrap.callsign(for: "some-uid-123")
        let b = FirebaseBootstrap.callsign(for: "some-uid-123")
        let c = FirebaseBootstrap.callsign(for: "different-uid")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.hasPrefix("ENG-"))
        XCTAssertEqual(a.count, 10) // ENG- + 6 digits (R13)
    }
}

@MainActor
final class ChallengeDocumentMapperTests: XCTestCase {

    func testRoundTripThroughFirestoreShape() {
        let original = ChallengeGenerator.generate(dayNumber: 197, dateKey: "2026-07-16")
            .finalized(minPossibleAverageLapMillis: 86_301)

        // Simulate the decoded Firestore document shape. Every field
        // apex-publish writes must appear here — this fixture IS the
        // contract, and it caught apex-publish omitting bannedOption
        // entirely, which would have shipped every day unregulated.
        let data: [String: Any] = [
            "dateKey": original.dateKey,
            "seed": String(original.seed),
            "weather": original.weather.rawValue,
            "budget": original.budget,
            "simulationVersion": original.simulationVersion,
            "minPossibleAverageLapMillis": original.minPossibleAverageLapMillis,
            "bannedOption": original.bannedOption?.rawValue ?? "",
            "circuit": [
                "id": original.circuit.id,
                "name": original.circuit.name,
                "archetype": original.circuit.archetype.rawValue,
                "sections": original.circuit.sections.map(\.rawValue)
            ] as [String: Any]
        ]

        let decoded = ChallengeDocumentMapper.challenge(from: data)
        XCTAssertEqual(decoded, original, "server round-trip must be lossless")
        XCTAssertNotNil(
            original.bannedOption,
            "day 197 should carry a regulation — if this trips, the round trip above "
                + "is no longer exercising the field that was silently dropped"
        )
    }

    /// A document missing `bannedOption` is MALFORMED, not "unrestricted".
    ///
    /// Leniency here is what let apex-publish omit the field unnoticed:
    /// the client would have played unregulated days forever with nothing
    /// reporting a problem. The security rules also dereference this
    /// field on every leaderboard write, so an absent one denies every
    /// submission for that day — failing loudly at load is far better.
    func testDocumentWithoutRegulationFieldIsRejected() {
        let original = ChallengeGenerator.generate(dayNumber: 197, dateKey: "2026-07-16")
            .finalized(minPossibleAverageLapMillis: 86_301)
        let missingRegulation: [String: Any] = [
            "dateKey": original.dateKey,
            "seed": String(original.seed),
            "weather": original.weather.rawValue,
            "budget": original.budget,
            "simulationVersion": original.simulationVersion,
            "minPossibleAverageLapMillis": original.minPossibleAverageLapMillis,
            "circuit": [
                "id": original.circuit.id,
                "name": original.circuit.name,
                "archetype": original.circuit.archetype.rawValue,
                "sections": original.circuit.sections.map(\.rawValue)
            ] as [String: Any]
        ]
        XCTAssertNil(ChallengeDocumentMapper.challenge(from: missingRegulation))
    }

    func testUnrestrictedDayDecodesAsNoRegulation() {
        let original = ChallengeGenerator.generate(dayNumber: 197, dateKey: "2026-07-16")
        let data: [String: Any] = [
            "dateKey": original.dateKey,
            "seed": String(original.seed),
            "weather": original.weather.rawValue,
            "budget": original.budget,
            "simulationVersion": original.simulationVersion,
            "minPossibleAverageLapMillis": 0,
            "bannedOption": "",            // explicitly unrestricted
            "circuit": [
                "id": original.circuit.id,
                "name": original.circuit.name,
                "archetype": original.circuit.archetype.rawValue,
                "sections": original.circuit.sections.map(\.rawValue)
            ] as [String: Any]
        ]
        XCTAssertNil(ChallengeDocumentMapper.challenge(from: data)?.bannedOption)
    }

    func testMalformedDocumentReturnsNil() {
        XCTAssertNil(ChallengeDocumentMapper.challenge(from: ["dateKey": "x"]))
        XCTAssertNil(ChallengeDocumentMapper.challenge(from: [:]))
    }
}
