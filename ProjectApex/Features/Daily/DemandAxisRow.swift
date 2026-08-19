//
//  DemandAxisRow.swift
//  ProjectApex
//
//  One row of "what decides today": a stat, your car's level on it, and
//  how much of the lap this circuit spends rewarding it.
//
//  ── WHY THIS IS ITS OWN FILE ───────────────────────────────────────
//  The Engineering Bay and the Race Debrief both draw this chart, and
//  they had drifted into two copies with different bar shapes, different
//  colours and different opacities. That is worse than cosmetic: the Bay
//  is where you decide and the Debrief is where you find out, so if the
//  same four bars look different in the two places, the player cannot
//  carry a read from one to the other.
//
//  ── THE TRAP THIS ENCODES ──────────────────────────────────────────
//  `axis.fraction` is YOUR CAR's level on a stat. `axis.demandText` is
//  how much of the lap THIS CIRCUIT rewards it. Two different
//  quantities. Both copies used to draw the first as a bar and print the
//  second beside it in the same colour, which invites reading them as
//  one measurement — and on a real day that produced "ACCELERATION — 9%
//  of this lap" beside the longest bar on the screen.
//
//  That is not a contradiction, it is the most useful line on the
//  screen: credits spent where the circuit will not pay them back. So
//  the bar's COLOUR encodes the RELATIONSHIP rather than repeating the
//  level it is already showing by length.
//

import SwiftUI
import ProjectApexCore

struct DemandAxisRow: View {

    let axis: VehicleProfile.Axis
    /// Position in demand order. Axes arrive sorted by demand, so
    /// `rank < 2` means "this decides the lap" without a share threshold
    /// that would drift as the circuit generator changes.
    let rank: Int
    var barHeight: CGFloat = 5

    /// Print this once beneath a group of rows. Without it the two
    /// quantities are still ambiguous no matter how they are coloured.
    static let explainer = "Bar is your car. The percentage is how much this circuit rewards it."

    /// Below this, your car is soft on the stat.
    private static let weakLevel = 0.45
    /// Above this, you have spent real credits on it.
    private static let strongLevel = 0.66

    private var decisive: Bool { rank < 2 }

    private var tint: Color {
        if decisive && axis.fraction < Self.weakLevel {
            return Theme.Color.signal          // your time is going here
        }
        if !decisive && axis.fraction > Self.strongLevel {
            return Theme.Color.faint           // paid for, not rewarded
        }
        return Theme.Color.cream
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(axis.name).apexLabel(Theme.Color.cream)
                if axis.isInvertedStat {
                    Text("lower is better")
                        .font(Theme.Font.body(10, weight: .regular))
                        .foregroundStyle(Theme.Color.faint)
                }
                Spacer(minLength: 8)
                if let demand = axis.demandText {
                    Text(demand).apexData(10.5, weight: .medium, color: Theme.Color.muted)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.cream.opacity(0.10))
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(4, proxy.size.width * axis.fraction))
                        .animation(.snappy(duration: 0.25), value: axis.fraction)
                }
            }
            .frame(height: barHeight)
        }
    }
}
