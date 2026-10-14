//
//  ShareCardView.swift
//  ProjectApex
//
//  The day's result as an image: 1080×1350 (4:5, the shape feeds
//  crop least), rendered on device with ImageRenderer.
//
//  Built only from ShareCard, which never carries a part name or the
//  setup identity — so nothing drawn here can spoil the day.
//

import SwiftUI
import ProjectApexCore

extension Medal {
    /// App-layer colour; Core owns the thresholds, not the palette.
    var color: Color {
        switch self {
        case .gold: return Theme.Color.notice
        case .silver: return Color(red: 0.80, green: 0.82, blue: 0.86)
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.24)
        }
    }
}

extension SectorTier {
    /// Same coding as the replay's timing tower and the emoji blocks.
    var shareColor: Color {
        switch self {
        case .ahead, .optimal: return Theme.Color.session
        case .onPace, .close: return Theme.Color.gain
        case .offPace: return Theme.Color.notice
        case .weak: return Theme.Color.signal
        }
    }
}

/// A medal as a badge: disc + word. Used on the card, the race board
/// and the debrief, so it reads the same everywhere.
struct MedalBadge: View {
    let medal: Medal?
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: size * 0.4) {
            Circle()
                .fill(medal?.color ?? Theme.Color.rule)
                .frame(width: size * 0.9, height: size * 0.9)
                .overlay(Circle().stroke(Theme.Color.ink.opacity(0.35), lineWidth: 1))
            Text(medal?.label ?? "No medal")
                .font(Theme.Font.display(size))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(medal?.color ?? Theme.Color.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(medal.map { "\($0.label) medal" } ?? "No medal")
    }
}

struct ShareCardView: View {
    let card: ShareCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Masthead
            HStack(alignment: .firstTextBaseline) {
                Text("Project Apex")
                    .font(Theme.Font.display(15))
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Color.signal)
                Spacer()
                if let day = card.dayNumber {
                    Text("Day \(day)")
                        .font(Theme.Font.display(15))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Color.muted)
                }
            }

            Text("\(card.circuitName) · \(card.weatherName)")
                .font(Theme.Font.display(26))
                .foregroundStyle(Theme.Color.cream)
                .padding(.top, 16)

            Spacer(minLength: 18)

            // Position
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("P\(card.position)")
                    .font(Theme.Font.display(104))
                    .foregroundStyle(Theme.Color.cream)
                Text("of \(card.fieldSize)")
                    .font(Theme.Font.display(24))
                    .foregroundStyle(Theme.Color.muted)
            }
            MedalBadge(medal: card.medal, size: 20)
                .padding(.top, 2)

            Spacer(minLength: 18)

            // Sectors
            if !card.sectorTiers.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(card.sectorTiers.enumerated()), id: \.offset) { index, tier in
                        VStack(alignment: .leading, spacing: 6) {
                            Rectangle()
                                .fill(tier.shareColor)
                                .frame(height: 16)
                            Text("S\(index + 1)")
                                .font(Theme.Font.label(11))
                                .tracking(1.4)
                                .foregroundStyle(Theme.Color.muted)
                        }
                    }
                }
            }
            if let gap = card.gapText {
                Text(gap)
                    .font(Theme.Font.body(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.cream)
                    .padding(.top, 10)
            }

            Spacer(minLength: 18)

            // Footer
            Rectangle().fill(Theme.Color.rule).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text("Build the car. Watch it race.")
                    .font(Theme.Font.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.cream)
                Spacer()
                Text("App Store")
                    .font(Theme.Font.label(11))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Color.muted)
            }
            .padding(.top, 12)
        }
        .padding(28)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .background(
            ZStack(alignment: .leading) {
                Theme.Color.ink
                RadialGradient(
                    colors: [Theme.Color.signal.opacity(0.18), .clear],
                    center: .topTrailing, startRadius: 10, endRadius: 360
                )
                Rectangle().fill(Theme.Color.signal).frame(width: 5)
            }
        )
        .environment(\.colorScheme, .dark)
    }
}

/// Share button that sends the image with the text alongside, and falls
/// back to the text alone until the image has rendered.
struct ShareResultButton<Label: View>: View {
    let card: ShareCard
    let text: String
    @ViewBuilder let label: () -> Label

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    subject: Text(card.title),
                    message: Text(text),
                    preview: SharePreview(card.title, image: image)
                ) { label() }
            } else {
                ShareLink(item: text) { label() }
            }
        }
        // ShareLink has no action hook; this counts intent, not
        // completion — nobody can see whether a share landed.
        .simultaneousGesture(TapGesture().onEnded {
            Analytics.shareTapped(dayNumber: card.dayNumber)
        })
        .task(id: card) { image = Self.render(card) }
    }

    @MainActor
    static func render(_ card: ShareCard) -> Image? {
        let renderer = ImageRenderer(content: ShareCardView(card: card))
        renderer.scale = 3   // 360×450 pt → 1080×1350 px
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

#Preview {
    ShareCardView(card: ShareCard(
        dayNumber: 232, circuitName: "Mountain", weatherName: "Rain",
        position: 2, fieldSize: 6, medal: .silver,
        sectorTiers: [.optimal, .close, .offPace],
        gapToBestMillis: 840, averageLapMillis: 91_000
    ))
}
