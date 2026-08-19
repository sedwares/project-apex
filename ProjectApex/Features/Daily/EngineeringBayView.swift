//
//  EngineeringBayView.swift
//  ProjectApex
//
//  The core screen: 8 categories × 3 options, live budget, submit.
//  Over-budget selection is allowed by design — the total goes red
//  and Submit gates. The player feels the trade-off.
//
//  PASS 6:
//  • The preview shows the four stats that decide THIS circuit, each
//    with its share of the lap. The old fixed five axes hid braking,
//    acceleration, power, cooling and weight — between them most of
//    what the simulation actually rewards.
//  • Options removed by the day's technical regulation render struck
//    through and unselectable, with the reason stated once at the top
//    rather than as a mystery disabled row.
//
//  LIVERY RESTYLE:
//  The regulation moved out of the scrolling list and into the pinned
//  top inset, beside the circuit context. It constrains every choice on
//  this screen, so scrolling it off the top was wrong — you could be
//  four categories deep and no longer be able to see why one row was
//  struck through.
//

import SwiftUI
import ProjectApexCore

struct EngineeringBayView: View {
    @Bindable var viewModel: DailyViewModel
    @State private var showDebrief = false
    @State private var showReplay = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if let identity = viewModel.identityPreview {
                        Text(identity.displayText)
                            .apexDisplay(18)
                    } else {
                        Text("Complete all 8 systems to see your identity")
                            .font(Theme.Font.body(13, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                    }

                    Text("What decides today").apexLabel()

                    ForEach(Array(viewModel.livePreview.axes.enumerated()), id: \.element.name) { rank, axis in
                        DemandAxisRow(axis: axis, rank: rank)
                    }

                    Text(DemandAxisRow.explainer)
                        .font(Theme.Font.body(10.5, weight: .regular))
                        .foregroundStyle(Theme.Color.faint)
                        .padding(.top, 2)
                }
                // Baseline bars read as "all equal" rather than "nothing
                // chosen yet"; dim until the first selection gives them
                // something to say.
                .opacity(viewModel.selections.isEmpty ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.2), value: viewModel.selections.isEmpty)
                .padding(.vertical, 6)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparator(.hidden)

