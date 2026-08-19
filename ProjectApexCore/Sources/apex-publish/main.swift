//
//  main.swift
//  apex-publish
//
//  Publishes daily challenges to Firestore (Phase 5, Decision 1).
//  Uses the SAME ChallengeGenerator + ExhaustiveSolver the game ships —
//  one simulation codebase, bit-identical challenges everywhere.
//
//  USAGE
//    swift run -c release apex-publish \
//        --project YOUR_FIREBASE_PROJECT_ID \
//        --start 2026-07-16 \
//        --days 60 \
//        --token "$(gcloud auth print-access-token)"
//
//    Add --dry-run to print the documents without writing anything.
//    Add --overwrite to REPLACE days that already exist.
//
//    Re-rolling a day whose draw failed the validation gate (future
//    dates only — past dates are refused, see the guard in main):
//        --reroll 2026-09-03=1 --reroll 2026-09-17=1 --overwrite
//    or, preferably, keep them in a file that lives in the repo:
//        --reroll-file rerolls.txt --overwrite
//    A re-rolled day is NOT reproducible from its date alone, so the
//    file is the only record of which draw is live. Losing it means
//    losing the ability to re-derive a published challenge. Commit it.
//
//  Requires the Google Cloud SDK (`gcloud auth login` with the Firebase
//  project owner account). Re-running is safe by default: existing days
//  are skipped (create-only semantics, HTTP 409 → skip).
//
//  ⚠️ THE SKIP IS A TRAP DURING A VERSION BUMP. After pass 6 every
//  document needs a new simulationVersion and a bannedOption field, but
//  a plain rerun prints "already published" for every existing day and
//  writes nothing — which looks exactly like success while the client
//  keeps getting "Missing or insufficient permissions", because the
//  rules compare the submission against a document that never changed.
//  Use --overwrite for the migration; leave it off for normal topping-up
//  of future days, where rewriting a played competition would be wrong.
//

import Foundation
import ProjectApexCore

// MARK: - Argument parsing (hand-rolled; no dependencies)

struct Arguments {
    var project: String?
    var start: String?
    var days: Int = 60
    var token: String? = ProcessInfo.processInfo.environment["FIREBASE_TOKEN"]
    var dryRun = false
    /// Republish days that already exist, instead of skipping them.
    ///
    /// The default (create-only POST) is the right safety behaviour: a
    /// published day is a competition that people played, and silently
    /// rewriting it would invalidate every result. But it also means a
    /// balance change or a new field — like pass 6's `bannedOption` —
    /// can NEVER reach days that are already in the database. The rerun
    /// prints "already published" for every one of them and changes
    /// nothing, which reads exactly like success.
    var overwrite = false
    /// dateKey → nonce, for days whose canonical draw failed the gate.
    /// Absent = nonce 0 = the canonical draw.
    var rerolls: [String: Int] = [:]
    /// Permit re-rolling a date at or before today. Off by default —
    /// see the guard in main for why.
    var allowPastReroll = false
}

func parseArguments() -> Arguments {
    var args = Arguments()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let flag = iterator.next() {
        switch flag {
        case "--project": args.project = iterator.next()
        case "--start": args.start = iterator.next()
        case "--days": args.days = iterator.next().flatMap(Int.init) ?? args.days
        case "--token": args.token = iterator.next()
        case "--dry-run": args.dryRun = true
        case "--overwrite": args.overwrite = true
        case "--reroll":
            guard let pair = iterator.next() else { fail("--reroll needs yyyy-MM-dd=nonce") }
            let (key, nonce) = parseReroll(pair)
            args.rerolls[key] = nonce
        case "--allow-past-reroll": args.allowPastReroll = true
        case "--reroll-file":
            guard let path = iterator.next() else { fail("--reroll-file needs a path") }
            for (key, nonce) in parseRerollFile(path) { args.rerolls[key] = nonce }
        default:
            fail("Unknown argument: \(flag)")
        }
    }
    return args
}

/// "2026-09-03=1" → ("2026-09-03", 1). Validated hard: a typo here
/// silently publishes the wrong draw, and you would not find out until
/// somebody's leaderboard submission is rejected.
func parseReroll(_ pair: String) -> (String, Int) {
    let parts = pair.split(separator: "=")
    guard parts.count == 2,
          let nonce = Int(parts[1]),
          nonce != 0,
          ChallengeSeed.dayNumber(fromDateKey: String(parts[0])) != nil
    else { fail("Bad --reroll \(pair) — expected yyyy-MM-dd=nonce with a non-zero nonce") }
    return (String(parts[0]), nonce)
}

/// One `dateKey=nonce` per line. `#` starts a comment; blank lines are
/// ignored. Keep this file in the repository — see the header.
func parseRerollFile(_ path: String) -> [(String, Int)] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("Could not read --reroll-file \(path)")
    }
    return text.split(separator: "\n").compactMap { rawLine -> (String, Int)? in
        // prefix(while:), not split(separator: "#") — splitting drops
        // empty subsequences, so a line that STARTS with # yields the
        // comment text as element 0 and every comment gets parsed.
        let line = rawLine.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return parseReroll(line)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("❌ \(message)\n".utf8))
    exit(1)
}

