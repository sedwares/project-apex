//
//  EngineeringBayView.swift
//  ProjectApex
//
//  The core screen: 8 categories × 3 options, live budget, submit.
//  Over-budget selection is allowed by design — the total goes red
//  and Submit gates. The player feels the trade-off.
//
//  GARAGE LAYOUT (v1.2):
//  This used to be a list of twenty-four option rows with the car at
//  the top — so the moment you scrolled down to Brakes or Cooling, the
//  car scrolled away and every reaction to your choice happened off
//  screen. Players said it "didn't feel like a game".
//
//  Now the car is the stage and never leaves it. You work one system at
//  a time: a tab per system, three option cards, and the car answers
//  each pick right above your thumb. Picking in an empty system moves
//  on to the next open one, so building the car reads as a sequence of
//  fittings rather than a form; swipe the cards to move freely.
//

import SwiftUI
import ProjectApexCore

struct EngineeringBayView: View {
    @Bindable var viewModel: DailyViewModel
    @State private var showDebrief = false
    @State private var showReplay = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            // Car, board and cards must share one screen even under the
            // circuit header and a regulation strip — the moment the cards
            // push the car off the top, the reaction to a pick happens out
            // of sight again. GarageBuilder is laid out for that.
            GarageBuilder(
                selections: viewModel.selections,
                circuit: viewModel.challenge.circuit,
                weather: viewModel.challenge.weather,
                budget: viewModel.budget,
                banned: viewModel.bannedOption,
                identityText: viewModel.identityPreview?.displayText,
                isEnabled: viewModel.phase == .building,
                costDelta: { viewModel.costDeltaIfComparable(for: $0) },
                onSelect: { viewModel.select($0) }
            )
            .padding(.horizontal, Theme.Metric.gutter)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshDayState() }
        }
        .navigationDestination(isPresented: $showDebrief) {
            RaceDebriefView(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showReplay) {
            if let result = viewModel.result {
                LockInSequence(
                    selections: viewModel.selections,
                    result: result,
                    challenge: viewModel.challenge
                ) {
                    showReplay = false
                    showDebrief = true
                }
            }
        }
    }

    // MARK: - Budget bar

    private var budgetBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(viewModel.phase == .submitted ? "Locked setup" : "Engineering budget")
                    .apexLabel()
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

            // Submit — red when active (race control style). Once the
            // day is locked this is the way FORWARD to the debrief
            // rather than a dead "Submitted" label: coming back here
            // from the debrief used to leave the screen with no exit
            // but the back button.
            // Ready to submit: hold to lock. Locking is the one move in
            // the game you cannot take back, so it is a press-and-hold
            // with a thunk, not a tap. Every other state keeps the plain
            // button below.
            if viewModel.canSubmit {
                HoldToLockButton(title: "Hold to lock setup") { lockIn() }
            } else {
                Button {
                    if viewModel.phase == .submitted {
                        showDebrief = true
                    } else {
                        viewModel.submit()
                        showReplay = viewModel.result != nil
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(submitLabel)
                            .font(Theme.Font.display(15))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            // Never morph a Text's content — "Choose 3 more"
                            // dissolving into "Submit" is the bug class that
                            // has bitten this project four times.
                            .contentTransition(.identity)
                        if isSubmittedWithResult {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(actionIsLive ? Theme.Color.cream : Theme.Color.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        actionIsLive
                        ? Theme.Color.signal
                        : Theme.Color.signal.opacity(0.12)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!actionIsLive)
            }
        }
        .padding(.horizontal, Theme.Metric.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Theme.Color.ink)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
        }
    }

    // MARK: - Lock in

    /// Submit, then present the garage-to-race sequence WITHOUT the
    /// cover's slide-up — the sequence fades itself in, and a sheet
    /// sliding over a car about to roll out reads as two animations
    /// fighting.
    private func lockIn() {
        viewModel.submit()
        guard viewModel.result != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showReplay = true }
    }

    private var fillFraction: Double {
        guard viewModel.budget > 0 else { return 0 }
        return min(1, Double(viewModel.totalCost) / Double(viewModel.budget))
    }

    /// True once there is a result to go and look at. A submitted day
    /// with no result is not reachable in practice, but the button must
    /// not promise a debrief that would render empty.
    private var isSubmittedWithResult: Bool {
        viewModel.phase == .submitted && viewModel.result != nil
    }

    /// Whether the primary button does anything: submit while building,
    /// open the debrief once locked.
    private var actionIsLive: Bool {
        isSubmittedWithResult || viewModel.canSubmit
    }

    private var submitLabel: String {
        if viewModel.phase == .submitted {
            return isSubmittedWithResult ? "View debrief" : "Submitted"
        }
        // Midnight UTC can pass while the player is mid-build. canSubmit
        // already refuses, but a disabled button still reading
        // "Submit — lock setup" looks like a bug rather than a deadline.
        if viewModel.isClosed { return "Assignment closed" }
        if !viewModel.isComplete {
            let remaining = EngineeringCategoryID.allCases.count - viewModel.selections.count
            return "Choose \(remaining) more"
        }
        if viewModel.usesBannedOption { return "Illegal setup" }
        if viewModel.isOverBudget { return "Over budget" }
        return "Submit — lock setup"
    }
}
