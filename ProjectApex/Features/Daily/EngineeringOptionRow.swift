//
//  EngineeringOptionRow.swift
//  ProjectApex
//
//  ── WHY THIS IS ITS OWN FILE ───────────────────────────────────────
//  Three screens let you choose an engineering option: the Daily bay,
//  the Lab (Quick Race / Custom Test) and the post-race Experiment.
//  They had three private `optionRow` functions that had drifted apart,
//  and the drift was not only cosmetic:
//
//  • Only the Bay drew the timing-tower left stripe, so the same list
//    of twenty-four options read as a different game in each screen.
//  • Only the Bay showed the cost delta, which is the number that makes
//    a budget feel like a budget.
//  • The Experiment never rendered a BAN. `experimentSelect` silently
//    returns on a banned option, so the row looked perfectly tappable
//    and simply did nothing — the worst kind of bug, because the player
//    concludes the app is broken rather than that the option is barred.
//
//  One row, three call sites. Everything that legitimately differs
//  between the screens is a parameter; everything else cannot drift.
//
//  The row is deliberately dumb: it knows nothing about view models,
//  categories or budgets. Each screen decides what is selected, what is
//  banned and what the delta means, because those answers come from
//  three different places.
//

import SwiftUI
import ProjectApexCore

struct EngineeringOptionRow: View {

    let option: EngineeringOption

    /// The current pick in this option's category.
    let isSelected: Bool

    /// Barred by today's regulation. A banned row is struck through,
    /// explains itself, and is disabled — never silently inert.
    var isBanned: Bool = false

    /// Cost change if this option replaced the current pick, or nil
    /// when there is nothing to compare against (nothing chosen yet in
    /// the category) or the swap is free. The row never prints "+0".
    var costDelta: Int? = nil

    /// Small outlined marker on the right of the name — the Experiment
    /// uses it to mark the setup you actually raced.
    var badge: String? = nil

    /// False once the screen is read-only (a submitted Daily).
    var isEnabled: Bool = true

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Timing tower left stripe: red on selected, hairline
                // otherwise. A banned row gets no stripe at all — it is
                // not a position in the tower.
                Rectangle()
                    .fill(isBanned ? Color.clear
                          : (isSelected ? Theme.Color.signal : Theme.Color.rule))
                    .frame(width: 3)
                    .animation(.snappy(duration: 0.12), value: isSelected)

                HStack(spacing: 12) {
                    Image(systemName: isBanned
                          ? "nosign"
                          : (isSelected ? "checkmark.circle.fill" : "circle"))
                        .font(.system(size: 17))
                        .foregroundStyle(isBanned ? Theme.Color.faint
                                         : (isSelected ? Theme.Color.signal : Theme.Color.faint))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.displayName)
                            .font(Theme.Font.body(15))
                            .foregroundStyle(
                                isBanned ? Theme.Color.faint
                                : (isSelected ? Theme.Color.cream : Theme.Color.cream.opacity(0.70))
                            )
                            .strikethrough(isBanned)

                        if isBanned {
                            Text("Not permitted at this event")
                                .font(Theme.Font.body(10.5, weight: .regular))
                                .foregroundStyle(Theme.Color.faint)
                        } else {
                            effectCaption
                        }
                    }

                    if let badge {
                        Text(badge)
                            .font(Theme.Font.label(9))
                            .tracking(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.Color.faint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: 1))
                    }

                    Spacer(minLength: 8)

                    if !isBanned, !isSelected, let costDelta, costDelta != 0 {
                        Text(costDelta > 0 ? "+\(costDelta)" : "\(costDelta)")
                            .apexData(11, color: costDelta > 0 ? Theme.Color.notice : Theme.Color.gain)
                    }

                    Text("\(option.cost) cr")
                        .apexData(13, color: Theme.Color.muted)
                }
                .padding(.vertical, 10)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBanned)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(traits)
    }

    /// Explicitly typed so both branches resolve — a bare ternary of
    /// two option-set literals does not always infer here.
    private var traits: AccessibilityTraits {
        isSelected ? [.isButton, .isSelected] : [.isButton]
    }

    /// Trade-off directions (§7): the SIGN carries the stat direction,
    /// and the colour carries goodness — but only the upside gets a
    /// colour.
    ///
    /// Downsides were amber, and 24 option rows of amber made the one
    /// colour that is supposed to mean "warning" mean nothing: heat
    /// climbing past 65%, an over-budget total, the biggest sector loss.
    /// It was also the wrong claim. Every option in this game has a
    /// downside by design — that is the whole game — so flagging the
    /// price as an alarm tells the player to avoid something they cannot
    /// avoid. The minus sign already says it costs you.
    @ViewBuilder
    private var effectCaption: some View {
        if option.topUpside != nil || option.topDownside != nil {
            HStack(spacing: 9) {
                if let up = option.topUpside {
                    Text(up).foregroundStyle(Theme.Color.gain)
                }
                if let down = option.topDownside {
                    Text(down).foregroundStyle(Theme.Color.muted)
                }
            }
            .font(Theme.Font.body(11, weight: .medium))
        }
    }

    /// VoiceOver reads a spec, not a pile of symbols: what it is, what
    /// it costs, what it trades and whether you can have it.
    private var accessibilityText: String {
        var parts: [String] = [option.displayName]
        if isBanned {
            parts.append("not permitted at this event")
        } else {
            if let up = option.topUpside { parts.append(Self.spoken(up)) }
            if let down = option.topDownside { parts.append(Self.spoken(down)) }
            parts.append("\(option.cost) credits")
            if let costDelta, costDelta != 0, !isSelected {
                parts.append(costDelta > 0 ? "\(costDelta) more than your pick"
                                           : "\(abs(costDelta)) less than your pick")
            }
        }
        if let badge { parts.append(badge) }
        return parts.joined(separator: ", ")
    }

    /// "+Power" / "−Heat" are legible as glyphs and unreadable aloud.
    /// The sign is the whole meaning, and it appears on BOTH sides —
    /// a cooler engine is an upside spelled with a minus — so the
    /// mapping is by sign, never by which slot the string came from.
    private static func spoken(_ effect: String) -> String {
        if let rest = effect.stripping(prefix: "+") { return "more \(rest)" }
        if let rest = effect.stripping(prefix: "−") { return "less \(rest)" }
        if let rest = effect.stripping(prefix: "-") { return "less \(rest)" }
        return effect
    }
}

private extension String {
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
