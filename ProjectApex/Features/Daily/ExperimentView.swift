//
//  ExperimentView.swift
//  ProjectApex
//
//  Post-submit sandbox: edit a copy of the locked setup, re-simulate
//  unofficially, compare against the official time. The official
//  result is never touched — this is Test Session's soul, surfaced
//  at the moment curiosity peaks.
//
//  CONSISTENCY PASS: this screen used to be the odd one out — no
//  circuit header, no car, no demand chart, its own option row. It is
//  the same job as the Bay (choose eight parts for this circuit), so
//  it is now the same screen, differing only where the sandbox really
//  differs: nothing is official, and the setup you raced is marked.
//

import SwiftUI
import ProjectApexCore

struct ExperimentView: View {
    @Bindable var viewModel: DailyViewModel
    /// The test result being watched as a race, if any.
    @State private var racing: SimulationResult?

    var body: some View {
        List {
            Section {
                Text("Unofficial test runs on today's conditions. Your submitted result stands.")
                    .font(Theme.Font.body(12.5, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
                    .padding(.vertical, 2)
            }
            .listRowBackground(Theme.Color.panel)
            .listRowSeparator(.hidden)

            // The same garage as the Bay and the Lab, built from the
            // sandbox selections. Cards you actually raced are marked, so
            // the departure from the locked car is visible at a glance.
            Section {
                GarageBuilder(
                    selections: viewModel.experimentSelections,
                    circuit: viewModel.challenge.circuit,
                    weather: viewModel.challenge.weather,
                    budget: viewModel.budget,
                    banned: viewModel.bannedOption,
                    identityText: experimentIdentity,
                    costDelta: { viewModel.experimentCostDeltaIfComparable(for: $0) },
                    onSelect: { viewModel.experimentSelect($0) },
                    raced: viewModel.selections
                )
                // Clear of the inset-grouped row's clipped corners.
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .listRowBackground(Theme.Color.ink)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle("Experiment")
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
        .safeAreaInset(edge: .bottom, spacing: 0) { testBar }
        .onAppear { viewModel.beginExperimentIfNeeded() }
        .fullScreenCover(isPresented: Binding(
            get: { racing != nil },
            set: { if !$0 { racing = nil } }
        )) {
            if let racing {
                // The test car races the field AND the official car,
                // drawn as a faded ghost of your own.
                SimulationReplayView(
                    result: racing,
                    challenge: viewModel.challenge,
                    ghost: viewModel.result
                ) {
                    self.racing = nil
                }
            }
        }
    }

    /// The sandbox car's character, once all eight are chosen.
    private var experimentIdentity: String? {
        let picks = viewModel.experimentSelections
        guard picks.count == EngineeringCategoryID.allCases.count else { return nil }
        let setup = PlayerSetup(challengeId: viewModel.challenge.id, selectedOptions: picks)
        return SetupIdentity.derive(from: VehicleBuilder.build(from: setup)).displayText
    }

    // Shared with the Daily bay and the Lab — see EngineeringOptionRow.
    //
    // `isBanned` is the fix this consistency pass was worth doing for.
    // `experimentSelect` has always refused a banned option, but this
    // screen drew it as an ordinary row, so the tap did nothing and
    // said nothing. Now it strikes through, explains itself and stops
    // accepting taps, exactly as it does in the Bay.
    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        EngineeringOptionRow(
            option: option,
            isSelected: viewModel.experimentSelectedOption(in: category.id) == option.id,
            isBanned: viewModel.isBanned(option.id),
            costDelta: viewModel.experimentCostDeltaIfComparable(for: option),
            // The setup you actually raced, so a sandbox full of changes
            // still shows what you are departing from.
            badge: viewModel.selectedOption(in: category.id) == option.id ? "Raced" : nil
        ) {
            viewModel.experimentSelect(option.id)
        }
    }

    private var testBar: some View {
        VStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spent").apexLabel()
                Text("\(viewModel.experimentTotalCost) / \(viewModel.budget)")
                    .apexData(18, weight: .bold,
                              color: viewModel.experimentIsOverBudget
                                  ? Theme.Color.signal : Theme.Color.cream)
                Spacer()
                resultReadout
            }

            // Run test stays instant — five ideas in a minute is the point
            // of a sandbox. Watching is a choice, offered once there is a
            // result to watch.
            if let test = viewModel.experimentResult {
                Button {
                    racing = test
                } label: {
                    Label("Watch race vs official car", systemImage: "flag.checkered")
                        .apexSecondaryButton()
                }
                .buttonStyle(.plain)
            }

            Button {
                viewModel.runExperiment()
            } label: {
                Text(viewModel.experimentIsOverBudget ? "Over budget" : "Run test")
                    .font(Theme.Font.display(15))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(viewModel.canRunExperiment ? Theme.Color.ink : Theme.Color.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(viewModel.canRunExperiment
                                ? Theme.Color.cream : Theme.Color.cream.opacity(0.10))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRunExperiment)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.Color.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }

    @ViewBuilder
    private var resultReadout: some View {
        if let test = viewModel.experimentResult {
            HStack(spacing: 9) {
                Text(FixedPoint.formatLapTime(millis: test.averageLapTimeMillis))
                    .apexData(18, weight: .bold)
                if let delta = viewModel.experimentDeltaMillis {
                    Text(deltaText(delta))
                        .apexData(14, weight: .bold, color: Theme.Color.delta(delta))
                }
            }
        }
    }

    private func deltaText(_ delta: Int) -> String {
        if delta == 0 { return "±0.000" }
        let sign = delta < 0 ? "−" : "+"
        let a = abs(delta)
        return "\(sign)\(a / 1000).\(String(format: "%03d", a % 1000))s"
    }
}
