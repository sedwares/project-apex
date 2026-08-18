//
//  ExperimentView.swift
//  ProjectApex
//
//  Post-submit sandbox: edit a copy of the locked setup, re-simulate
//  unofficially, compare against the official time. The official
//  result is never touched — this is Test Session's soul, surfaced
//  at the moment curiosity peaks.
//

import SwiftUI
import ProjectApexCore

struct ExperimentView: View {
    @Bindable var viewModel: DailyViewModel

    var body: some View {
        List {
            Section {
                Text("Unofficial test runs on today's conditions. Your submitted result stands.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(OptionLibrary.categories) { category in
                Section(category.displayName) {
                    ForEach(category.options) { option in
                        optionRow(option, in: category)
                    }
                }
            }
        }
        .navigationTitle("Experiment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { testBar }
    }

    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        let isSelected = viewModel.experimentSelectedOption(in: category.id) == option.id
        let wasOfficial = viewModel.selectedOption(in: category.id) == option.id

        return Button {
            viewModel.experimentSelect(option.id)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .foregroundStyle(.primary)
                    effectCaption(for: option)
                }
                if wasOfficial {
                    Text("raced")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
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

    private var testBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Spent")
                    .foregroundStyle(.secondary)
                Text("\(viewModel.experimentTotalCost) / \(viewModel.budget)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(viewModel.experimentIsOverBudget ? .red : .primary)
                Spacer()
                resultReadout
            }

            Button {
                viewModel.runExperiment()
            } label: {
                Text(viewModel.experimentIsOverBudget ? "Over Budget" : "Run Test")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canRunExperiment)
        }
        .padding(16)
        .background(.bar)
    }

    @ViewBuilder
    private var resultReadout: some View {
        if let test = viewModel.experimentResult {
            HStack(spacing: 8) {
                Text(FixedPoint.formatLapTime(millis: test.averageLapTimeMillis))
                    .font(.headline.monospacedDigit())
                if let delta = viewModel.experimentDeltaMillis {
                    Text(deltaText(delta))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(delta < 0 ? .green : (delta > 0 ? .red : .secondary))
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
