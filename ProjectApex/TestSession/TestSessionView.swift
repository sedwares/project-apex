//
//  TestSessionView.swift
//  ProjectApex
//
//  Quick Race / Custom Test — the lab. Conditions up top (editable),
//  the Bay list below, unlimited Run at the bottom with last/best
//  readouts and the Engineer's one-line read.
//

import SwiftUI
import ProjectApexCore

private struct ReplayResultWrapper: Identifiable {
    let result: SimulationResult
    var id: String { result.resultHash }
}

struct TestSessionView: View {
    @State var viewModel: TestSessionViewModel
    @State private var showResultSummary = false

    var body: some View {
        List {
            conditionsSection

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

            if let feedback = viewModel.feedback {
                Section {
                    // The reading of the run. When the advice card below
                    // is showing it carries the action, so this drops the
                    // recommendation sentence rather than saying it twice.
                    Label {
                        Text(viewModel.advice == nil ? feedback.reportText : feedback.observationText)
                            .font(Theme.Font.body(13.5, weight: .regular))
                            .foregroundStyle(Theme.Color.cream)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Theme.Color.signal)
                    }

                    if let advice = viewModel.advice {
                        adviceRow(advice)
                    }
                } header: {
                    Text("Engineer's read").apexLabel(Theme.Color.muted)
                }
                .listRowBackground(Theme.Color.panel)
                .listRowSeparatorTint(Theme.Color.rule)
            }

            if !viewModel.runHistory.isEmpty {
                            Section {
                                ForEach(Array(viewModel.runHistory.enumerated()), id: \.element.resultHash) { index, result in
                                    let isBest = result.averageLapTimeMillis == viewModel.bestAverageMillis
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 5) {
                                                Text("Run \(viewModel.runHistory.count - index)")
                                                    .font(Theme.Font.body(13.5))
                                                    .foregroundStyle(Theme.Color.cream)
                                                if isBest {
                                                    Image(systemName: "star.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(Theme.Color.notice)
                                                }
                                            }
                                            // What was actually tested — turns the
                                            // log from bare numbers into a notebook.
                                            Text(result.setupIdentity.displayText)
                                                .font(Theme.Font.body(11, weight: .regular))
                                                .foregroundStyle(Theme.Color.faint)
                                        }
                                        Spacer()
                                        Text(FixedPoint.formatLapTime(millis: result.averageLapTimeMillis))
                                            .apexData(14, weight: isBest ? .bold : .regular,
                                                      color: isBest ? Theme.Color.cream : Theme.Color.muted)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .listRowBackground(Theme.Color.panel)
                                .listRowSeparatorTint(Theme.Color.rule)
                            } header: {
                                Text("This session — \(viewModel.runHistory.count) run\(viewModel.runHistory.count == 1 ? "" : "s")")
                                    .apexLabel(Theme.Color.muted)
                            }
                        }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Color.ink)
        .navigationTitle(viewModel.mode == .quickRace ? "Quick Race" : "Test Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Recomputed whenever a new result lands. Keyed on the result
        // hash rather than on appearance, so re-running the same setup
        // (identical hash, by determinism) doesn't re-do the search.
        .task(id: viewModel.lastResult?.resultHash) {
            await viewModel.loadAdvice()
        }
        .safeAreaInset(edge: .top) {
            CircuitContextHeader(
                circuit: viewModel.circuit,
                weather: viewModel.conditions.weather,
                budget: viewModel.budget
            )
        }
        .safeAreaInset(edge: .bottom) { runBar }
        .fullScreenCover(item: Binding(
            get: { viewModel.replayResult.map { ReplayResultWrapper(result: $0) } },
            set: { if $0 == nil { viewModel.replayResult = nil } }
        )) { wrapper in
            NavigationStack {
                SimulationReplayView(
                    result: wrapper.result,
                    challenge: viewModel.challengeAdapter
                ) {
                    showResultSummary = true
                }
            }
        }
        .alert(
            "Run Complete",
            isPresented: $showResultSummary,
            presenting: viewModel.replayResult
        ) { _ in
            Button("Done") { viewModel.replayResult = nil }
        } message: { result in
            Text(FixedPoint.formatLapTime(millis: result.averageLapTimeMillis)
                 + " average · " + result.setupIdentity.displayText)
        }
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsSection: some View {
        if viewModel.mode == .quickRace {
            quickRaceConditionsSection
        } else {
            customConditionsSection
        }
    }

    /// Quick Race: the conditions are the brief — read them, race them.
    private var quickRaceConditionsSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.conditions.archetype.displayName)
                    .font(Theme.Font.body(15))
                    .foregroundStyle(Theme.Color.cream)
                Spacer(minLength: 10)
                Text("\(viewModel.conditions.weather.displayName) · \(viewModel.budget) cr · \(viewModel.circuit.sections.count) sections")
                    .apexData(11.5, weight: .medium, color: Theme.Color.muted)
            }
            .padding(.vertical, 2)
            Button {
                viewModel.newQuickRace()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dice")
                    Text("New race")
                }
                .apexLabel(Theme.Color.signal)
            }
        }
        .listRowBackground(Theme.Color.panel)
        .listRowSeparatorTint(Theme.Color.rule)
    }

    private var customConditionsSection: some View {
        Section {
            Picker("Circuit", selection: Binding(
                get: { viewModel.conditions.archetype },
                set: { viewModel.setArchetype($0) }
            )) {
                ForEach(CircuitArchetype.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }

            Picker("Weather", selection: Binding(
                get: { viewModel.conditions.weather },
                set: { viewModel.setWeather($0) }
            )) {
                ForEach(Weather.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }

            Stepper(
                "Budget: \(viewModel.budget) cr",
                value: Binding(
                    get: { viewModel.conditions.budget },
                    set: { viewModel.setBudget($0) }
                ),
                in: TestSessionViewModel.customBudgetRange
            )

            Button {
                viewModel.rerollCircuit()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("New layout (\(viewModel.circuit.sections.count) sections)")
                }
                .apexLabel(Theme.Color.signal)
            }
        }
        .listRowBackground(Theme.Color.panel)
        .listRowSeparatorTint(Theme.Color.rule)
        .tint(Theme.Color.signal)
        .foregroundStyle(Theme.Color.cream)
    }

    // MARK: - Options

    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        let isSelected = viewModel.selectedOption(in: category.id) == option.id
        return Button {
            viewModel.select(option.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Theme.Color.signal : Theme.Color.faint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.displayName)
                        .font(Theme.Font.body(15))
                        .foregroundStyle(Theme.Color.cream)
                    effectCaption(for: option)
                }
                Spacer(minLength: 8)
                Text("\(option.cost) cr")
                    .apexData(13, color: Theme.Color.muted)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    /// Trade-off directions (§7): the SIGN carries stat direction, and
    /// the colour carries goodness — but only the upside gets a colour.
    ///
    /// Downsides were amber, and 24 option rows of amber made the one
    /// colour that is supposed to mean "warning" mean nothing: heat
    /// climbing past 65%, an over-budget total, the biggest sector loss.
    /// It was also the wrong claim. Every option in this game has a
    /// downside by design — that is the whole game — so flagging the
    /// price as an alarm tells the player to avoid something they cannot
    /// avoid. The minus sign already says it costs you.
    @ViewBuilder
    private func effectCaption(for option: EngineeringOption) -> some View {
        let upside = OptionEffectSummary.topUpside(of: option)
        let downside = OptionEffectSummary.topDownside(of: option)
        if upside != nil || downside != nil {
            HStack(spacing: 8) {
                if let upside { Text(upside).foregroundStyle(Theme.Color.gain) }
                if let downside { Text(downside).foregroundStyle(Theme.Color.muted) }
            }
            .font(Theme.Font.body(11, weight: .medium))
        }
    }

    // MARK: - The engineer's next test

    /// One tap to test the suggestion. The Daily has to route this
    /// through the unofficial Experiment sandbox because the official
    /// result is locked; the lab has nothing to protect, so it applies
    /// the setup and runs immediately.
    private func adviceRow(_ advice: EngineerAdvice) -> some View {
        Button {
            viewModel.applyAdvice()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.Color.signal)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(advice.upgrade.category.displayName) → "
                         + OptionLibrary.option(advice.upgrade.to).displayName)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.cream)
                    if let funding = advice.funding {
                        Text("Pay for it: \(funding.category.displayName) → "
                             + OptionLibrary.option(funding.to).displayName)
                            .font(Theme.Font.body(11.5, weight: .regular))
                            .foregroundStyle(Theme.Color.muted)
                    }
                    Text("Apply and run — worth about \(secondsText(advice.gainMillis))")
                        .apexData(11.5, color: Theme.Color.gain)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func secondsText(_ millis: Int) -> String {
        let a = abs(millis)
        return "\(a / 1000).\(String(format: "%03d", a % 1000))s"
    }

    // MARK: - Run bar

    private var runBar: some View {
        VStack(spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spent").apexLabel()
                Text("\(viewModel.totalCost) / \(viewModel.budget)")
                    .apexData(18, weight: .bold,
                              color: viewModel.isOverBudget ? Theme.Color.signal : Theme.Color.cream)
                Spacer()
                if let last = viewModel.lastResult {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(FixedPoint.formatLapTime(millis: last.averageLapTimeMillis))
                            .apexData(18, weight: .bold)
                        if let best = viewModel.bestAverageMillis {
                            Text("Best \(FixedPoint.formatLapTime(millis: best)) · \(viewModel.runCount) runs")
                                .apexData(11, weight: .medium, color: Theme.Color.muted)
                        }
                    }
                } else if let best = viewModel.bestAverageMillis {
                    Text("Best \(FixedPoint.formatLapTime(millis: best))")
                        .apexData(11, weight: .medium, color: Theme.Color.muted)
                }
            }

            Button {
                viewModel.run()
            } label: {
                Text(viewModel.isOverBudget ? "Over budget" : "Run simulation")
                    .font(Theme.Font.display(15))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(viewModel.canRun ? Theme.Color.ink : Theme.Color.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(viewModel.canRun
                                ? Theme.Color.cream : Theme.Color.cream.opacity(0.10))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canRun)
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.Color.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }
}
