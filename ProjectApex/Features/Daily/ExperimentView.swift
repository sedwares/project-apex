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
                    .font(Theme.Font.body(12.5, weight: .regular))
                    .foregroundStyle(Theme.Color.muted)
                    .padding(.vertical, 2)
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
        .navigationTitle("Experiment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Color.ink, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { testBar }
    }

    private func optionRow(_ option: EngineeringOption, in category: EngineeringCategory) -> some View {
        let isSelected = viewModel.experimentSelectedOption(in: category.id) == option.id
        let wasOfficial = viewModel.selectedOption(in: category.id) == option.id

        return Button {
            viewModel.experimentSelect(option.id)
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
                if wasOfficial {
                    // The setup you actually raced, so a sandbox full of
                    // changes still shows what you are departing from.
                    Text("Raced")
                        .font(Theme.Font.label(9))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Color.faint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: 1))
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


    /// Trade-off directions (§7): the SIGN carries stat direction. Only
    /// the upside gets a colour — see TestSessionView for why the
    /// downside lost its amber.
    @ViewBuilder
    private func effectCaption(for option: EngineeringOption) -> some View {
        let upside = OptionEffectSummary.topUpside(of: option)
        let downside = OptionEffectSummary.topDownside(of: option)
        if upside != nil || downside != nil {
            HStack(spacing: 9) {
                if let upside { Text(upside).foregroundStyle(Theme.Color.gain) }
                if let downside { Text(downside).foregroundStyle(Theme.Color.muted) }
            }
            .font(Theme.Font.body(11, weight: .medium))
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
