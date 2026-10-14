//
//  HoldToLockButton.swift
//  ProjectApex
//
//  Submitting the Daily is the one irreversible decision in the game,
//  and it used to be an ordinary tap — indistinguishable from choosing
//  tires. A press-and-hold makes it a moment: the bar fills under your
//  thumb, a heavy thunk lands when it locks, and letting go early
//  cancels with no harm done. It also ends accidental submits.
//
//  ACCESSIBILITY: a long press is hard or impossible with VoiceOver and
//  some motor impairments, so the same action is exposed as an ordinary
//  accessibility action. Holding is a ceremony, never a gate.
//

import SwiftUI

struct HoldToLockButton: View {
    let title: String
    var holdDuration: Double = 0.85
    let onLock: () -> Void

    @State private var progress = 0.0
    @State private var pressing = false
    @State private var locked = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 13, weight: .bold))
            Text(locked ? "Setup locked" : title)
                .font(Theme.Font.display(15))
                .tracking(1.4)
                .textCase(.uppercase)
                .contentTransition(.identity)
        }
        .foregroundStyle(Theme.Color.cream)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        // The fill sweeps left to right under the label while held.
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Theme.Color.signal.opacity(0.45)
                    Theme.Color.signal
                        .frame(width: proxy.size.width * progress)
                }
            }
        }
        .scaleEffect(pressing && !locked ? 0.98 : 1)
        .animation(.snappy(duration: 0.15), value: pressing)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 40) {
            lock()
        } onPressingChanged: { isPressing in
            guard !locked else { return }
            pressing = isPressing
            if isPressing {
                withAnimation(.linear(duration: holdDuration)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pressing) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lock setup")
        .accessibilityHint("Submits today's setup. This can't be undone.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { lock() }
    }

    private func lock() {
        guard !locked else { return }
        locked = true
        progress = 1
        // Fired directly, not via .sensoryFeedback: locking flips the
        // day to submitted and this button is replaced in the same
        // frame, so a state-driven haptic would never get to play.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onLock()
    }
}
