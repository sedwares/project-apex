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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle("Engineering Debrief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
            VStack(spacing: 5) {
                Text("Assignment complete").apexLabel(Theme.Color.signal)
                Text(FixedPoint.formatLapTime(millis: result.averageLapTimeMillis))
                    .apexData(40, weight: .bold)
                Text("Average · Fastest \(FixedPoint.formatLapTime(millis: result.fastestLapTimeMillis))")
                    .apexData(12, weight: .medium, color: Theme.Color.muted)
                Text(result.setupIdentity.displayText)
                    .apexDisplay(17)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .listRowBackground(Theme.Color.panel)
        .listRowSeparator(.hidden)
    }

    // MARK: - Global standing

    @ViewBuilder
    private var standingSection: some View {
        switch viewModel.standingState {
        case .idle:
            EmptyView()
        case .loading:
            Section {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Color.signal)
                    Text("Checking the paddock").apexLabel(Theme.Color.muted)
                }
            } header: { Text("Global standing").apexLabel(Theme.Color.muted) }
                .listRowBackground(Theme.Color.panel)
        case .failed(let reason):
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        Task { await viewModel.refreshStanding() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.clockwise")
                            Text("Couldn't reach the leaderboard — tap to retry")
                        }
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.signal)
                    }
                    // Never shipped to players — but during development
                    // the difference between a rules rejection and a
                    // missing index is the whole diagnosis, and the
                    // friendly sentence above erases it.
                    #if DEBUG
                    Text(reason)
                        .font(Theme.Font.body(10.5, weight: .regular))
                        .foregroundStyle(Theme.Color.faint)
                        .textSelection(.enabled)
                    #endif
                }
            } header: { Text("Global standing").apexLabel(Theme.Color.muted) }
                .listRowBackground(Theme.Color.panel)
        case .loaded(let standing):
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if standing.totalEntries == 1 {
                            Text("Rank #1").apexDisplay(22)
                            Text("Only engineer today — set the benchmark")
                                .font(Theme.Font.body(11.5, weight: .regular))
                                .foregroundStyle(Theme.Color.muted)
                        } else if standing.totalEntries < 10 {
                            Text("Rank #\(standing.rank) of \(standing.totalEntries)")
                                .apexDisplay(22)
                            Text("Early field"
                                 + (standing.tieCount > 1 ? " · \(standing.tieCount) tied" : ""))
                                .font(Theme.Font.body(11.5, weight: .regular))
                                .foregroundStyle(Theme.Color.muted)
                        } else {
                            Text("Top \(standing.topPercent)% of engineers")
                                .apexDisplay(22)
                            Text("Rank #\(standing.rank) of \(standing.totalEntries)"
                                 + (standing.tieCount > 1 ? " · \(standing.tieCount) tied" : ""))
                                .font(Theme.Font.body(11.5, weight: .regular))
                                .foregroundStyle(Theme.Color.muted)
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
                            Text("Full board").apexLabel(Theme.Color.signal)
                        }
                        .fixedSize()
                    }
                }
            } header: { Text("Global standing").apexLabel(Theme.Color.muted) }
                .listRowBackground(Theme.Color.panel)
        }
    }

    // MARK: - Laps

    private func lapsSection(_ result: SimulationResult) -> some View {
        Section {
            ForEach(result.lapResults, id: \.lapNumber) { lap in
                let fastest = lap.timeMillis == result.fastestLapTimeMillis
                HStack(spacing: 8) {
                    Text("Lap \(lap.lapNumber)")
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.cream)
                    Text(lapRole(lap.lapNumber))
                        .font(Theme.Font.body(11, weight: .regular))
                        .foregroundStyle(Theme.Color.faint)
                    Spacer()
                    Text(FixedPoint.formatLapTime(millis: lap.timeMillis))
                        .apexData(14, weight: fastest ? .bold : .regular,
                                  color: fastest ? Theme.Color.cream : Theme.Color.muted)
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparatorTint(Theme.Color.rule)
        } header: { Text("Laps").apexLabel(Theme.Color.muted) }
    }

    // MARK: - Vehicle profile (circuit-relative)

    private var profileSection: some View {
        Section {
            let profile = VehicleProfile.from(
                setup: PlayerSetup(
                    challengeId: viewModel.challenge.id,
                    selectedOptions: viewModel.selections
                ),
                circuit: viewModel.challenge.circuit
            )
            VStack(alignment: .leading, spacing: 12) {
                // Same component as the Engineering Bay, deliberately.
                // This screen tells you how the read you made over there
                // turned out; if the two charts look different you
                // cannot carry anything from one to the other.
                ForEach(Array(profile.axes.enumerated()), id: \.element.name) { rank, axis in
                    DemandAxisRow(axis: axis, rank: rank, barHeight: 6)
                }
                Text(DemandAxisRow.explainer)
                    .font(Theme.Font.body(10.5, weight: .regular))
                    .foregroundStyle(Theme.Color.faint)
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.Color.panel)
            .listRowSeparator(.hidden)
        } header: { Text("What decided today").apexLabel(Theme.Color.muted) }
    }

    // MARK: - Engineering efficiency

    @ViewBuilder
    private func efficiencySection(_ result: SimulationResult) -> some View {
        Section {
            if let analysis = viewModel.analysis {
                HStack {
                    Text(theoreticalBestLabel(legalCount: analysis.legalCount)).apexLabel()
                    Spacer(minLength: 10)
                    Text(FixedPoint.formatLapTime(millis: analysis.minPossibleAverageLapMillis))
                        .apexData(14, color: Theme.Color.muted)
                }
                HStack {
                    Text("Your gap").apexLabel()
                    Spacer()
                    Text(gapText(analysis.gapToOptimalMillis))
                        .apexData(16, weight: .bold,
                                  color: analysis.gapToOptimalMillis == 0
                                      ? Theme.Color.gain : Theme.Color.cream)
                }
                HStack {
                    Text("Possible setups beaten").apexLabel()
                    Spacer()
                    Text("\(analysis.beatPercent)%").apexData(16, weight: .bold)
                }

                if viewModel.isRevealAllowed() {
                    DisclosureGroup(isExpanded: $revealOptimal) {
                        ForEach(EngineeringCategoryID.allCases.sorted(), id: \.self) { category in
                            if let optionID = viewModel.analysis?.optimalSetup.selectedOptions[category] {
                                optimalRow(category: category, optionID: optionID)
                            }
                        }
                    } label: {
                        Text("Reveal the optimal setup").apexLabel(Theme.Color.signal)
                    }
                    .tint(Theme.Color.cream)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Optimal setup reveals when the day closes")
                    }
                    .apexLabel(Theme.Color.faint)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Color.signal)
                    Text("Analyzing every legal setup").apexLabel(Theme.Color.muted)
                }
            }
        } header: { Text("Engineering efficiency").apexLabel(Theme.Color.muted) }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparatorTint(Theme.Color.rule)
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
        return HStack(spacing: 10) {
            Text(category.displayName).apexLabel()
            Spacer(minLength: 10)
            Text(option.displayName)
                .font(Theme.Font.body(13, weight: matched ? .bold : .regular))
                .foregroundStyle(matched ? Theme.Color.cream : Theme.Color.muted)
            Image(systemName: matched ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(matched ? Theme.Color.gain : Theme.Color.faint)
        }
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
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text("Sector \(index + 1)")
                                .font(Theme.Font.body(14))
                                .foregroundStyle(Theme.Color.cream)
                            if index == worst, millis > 0 {
                                Text("biggest loss").apexLabel(Theme.Color.notice)
                            }
                            Spacer(minLength: 8)
                            Text(tierLabel(delta: millis))
                                .apexLabel(tierColor(delta: millis))
                            // Only when it adds something the label didn't:
                            // "Optimal optimal" was saying it twice.
                            if millis != 0 {
                                Text(signedSeconds(millis))
                                    .apexData(15, weight: .bold, color: tierColor(delta: millis))
                            }
                        }
                        // Diverging from a centre line: quicker-than-optimal
                        // runs left in green, time lost runs right in red.
                        GeometryReader { proxy in
                            let half = proxy.size.width / 2
                            let frac = Double(abs(millis)) / Double(scale)
                            ZStack {
                                Rectangle()
                                    .fill(Theme.Color.cream.opacity(0.22))
                                    .frame(width: 1)
                                if millis != 0 {
                                    Rectangle()
                                        .fill(tierColor(delta: millis))
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
                    .padding(.vertical, 3)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Color.signal)
                    Text("Comparing your sectors to the optimal car").apexLabel(Theme.Color.muted)
                }
            }
        } header: {
            Text("Where the lap went").apexLabel(Theme.Color.muted)
        } footer: {
            if viewModel.sectorsLostToOptimal != nil {
                // Says out loud that the three numbers add up to the gap
                // above. They do, and inviting the check is the point.
                Text("Per lap, against the optimal setup. These add up to your gap.")
                    .font(Theme.Font.body(10.5, weight: .regular))
                    .foregroundStyle(Theme.Color.faint)
            }
        }
        .listRowBackground(Theme.Color.panel)
        .listRowSeparatorTint(Theme.Color.rule)
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
        case ..<80: return Theme.Color.gain
        case ..<350: return Theme.Color.cream
        case ..<850: return Theme.Color.notice
        default: return Theme.Color.signal
        }
    }

    private func signedSeconds(_ millis: Int) -> String {
        (millis > 0 ? "+" : "−") + secondsText(millis)
    }

    // MARK: - Chief Engineer's Report

    @ViewBuilder
    private var reportSection: some View {
        if let feedback = viewModel.feedback {
            Section {
                VStack(alignment: .leading, spacing: 11) {
                    // When the Next Test card is showing, the prose drops
                    // its recommendation sentence — otherwise the same
                    // change, funding source and time saving get stated
                    // twice, one line apart.
                    Text(viewModel.advice == nil ? feedback.reportText : feedback.observationText)
                        .font(Theme.Font.body(14, weight: .regular))
                        .foregroundStyle(Theme.Color.cream)
                    Text("— Chief Engineer")
                        .font(Theme.Font.body(11, weight: .regular).italic())
                        .foregroundStyle(Theme.Color.faint)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if let advice = viewModel.advice {
                        Rectangle().fill(Theme.Color.rule).frame(height: 1)
                        nextTestLink(advice)
                    }
                }
                .padding(.vertical, 5)
            } header: { Text("Chief engineer's report").apexLabel(Theme.Color.muted) }
                .listRowBackground(Theme.Color.panel)
                .listRowSeparator(.hidden)
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
                    .foregroundStyle(Theme.Color.signal)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(nextTestTitle(advice))
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.cream)
                    if let funding = advice.funding {
                        Text("Pay for it: \(funding.category.displayName) → "
                             + OptionLibrary.option(funding.to).displayName)
                            .font(Theme.Font.body(11.5, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                    }
                    Text("Worth about \(secondsText(advice.gainMillis)) here")
                        .apexData(11.5, color: Theme.Color.gain)
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
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Color.signal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Experiment").apexDisplay(17)
                        Text("Replay today's assignment with another setup. Your submitted result will never change.")
                            .font(Theme.Font.body(11.5, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                    }
                }
                .padding(.vertical, 7)
            }
            .listRowBackground(Theme.Color.panel)
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
