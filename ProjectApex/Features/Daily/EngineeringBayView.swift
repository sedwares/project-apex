//
//  EngineeringBayView.swift
//  ProjectApex
//
//  The core screen: 8 categories × 3 options, live budget, submit.
//  Over-budget selection is allowed by design — the total goes red
//  and Submit gates. The player feels the trade-off.
//
//  F1 RESTYLE (pass 7):
//  Option rows are styled as timing-tower entries: a 3px red left stripe
//  marks the selected row, with an animation on selection. Unselected rows
//  have a hairline rule stripe. The submit button is now signal red.
//  List row insets are removed on the leading edge so the stripe sits
//  flush with the row's left boundary.
//

import SwiftUI
import ProjectApexCore

struct EngineeringBayView: View {
    @Bindable var viewModel: DailyViewModel
    @State private var showDebrief = false
    @State private var showReplay = false

    var body: some View {
        List {
            // The car being built. It starts as an outline and fills in
            // part by part, so the bay reads as construction rather than
            // as a form — and so all eight choices are visible at once,
            // which twenty-four scrolling rows can never be.
            Section {
                VStack(spacing: 12) {
                    SetupCarView(selections: viewModel.selections)
                        .frame(height: 176)
                        .frame(maxWidth: .infinity)

                    SetupSpecGrid(selections: viewModel.selections)

                    if let identity = viewModel.identityPreview {
                        Text(identity.displayText)
                            .apexDisplay(17)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Eight systems, one budget. The car takes shape as you choose.")
                            .font(Theme.Font.body(11.5, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparator(.hidden)

            // The circuit's demands are about the TRACK, not the car, so
            // they are their own section rather than more of that one.
            if !viewModel.selections.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(viewModel.livePreview.axes.enumerated()), id: \.element.name) { rank, axis in
                            DemandAxisRow(axis: axis, rank: rank)
                        }

                        Text(DemandAxisRow.explainer)
                            .font(Theme.Font.body(10.5, weight: .regular))
                            .foregroundStyle(Theme.Color.faint)
                            .padding(.top, 2)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("What decides today").apexLabel(Theme.Color.muted)
                }
                .listRowBackground(Theme.Color.panel)
                .listRowSeparator(.hidden)
            }

            ForEach(OptionLibrary.categories) { category in
                Section {
                    ForEach(category.options) { option in
                        optionRow(option, in: category)
                    }
                    .listRowBackground(Theme.Color.panel)
                    .listRowSeparatorTint(Theme.Color.rule)
                    // Remove leading inset so the stripe reaches the row edge.
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
                    Text(regulation).apexNotice(Theme.Color.signal)
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
            if viewModel.phase == .submitted && viewModel.result != nil && !showReplay {
                showDebrief = true
            }
        }
    }

    // MARK: - Option row

    // The row itself lives in EngineeringOptionRow — the Lab and the
    // Experiment draw the same one, so a change here reaches all three.
    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        EngineeringOptionRow(
            option: option,
            isSelected: viewModel.selectedOption(in: category.id) == option.id,
            isBanned: viewModel.isBanned(option.id),
            costDelta: viewModel.costDeltaIfComparable(for: option),
            isEnabled: viewModel.phase != .submitted
        ) {
            viewModel.select(option.id)
        }
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

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.cream.opacity(0.12))
                    Rectangle()
                        .fill(viewModel.isOverBudget ? Theme.Color.signal : Theme.Color.gain)
                        .frame(width: proxy.size.width * fillFraction)
                        .animation(.snappy(duration: 0.2), value: viewModel.totalCost)
                }
            }
            .frame(height: 4)

            // Submit — red when active (race control style).
            Button {
                viewModel.submit()
                showReplay = viewModel.result != nil
            } label: {
                Text(submitLabel)
                    .font(Theme.Font.display(15))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(viewModel.canSubmit ? Theme.Color.cream : Theme.Color.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        viewModel.canSubmit
                        ? Theme.Color.signal
                        : Theme.Color.signal.opacity(0.12)
                    )
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