            ForEach(OptionLibrary.categories) { category in
                Section {
                    ForEach(category.options) { option in
                        optionRow(option, in: category)
                    }
                    .listRowBackground(Theme.Color.panel)
                    .listRowSeparatorTint(Theme.Color.rule)
                } header: {
                    Text(category.displayName).apexLabel(Theme.Color.muted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle("Engineering Bay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CircuitContextHeader(
                    circuit: viewModel.challenge.circuit,
                    weather: viewModel.challenge.weather,
                    budget: viewModel.budget
                )
                if let regulation = viewModel.regulationText {
                    Text(regulation).apexNotice(Theme.Color.cream)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { budgetBar }
        .navigationDestination(isPresented: $showDebrief) {
            RaceDebriefView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showReplay) {
            if let result = viewModel.result {
                SimulationReplayView(
                    result: result,
                    challenge: viewModel.challenge
                ) {
                    showReplay = false
                    showDebrief = true
                }
            }
        }
        .onAppear {
            // Restored (already-submitted) day: straight to the debrief,
            // no re-ceremony. Guarded on !showReplay so a live replay
            // never has a navigation armed underneath it.
            if viewModel.phase == .submitted && viewModel.result != nil && !showReplay {
                showDebrief = true
            }
        }
    }

    // MARK: - Demand axis
    //
    // Lives in DemandAxisRow.swift — the Debrief draws the same chart,
    // and two copies had already drifted apart once.

    // MARK: - Option row

    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        let isSelected = viewModel.selectedOption(in: category.id) == option.id
        let categoryHasSelection = viewModel.selectedOption(in: category.id) != nil
        let delta = viewModel.costDelta(for: option)
        let isBanned = viewModel.isBanned(option.id)

        return Button {
            viewModel.select(option.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isBanned
                      ? "nosign"
                      : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 17))
                    .foregroundStyle(isBanned ? Theme.Color.faint
                                     : (isSelected ? Theme.Color.signal : Theme.Color.faint))

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.displayName)
                        .font(Theme.Font.body(15))
                        .foregroundStyle(isBanned ? Theme.Color.faint : Theme.Color.cream)
                        .strikethrough(isBanned)
                    if isBanned {
                        Text("Not permitted at this event")
                            .font(Theme.Font.body(10.5, weight: .regular))
                            .foregroundStyle(Theme.Color.faint)
                    } else if option.topUpside != nil || option.topDownside != nil {
                        HStack(spacing: 9) {
                            // No sign prefix here: topUpside/topDownside
                            // already carry their own (+/−). Prefixing
                            // produced "+ +Top Speed".
                            if let up = option.topUpside {
                                Text(up).foregroundStyle(Theme.Color.gain)
                            }
                            if let down = option.topDownside {
                                Text(down).foregroundStyle(Theme.Color.muted)
                            }
                        }
                        .font(Theme.Font.body(11, weight: .medium))
                    }
                }

                Spacer(minLength: 8)

                // A delta is only meaningful against an existing pick.
                // Without one, costDelta == cost and the row rendered
                // the same number twice ("+16  16 cr").
                if !isBanned && categoryHasSelection && !isSelected && delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .apexData(11, color: delta > 0 ? Theme.Color.notice : Theme.Color.gain)
                }
                Text("\(option.cost) cr")
                    .apexData(13, color: Theme.Color.muted)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.phase == .submitted || isBanned)
    }

    // MARK: - Budget bar

    private var budgetBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Engineering budget").apexLabel()
                Spacer()
                Text("\(viewModel.selections.count) / 8 systems")
                    .apexData(11, weight: .medium, color: Theme.Color.muted)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(viewModel.totalCost) / \(viewModel.budget) cr")
                    .apexData(21, weight: .bold,
                              color: viewModel.isOverBudget ? Theme.Color.signal : Theme.Color.cream)
                    .contentTransition(.numericText())
                Spacer()
                if viewModel.isOverBudget {
                    Text("Over by \(-viewModel.remainingCredits)")
                        .apexData(13, weight: .bold, color: Theme.Color.signal)
                } else {
                    Text("\(viewModel.remainingCredits) left")
                        .apexData(13, color: Theme.Color.muted)
                }
            }

            // A plain rectangle rather than ProgressView: the capsule
            // shape and the system's animation curve both belong to a
            // different design language, and at 4pt tall the rounded
            // ends eat most of the first few credits.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.cream.opacity(0.12))
                    Rectangle()
                        .fill(viewModel.isOverBudget ? Theme.Color.signal : Theme.Color.cream)
                        .frame(width: proxy.size.width * fillFraction)
                        .animation(.snappy(duration: 0.2), value: viewModel.totalCost)
                }
            }
            .frame(height: 4)

            Button {
                viewModel.submit()
                showReplay = viewModel.result != nil
            } label: {
                Text(submitLabel)
                    .font(Theme.Font.display(15))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(viewModel.canSubmit ? Theme.Color.ink : Theme.Color.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(viewModel.canSubmit
                                ? Theme.Color.cream : Theme.Color.cream.opacity(0.10))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.Color.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }

    /// Clamped so an over-budget setup shows a full bar rather than one
    /// that overflows its track.
    private var fillFraction: Double {
        guard viewModel.budget > 0 else { return 0 }
        return min(1, Double(viewModel.totalCost) / Double(viewModel.budget))
    }

    private var submitLabel: String {
        if viewModel.phase == .submitted { return "Submitted" }
        if !viewModel.isComplete {
            let remaining = EngineeringCategoryID.allCases.count - viewModel.selections.count
            return "Choose \(remaining) more"
        }
        if viewModel.usesBannedOption { return "Illegal setup" }
        if viewModel.isOverBudget { return "Over budget" }
        return "Submit — lock setup"
    }
}
