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
                Section(category.displayName) {
                    ForEach(category.options) { option in
                        optionRow(option, in: category)
                    }
                }
            }

            if let feedback = viewModel.feedback {
                Section("Engineer's Read") {
                    // The reading of the run. When the advice card below
                    // is showing it carries the action, so this drops the
                    // recommendation sentence rather than saying it twice.
                    Label {
                        Text(viewModel.advice == nil ? feedback.reportText : feedback.observationText)
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                    }

                    if let advice = viewModel.advice {
                        adviceRow(advice)
                    }
                }
            }

            if !viewModel.runHistory.isEmpty {
                            Section("This Session — \(viewModel.runHistory.count) run\(viewModel.runHistory.count == 1 ? "" : "s")") {
                                ForEach(Array(viewModel.runHistory.enumerated()), id: \.element.resultHash) { index, result in
                                    let isBest = result.averageLapTimeMillis == viewModel.bestAverageMillis
                                    HStack(alignment: .firstTextBaseline) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 5) {
                                                Text("Run \(viewModel.runHistory.count - index)")
                                                    .foregroundStyle(.secondary)
                                                if isBest {
                                                    Image(systemName: "star.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(.yellow)
                                                }
                                            }
                                            // What was actually tested — turns the
                                            // log from bare numbers into a notebook.
                                            Text(result.setupIdentity.displayText)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Text(FixedPoint.formatLapTime(millis: result.averageLapTimeMillis))
                                            .monospacedDigit()
                                            .fontWeight(isBest ? .semibold : .regular)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
        }
        .navigationTitle(viewModel.mode == .quickRace ? "Quick Race" : "Test Lab")
        .navigationBarTitleDisplayMode(.inline)
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
        Section("Generated Assignment") {
            HStack {
                Text(viewModel.conditions.archetype.displayName)
                    .fontWeight(.medium)
                Spacer()
                Text("\(viewModel.conditions.weather.displayName) · \(viewModel.budget) cr · \(viewModel.circuit.sections.count) sections")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                viewModel.newQuickRace()
            } label: {
                Label("New race", systemImage: "dice")
            }
        }
    }

    private var customConditionsSection: some View {
        Section("Conditions") {
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
                Label("New layout (\(viewModel.circuit.sections.count) sections)", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    // MARK: - Options

    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        let isSelected = viewModel.selectedOption(in: category.id) == option.id
        return Button {
            viewModel.select(option.id)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .foregroundStyle(.primary)
                    effectCaption(for: option)
                }
                Spacer()
                Text("\(option.cost) cr")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }


    /// Trade-off directions (§7): sign = stat direction, color = goodness.
    @ViewBuilder
    private func effectCaption(for option: EngineeringOption) -> some View {
        let upside = OptionEffectSummary.topUpside(of: option)
        let downside = OptionEffectSummary.topDownside(of: option)
        if upside != nil || downside != nil {
            HStack(spacing: 8) {
                if let upside { Text(upside).foregroundStyle(.green) }
                if let downside { Text(downside).foregroundStyle(.orange) }
            }
            .font(.caption2)
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
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(advice.upgrade.category.displayName) → "
                         + OptionLibrary.option(advice.upgrade.to).displayName)
                        .font(.subheadline.weight(.semibold))
                    if let funding = advice.funding {
                        Text("Pay for it: \(funding.category.displayName) → "
                             + OptionLibrary.option(funding.to).displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Apply and run — worth about \(secondsText(advice.gainMillis))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
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
        VStack(spacing: 10) {
            HStack {
                Text("Spent")
                    .foregroundStyle(.secondary)
                Text("\(viewModel.totalCost) / \(viewModel.budget)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(viewModel.isOverBudget ? .red : .primary)
                Spacer()
                if let last = viewModel.lastResult {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(FixedPoint.formatLapTime(millis: last.averageLapTimeMillis))
                            .font(.headline.monospacedDigit())
                        if let best = viewModel.bestAverageMillis {
                            Text("Best \(FixedPoint.formatLapTime(millis: best)) · \(viewModel.runCount) runs")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let best = viewModel.bestAverageMillis {
                    Text("Best \(FixedPoint.formatLapTime(millis: best))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                viewModel.run()
            } label: {
                Text(viewModel.isOverBudget ? "Over Budget" : "Run Simulation")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRun)
        }
        .padding(16)
        .background(.bar)
    }
}