// MARK: - Civil calendar (inverse of ChallengeSeed.daysSinceUnixEpoch)

// civil_from_days now lives in ChallengeSeed — two copies of calendar
// arithmetic is one copy too many, and the validation batch needs the
// same inverse to label its days by date.

func dateKey(daysAfter startKey: String, offset: Int) -> String {
    guard let start = ChallengeSeed.parse(dateKey: startKey) else {
        fail("Invalid --start dateKey: \(startKey) (expected yyyy-MM-dd)")
    }
    let base = ChallengeSeed.daysSinceUnixEpoch(year: start.year, month: start.month, day: start.day)
    let c = ChallengeSeed.civilFromDays(base + offset)
    return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
}

func todayUTCDateKey() -> String {
    UTCDateKey.make()
}

// MARK: - Firestore REST document encoding

func firestoreDocument(for challenge: DailyChallenge) -> [String: Any] {
    func s(_ v: String) -> [String: Any] { ["stringValue": v] }
    func i(_ v: Int) -> [String: Any] { ["integerValue": String(v)] }
    func ts(_ v: String) -> [String: Any] { ["timestampValue": v] }

    let opensAt = "\(challenge.dateKey)T00:00:00Z"
    let closesAt = "\(dateKey(daysAfter: challenge.dateKey, offset: 1))T00:00:00Z"

    let sections: [[String: Any]] = challenge.circuit.sections.map { s($0.rawValue) }
    let circuit: [String: Any] = ["mapValue": ["fields": [
        "id": s(challenge.circuit.id),
        "name": s(challenge.circuit.name),
        "archetype": s(challenge.circuit.archetype.rawValue),
        "sections": ["arrayValue": ["values": sections]]
    ]]]

    return ["fields": [
        "dateKey": s(challenge.dateKey),
        "seed": s(String(challenge.seed)),      // u64 as string (Firestore has no u64)
        "circuit": circuit,
        "weather": s(challenge.weather.rawValue),
        "budget": i(challenge.budget),
        "simulationVersion": s(challenge.simulationVersion),
        "minPossibleAverageLapMillis": i(challenge.minPossibleAverageLapMillis),
        // The day's technical regulation. ALWAYS written, empty string
        // when the day is unrestricted — never omitted.
        //
        // Two reasons it must always be present. The client treats a
        // missing key as a malformed document rather than as "no
        // regulation", because silently dropping a ban the server
        // intended would let a player submit a setup the database then
        // rejects. And the security rules dereference
        // `challenge(dateKey).data.bannedOption` on every leaderboard
        // write: in Firestore rules, reading an absent field raises an
        // error that evaluates the whole condition to false, so an
        // omitted field wouldn't merely disable the regulation — it
        // would deny every submission for that day.
        "bannedOption": s(challenge.bannedOption?.rawValue ?? ""),
        "opensAt": ts(opensAt),
        "closesAt": ts(closesAt)
    ]]
}

// MARK: - Firestore REST write (create-only, idempotent reruns)

enum PublishResult { case created, alreadyExists, failed(String) }

func publish(
    document: [String: Any],
    dateKey: String,
    project: String,
    token: String,
    overwrite: Bool = false
) async -> PublishResult {
    let base = "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents/challenges"
    var components: URLComponents
    if overwrite {
        // PATCH creates-or-updates. The updateMask names every field we
        // write, so the patch fully replaces them rather than merging
        // into whatever the old document happened to hold.
        components = URLComponents(string: "\(base)/\(dateKey)")!
        let fields = (document["fields"] as? [String: Any])?.keys.sorted() ?? []
        components.queryItems = fields.map {
            URLQueryItem(name: "updateMask.fieldPaths", value: $0)
        }
    } else {
        components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: "documentId", value: dateKey)]
    }

    var request = URLRequest(url: components.url!)
    request.httpMethod = overwrite ? "PATCH" : "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try! JSONSerialization.data(withJSONObject: document)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200: return .created
        case 409: return .alreadyExists
        default:
            let body = String(decoding: data, as: UTF8.self)
            return .failed("HTTP \(status): \(body.prefix(300))")
        }
    } catch {
        return .failed(error.localizedDescription)
    }
}

// MARK: - Main

let args = parseArguments()
guard let start = args.start else { fail("Missing --start yyyy-MM-dd") }
guard args.days > 0 else { fail("--days must be positive") }
if !args.rerolls.isEmpty && !args.overwrite && !args.dryRun {
    fail("--reroll without --overwrite does nothing: the day already exists, so the create-only POST returns 409 and is skipped.")
}

