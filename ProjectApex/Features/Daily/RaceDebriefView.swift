//
//  RaceDebriefView.swift
//  ProjectApex
//
//  The Engineering Debrief (UX review batch): ASSIGNMENT COMPLETE
//  header, global standing with small-field honesty, theoretical-best
//  efficiency, sector bars with quality tiers, the Chief Engineer's
//  Report in prose, and the Experiment card with its reassurance.
//
//  PHASE 5 NOTE: optimal reveal stays gated until the day closes.
//
//  PASS 6:
//  • Next Test comes from SetupAdvisor (viewModel.advice) instead of
//    the deprecated event→swap table. It names the change, what it
//    costs, what to give up, and what it's worth — and pre-loads
//    exactly that setup into Experiment.
//  • The Vehicle Profile is circuit-relative, matching the Bay.
//  • "all 6,561 setups" is no longer hardcoded: a technical regulation
//    shrinks the legal space to 4,374 before the budget filter, so the
//    old copy was simply wrong on regulated days.
//

import SwiftUI
import ProjectApexCore

struct RaceDebriefView: View {
    @Bindable var viewModel: DailyViewModel
    @State private var revealOptimal = false

    var body: some View {
        List {
            if let result = viewModel.result {
                headerSection(result)
                standingSection
                lapsSection(result)
                profileSection
                efficiencySection(result)
                sectorsSection(result)
                reportSection
                experimentSection
            }
        }
        .navigationTitle("Engineering Debrief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let text = viewModel.shareText {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    // ShareLink has no action hook, and a simultaneous
                    // gesture is the only way to observe the tap without
                    // rebuilding the sheet by hand. Counts intent, not
                    // completion — nobody can see whether a share landed.
                    .simultaneousGesture(TapGesture().onEnded {
                        Analytics.shareTapped(
                            dayNumber: ChallengeSeed.dayNumber(
                                fromDateKey: viewModel.challenge.dateKey
                            )
                        )
                    })
                }
            }
        }
        .task { await viewModel.loadAnalysis() }
        .task { await viewModel.refreshStanding() }
        // Separate task: the advisor is ~128 simulations, far cheaper
        // than the exhaustive solve, so the Next Test button appears
        // long before the efficiency numbers do.
        .task { await viewModel.loadAdvice() }
    }

    // MARK: - Header

    private func headerSection(_ result: SimulationResult) -> some View {
        Section {
            VStack(spacing: 4) {
                Text("ASSIGNMENT COMPLETE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.5)
                Text(FixedPoint.formatLapTime(millis: result.averageLapTimeMillis))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                Text("Average · Fastest \(FixedPoint.formatLapTime(millis: result.fastestLapTimeMillis))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(result.setupIdentity.displayText)
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Global standing

    @ViewBuilder
    private var standingSection: some View {
        switch viewModel.standingState {
        case .idle:
            EmptyView()
        case .loading:
            Section("Global Standing") {
                HStack { ProgressView(); Text("Checking the paddock…").foregroundStyle(.secondary) }
                    .font(.subheadline)
            }
        case .failed(let reason):
            Section("Global Standing") {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        Task { await viewModel.refreshStanding() }
                    } label: {
                        Label("Couldn't reach the leaderboard — tap to retry", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                    }
                    // Never shipped to players — but during development
                    // the difference between a rules rejection and a
                    // missing index is the whole diagnosis, and the
                    // friendly sentence above erases it.
                    #if DEBUG
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    #endif
                }
            }
        case .loaded(let standing):
            Section("Global Standing") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if standing.totalEntries == 1 {
                            Text("Rank #1")
                                .font(.title3.weight(.bold))
                            Text("Only engineer today — set the benchmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if standing.totalEntries < 10 {
                            Text("Rank #\(standing.rank) of \(standing.totalEntries)")
                                .font(.title3.weight(.bold))
                            Text("Early field"
                                 + (standing.tieCount > 1 ? " · \(standing.tieCount) tied" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Top \(standing.topPercent)% of engineers")
                                .font(.title3.weight(.bold))
                            Text("Rank #\(standing.rank) of \(standing.totalEntries)"
                                 + (standing.tieCount > 1 ? " · \(standing.tieCount) tied" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let service = viewModel.leaderboardService {
                        NavigationLink {
                            LeaderboardView(
                                dateKey: viewModel.challenge.dateKey,
                                uid: viewModel.uid,
                                standing: standing,
                                service: service
                            )
                        } label: {
                            Text("Full board")
                                .font(.subheadline)
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Laps

    private func lapsSection(_ result: SimulationResult) -> some View {
        Section("Laps") {
            ForEach(result.lapResults, id: \.lapNumber) { lap in
                HStack {
                    Text("Lap \(lap.lapNumber)")
                    Text(lapRole(lap.lapNumber))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(FixedPoint.formatLapTime(millis: lap.timeMillis))
                        .monospacedDigit()
                        .fontWeight(lap.timeMillis == result.fastestLapTimeMillis ? .bold : .regular)
                }
            }
        }
    }

    // MARK: - Vehicle profile (circuit-relative)

    private var profileSection: some View {
        Section("What Decided Today") {
            let profile = VehicleProfile.from(
                setup: PlayerSetup(
                    challengeId: viewModel.challenge.id,
                    selectedOptions: viewModel.selections
                ),
                circuit: viewModel.challenge.circuit
            )
            ForEach(profile.axes, id: \.name) { axis in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(axis.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if axis.isInvertedStat {
                            Text("lower is better")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if let demand = axis.demandText {
                            Text(demand)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(Color.accentColor.opacity(0.75))
                                .frame(width: max(6, proxy.size.width * axis.fraction))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Engineering efficiency

    @ViewBuilder
    private func efficiencySection(_ result: SimulationResult) -> some View {
        Section("Engineering Efficiency") {
            if let analysis = viewModel.analysis {
                HStack {
                    Text(theoreticalBestLabel(legalCount: analysis.legalCount))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(FixedPoint.formatLapTime(millis: analysis.minPossibleAverageLapMillis))
                        .monospacedDigit()
                }
                HStack {
                    Text("Your gap")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(gapText(analysis.gapToOptimalMillis))
                        .monospacedDigit()
                        .foregroundStyle(analysis.gapToOptimalMillis == 0 ? .green : .primary)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Possible setups beaten")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(analysis.beatPercent)%")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }

                if viewModel.isRevealAllowed() {
                    DisclosureGroup("Reveal the optimal setup", isExpanded: $revealOptimal) {
                        ForEach(EngineeringCategoryID.allCases.sorted(), id: \.self) { category in
                            if let optionID = viewModel.analysis?.optimalSetup.selectedOptions[category] {
                                optimalRow(category: category, optionID: optionID)
                            }
                        }
                    }
                } else {
                    Label("Optimal setup reveals when the day closes",
                          systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Analyzing every legal setup…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The size of the space the optimum was found in. A technical
    /// regulation removes one option from one category, taking the
    /// structural space from 3^8 to 2×3^7 — so quoting 6,561 on a
    /// regulated day overstates what the player was actually up against.
    /// The field the player was actually ranked against — legal setups,
    /// not the structural space. Quoting 4,374 next to a percentage
    /// derived from 2,099 invited exactly the kind of arithmetic
    /// mismatch the sector chart just had to be fixed for.
    private func theoreticalBestLabel(legalCount: Int) -> String {
        "Theoretical best (all \(legalCount) legal setups)"
    }

    private func optimalRow(category: EngineeringCategoryID, optionID: EngineeringOptionID) -> some View {
        let option = OptionLibrary.option(optionID)
        let matched = viewModel.selectedOption(in: category) == optionID
        return HStack {
            Text(category.displayName)
                .foregroundStyle(.secondary)
            Spacer()
            Text(option.displayName)
                .fontWeight(matched ? .semibold : .regular)
            Image(systemName: matched ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(matched ? .green : Color.secondary.opacity(0.4))
                .imageScale(.small)
        }
        .font(.subheadline)
    }

    // MARK: - Sectors (bars + quality tiers)

    /// Where the lap went, measured against the OPTIMAL setup.
    ///
    /// This used to compare against the neutral car and was pure
    /// decoration: the neutral car has all twelve stats at 1000 and no
    /// options, so every sector read "Much faster" in green, every time,
    /// for every player. Against the optimum a gap is always ≥ 0 and
    /// each bar is that sector's share of the total time you gave up —
    /// which answers the only question worth asking here.
    @ViewBuilder
    private func sectorsSection(_ result: SimulationResult) -> some View {
        Section {
            if let deltas = viewModel.sectorsLostToOptimal {
                let scale = max(deltas.map { abs($0) }.max() ?? 1, 1)
                let worst = deltas.indices.max(by: { deltas[$0] < deltas[$1] })
                ForEach(Array(deltas.enumerated()), id: \.offset) { index, millis in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sector \(index + 1)")
                            if index == worst, millis > 0 {
                                Text("biggest loss")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(tierLabel(delta: millis))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tierColor(delta: millis))
                            // Only when it adds something the label didn't:
                            // "Optimal optimal" was saying it twice.
                            if millis != 0 {
                                Text(signedSeconds(millis))
                                    .monospacedDigit()
                                    .foregroundStyle(tierColor(delta: millis))
                            }
                        }
                        // Diverging from a centre line: quicker-than-optimal
                        // runs left in green, time lost runs right in red.
                        GeometryReader { proxy in
                            let half = proxy.size.width / 2
                            let frac = Double(abs(millis)) / Double(scale)
                            ZStack {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(width: 1)
                                if millis != 0 {
                                    Capsule()
                                        .fill(tierColor(delta: millis).opacity(0.8))
                                        .frame(width: max(3, half * frac))
                                        .offset(x: millis > 0
                                                ? half * frac / 2
                                                : -half * frac / 2)
                                }
                            }
                            .frame(width: proxy.size.width, alignment: .center)
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack {
                    ProgressView()
                    Text("Comparing your sectors to the optimal car…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Where the lap went")
        } footer: {
            if viewModel.sectorsLostToOptimal != nil {
                // Says out loud that the three numbers add up to the gap
                // above. They do, and inviting the check is the point.
                Text("Per lap, against the optimal setup. These add up to your gap.")
            }
        }
    }

    /// Absolute milliseconds against perfect, per lap — so the wording
    /// can be honest about what counts as close, and can say outright
    /// when you were quicker than the optimal car.
    private func tierLabel(delta: Int) -> String {
        switch delta {
        case ..<0: return "Ahead"
        case 0: return "Optimal"
        case ..<80: return "On pace"
        case ..<350: return "Close"
        case ..<850: return "Off pace"
        default: return "Weak"
        }
    }

    private func tierColor(delta: Int) -> Color {
        switch delta {
        case ..<80: return .green
        case ..<350: return .primary
        case ..<850: return .orange
        default: return .red
        }
    }

    private func signedSeconds(_ millis: Int) -> String {
        (millis > 0 ? "+" : "−") + secondsText(millis)
    }

    // MARK: - Chief Engineer's Report

    @ViewBuilder
    private var reportSection: some View {
        if let feedback = viewModel.feedback {
            Section("Chief Engineer's Report") {
                VStack(alignment: .leading, spacing: 10) {
                    // When the Next Test card is showing, the prose drops
                    // its recommendation sentence — otherwise the same
                    // change, funding source and time saving get stated
                    // twice, one line apart.
                    Text(viewModel.advice == nil ? feedback.reportText : feedback.observationText)
                        .font(.subheadline)
                    Text("— Chief Engineer")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if let advice = viewModel.advice {
                        Divider()
                        nextTestLink(advice)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// One tap to the exact setup the engineer recommends — the change,
    /// the funding source, and what it's worth. Pre-loading the whole
    /// resulting setup (rather than a single swap) is the point: the
    /// advisor already solved the budget, so the player lands in
    /// Experiment ready to press Run.
    private func nextTestLink(_ advice: EngineerAdvice) -> some View {
        NavigationLink {
            ExperimentView(viewModel: viewModel)
                .onAppear { viewModel.preloadExperiment(advice) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(nextTestTitle(advice))
                        .font(.subheadline.weight(.medium))
                    if let funding = advice.funding {
                        Text("Pay for it: \(funding.category.displayName) → "
                             + OptionLibrary.option(funding.to).displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Worth about \(secondsText(advice.gainMillis)) here")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func nextTestTitle(_ advice: EngineerAdvice) -> String {
        let to = OptionLibrary.option(advice.upgrade.to).displayName
        return "Next test: \(advice.upgrade.category.displayName) → \(to)"
    }

    // MARK: - Experiment

    private var experimentSection: some View {
        Section {
            NavigationLink {
                ExperimentView(viewModel: viewModel)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "flask")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Experiment")
                            .font(.headline)
                        Text("Replay today's assignment with another setup. Your submitted result will never change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Helpers

    private func lapRole(_ n: Int) -> String {
        switch n {
        case 1: return "warmup"
        case 2: return "peak"
        default: return "wear & heat"
        }
    }

    private func secondsText(_ millis: Int) -> String {
        let a = abs(millis)
        return "\(a / 1000).\(String(format: "%03d", a % 1000))s"
    }

    private func gapText(_ gap: Int) -> String {
        if gap == 0 { return "level" }
        let sign = gap < 0 ? "−" : "+"
        let a = abs(gap)
        return "\(sign)\(a / 1000).\(String(format: "%03d", a % 1000))s"
    }
}
