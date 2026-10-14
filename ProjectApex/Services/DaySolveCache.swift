//
//  DaySolveCache.swift
//  ProjectApex
//
//  One exhaustive solve per day, shared.
//
//  Three places now want the solved field: the bay (medal targets
//  before you lock), the race (your medal at the flag) and the debrief
//  (beat-%, the optimum, sector comparison). Each used to be — or
//  would have been — its own 6,561-setup run. This keeps the most
//  recent days' outcomes and hands concurrent callers the same
//  in-flight task, so a player who locks quickly still pays for one
//  solve, not three.
//

import Foundation
import ProjectApexCore

actor DaySolveCache {

    static let shared = DaySolveCache()

    struct Solved: Sendable {
        let outcome: SolverOutcome
        let targets: DayTargets
    }

    /// A solved field is a few MB; two days covers today and the
    /// midnight crossover.
    private let capacity = 2
    private var cache: [String: Solved] = [:]
    private var order: [String] = []
    private var inflight: [String: Task<Solved, Never>] = [:]

    private static func key(_ challenge: DailyChallenge) -> String {
        "\(challenge.id)|\(challenge.dateKey)|\(challenge.simulationVersion)"
    }

    func solved(_ challenge: DailyChallenge) async -> Solved {
        let key = Self.key(challenge)
        if let hit = cache[key] { return hit }
        if let running = inflight[key] { return await running.value }

        // .utility: this often runs while the race is animating, and a
        // dropped frame there costs more than a second's wait here.
        let task = Task.detached(priority: .utility) { () -> Solved in
            let outcome = ExhaustiveSolver.solve(challenge: challenge)
            return Solved(
                outcome: outcome,
                targets: DayTargets.compute(challenge: challenge, outcome: outcome)
            )
        }
        inflight[key] = task
        let value = await task.value
        inflight[key] = nil
        store(value, for: key)
        return value
    }

    private func store(_ value: Solved, for key: String) {
        cache[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            cache[order.removeFirst()] = nil
        }
    }
}