// A re-roll of a date that has already passed is at best a no-op and at
// worst destructive: that day is a finished competition, and publishing
// a different circuit for it invalidates every result and every
// leaderboard row recorded against it.
//
// This is not hypothetical. The balance gate samples days 1...180 —
// 2026-01-01 to 2026-06-29, all historical — so its worklist is made
// entirely of dates that must never be re-rolled. Pasting it is the
// obvious mistake, and it is silent.
if !args.rerolls.isEmpty,
   let todayNumber = ChallengeSeed.dayNumber(fromDateKey: todayUTCDateKey()) {
    let past = args.rerolls.keys
        .filter { (ChallengeSeed.dayNumber(fromDateKey: $0) ?? 0) <= todayNumber }
        .sorted()
    if !past.isEmpty && !args.allowPastReroll {
        fail("""
            Refusing to re-roll \(past.count) date(s) at or before today (\(todayUTCDateKey())):
            \(past.joined(separator: " "))
            Those are finished competitions — a new draw invalidates every result recorded
            against them. Take the worklist from the PUBLISHING WINDOW section of the gate
            report, not the balance sample. Override with --allow-past-reroll only if you
            are certain nobody has played them.
            """)
    }
}
if !args.dryRun {
    guard args.project != nil else { fail("Missing --project (or use --dry-run)") }
    guard args.token != nil else { fail("Missing --token (use --token \"$(gcloud auth print-access-token)\" or FIREBASE_TOKEN env)") }
}

print("apex-publish · simulationVersion \(ResultHasher.simulationVersion)")
print("Range: \(start) + \(args.days) days · \(args.dryRun ? "DRY RUN" : "publishing to \(args.project!)")")
if !args.rerolls.isEmpty {
    let listed = args.rerolls.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    print("Re-rolls: \(listed.joined(separator: " "))")
}
print("")

var created = 0, skipped = 0, failed = 0
var lastKey = start
let clock = ContinuousClock()

for offset in 0..<args.days {
    let key = dateKey(daysAfter: start, offset: offset)
    lastKey = key
    guard let dayNumber = ChallengeSeed.dayNumber(fromDateKey: key) else {
        fail("Could not compute day number for \(key)")
    }

    let solveStart = clock.now
    let nonce = args.rerolls[key] ?? 0
    let challenge = ChallengeGenerator.generate(dayNumber: dayNumber, dateKey: key, nonce: nonce)

    // A regulation that bans the cheapest option in a category raises
    // the cost floor. If it raises it above the day's budget there is no
    // legal setup at all and ExhaustiveSolver traps on an empty field —
    // better to refuse to publish than to ship an unplayable day.
    // ChallengeGenerator re-draws to avoid this, so reaching here means
    // the library's costs have moved out from under the budget range.
    guard challenge.isSatisfiable else {
        fail("""
            Day \(dayNumber) \(key) is unsatisfiable: budget \(challenge.budget) is below the \
            regulated minimum \(OptionLibrary.minimumTotalCost(banned: challenge.bannedOption)) \
            (regulation: \(challenge.bannedOption?.rawValue ?? "none")). \
            Re-roll it (--reroll \(key)=\((nonce == 0 ? 1 : nonce + 1))) or widen ChallengeGenerator.budgetRange.
            """)
    }

    let outcome = ExhaustiveSolver.solve(challenge: challenge)
    let finalized = challenge.finalized(
        minPossibleAverageLapMillis: outcome.minPossibleAverageLapMillis
    )
    let solveMillis = (clock.now - solveStart).components.attoseconds / 1_000_000_000_000_000
        + (clock.now - solveStart).components.seconds * 1_000

    let document = firestoreDocument(for: finalized)
    let rollTag = nonce == 0 ? "" : "  ↻n\(nonce)"
    let summary = "Day \(dayNumber) \(key)\(rollTag)  \(finalized.circuit.archetype.rawValue)/\(finalized.weather.rawValue)"
        + "  budget \(finalized.budget)  min \(FixedPoint.formatLapTime(millis: finalized.minPossibleAverageLapMillis))"
        + "  legal \(outcome.legalCount)  (\(solveMillis)ms)"

    if args.dryRun {
        print("DRY  \(summary)")
        if offset == 0 {
            let json = try! JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: json, as: UTF8.self))
        }
        created += 1
        continue
    }

    switch await publish(
        document: document, dateKey: key,
        project: args.project!, token: args.token!, overwrite: args.overwrite
    ) {
    case .created:
        print("PUB  \(summary)")
        created += 1
    case .alreadyExists:
        print("SKIP \(summary)  (already published — rerun with --overwrite to replace)")
        skipped += 1
    case .failed(let reason):
        print("FAIL \(summary)\n     \(reason)")
        failed += 1
        if failed >= 3 { fail("Three failures — aborting. Check token/project and rerun (reruns are safe).") }
    }
}

// Buffer report.
let today = todayUTCDateKey()
let bufferDays = (ChallengeSeed.dayNumber(fromDateKey: lastKey) ?? 0)
    - (ChallengeSeed.dayNumber(fromDateKey: today) ?? 0)
print("\nDone: \(created) published, \(skipped) skipped, \(failed) failed.")
print("Last day: \(lastKey) — buffer: \(bufferDays) days from today (\(today)).")
if bufferDays < 14 {
    print("⚠️  Buffer under two weeks — schedule the next publish run.")
}
