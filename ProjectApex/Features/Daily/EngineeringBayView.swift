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

import SwiftUI
import ProjectApexCore

struct EngineeringBayView: View {
    @Bindable var viewModel: DailyViewModel
    @State private var showDebrief = false
    @State private var showReplay = false

    var body: some View {
        List {
            if let regulation = viewModel.regulationText {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Technical regulation")
                                .font(.caption.weight(.semibold))
                            Text(regulation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    if let identity = viewModel.identityPreview {
                        Text(identity.displayText)
                            .font(.headline)
                    } else {
                        Text("Complete all 8 systems to see your identity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("WHAT DECIDES TODAY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(1.2)

                    ForEach(viewModel.livePreview.axes, id: \.name) { axis in
                        demandAxisRow(axis)
                    }
                }
                // Baseline bars read as "all equal" rather than "nothing
                // chosen yet"; dim until the first selection gives them
                // something to say.
                .opacity(viewModel.selections.isEmpty ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.2), value: viewModel.selections.isEmpty)
                .padding(.vertical, 4)
            }

            ForEach(OptionLibrary.categories) { category in
                Section(category.displayName) {
                    ForEach(category.options) { option in
                        optionRow(option, in: category)
                    }
                }
            }
        }
        .navigationTitle("Engineering Bay")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            CircuitContextHeader(
                circuit: viewModel.challenge.circuit,
                weather: viewModel.challenge.weather,
                budget: viewModel.budget
            )
        }
        .safeAreaInset(edge: .bottom) { budgetBar }
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

    /// The bar plus what it's worth. The share is the point: "Braking —
    /// 18% of this lap" is the sentence that turns a decorative gauge
    /// into a reason to spend credits.
    private func demandAxisRow(_ axis: VehicleProfile.Axis) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(axis.name)
                    .font(.caption)
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
                        .frame(width: max(4, proxy.size.width * axis.fraction))
                        .animation(.snappy(duration: 0.25), value: axis.fraction)
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Option row

    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        let isSelected = viewModel.selectedOption(in: category.id) == option.id
        let categoryHasSelection = viewModel.selectedOption(in: category.id) != nil
        let delta = viewModel.costDelta(for: option)
        let isBanned = viewModel.isBanned(option.id)

        return Button {
            viewModel.select(option.id)
        } label: {
            HStack {
                Image(systemName: isBanned
                      ? "nosign"
                      : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .foregroundStyle(isBanned ? Color.secondary
                                     : (isSelected ? Color.accentColor : Color.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .foregroundStyle(isBanned ? .secondary : .primary)
                        .strikethrough(isBanned)
                    if isBanned {
                        Text("Not permitted at this event")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if option.topUpside != nil || option.topDownside != nil {
                        HStack(spacing: 8) {
                            // No sign prefix here: topUpside/topDownside
                            // already carry their own (+/−). Prefixing
                            // produced "+ +Top Speed".
                            if let up = option.topUpside {
                                Text(up).foregroundStyle(.green)
                            }
                            if let down = option.topDownside {
                                Text(down).foregroundStyle(.orange)
                            }
                        }
                        .font(.caption2)
                    }
                }
                Spacer()
                // A delta is only meaningful against an existing pick.
                // Without one, costDelta == cost and the row rendered
                // the same number twice ("+16  16 cr").
                if !isBanned && categoryHasSelection && !isSelected && delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(delta > 0 ? .orange : .green)
                }
                Text("\(option.cost) cr")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.phase == .submitted || isBanned)
    }

    // MARK: - Budget bar

    private var budgetBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ENGINEERING BUDGET")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                Spacer()
                Text("\(viewModel.selections.count) / 8 systems")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(viewModel.totalCost) / \(viewModel.budget) cr")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(viewModel.isOverBudget ? .red : .primary)
                    .contentTransition(.numericText())
                Spacer()
                if viewModel.isOverBudget {
                    Text("Over by \(-viewModel.remainingCredits)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("\(viewModel.remainingCredits) left")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(
                value: Double(min(viewModel.totalCost, viewModel.budget)),
                total: Double(viewModel.budget)
            )
            .tint(viewModel.isOverBudget ? .red : Color.accentColor)
            .animation(.default, value: viewModel.totalCost)

            Button {
                viewModel.submit()
                showReplay = viewModel.result != nil
            } label: {
                Text(submitLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)
        }
        .padding(16)
        .background(.bar)
    }

    private var submitLabel: String {
        if viewModel.phase == .submitted { return "Submitted" }
        if !viewModel.isComplete {
            let remaining = EngineeringCategoryID.allCases.count - viewModel.selections.count
            return "Choose \(remaining) more"
        }
        if viewModel.usesBannedOption { return "Illegal Setup" }
        if viewModel.isOverBudget { return "Over Budget" }
        return "Submit — Lock Setup"
    }
}
