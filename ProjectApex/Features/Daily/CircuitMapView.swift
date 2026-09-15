//
//  CircuitMapView.swift
//  ProjectApex
//
//  The day's circuit, drawn as a map.
//
//  ── WHY ────────────────────────────────────────────────────────────
//  CircuitLoop learned to build a real per-circuit shape for the
//  replay, and then only the replay ever showed it — you saw the track
//  you had been building for AFTER you had finished building for it.
//  The brief screen described the circuit in a bar strip and a
//  sentence; it could not show you the place.
//
//  Same geometry, same kerb rules, same sector split as the replay, so
//  the map on the brief is the circuit you then drive rather than an
//  artist's impression of it.
//
//  SwiftUI's origin is top-left, hence .down — the same maths with the
//  SpriteKit axis would render the loop mirrored.
//

import SwiftUI
import ProjectApexCore

struct CircuitMapView: View {
    let circuit: Circuit
    var trackWidth: CGFloat = 11
    var inset: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let loop = CircuitLoop(
                size: proxy.size,
                sections: circuit.sections,
                archetype: circuit.archetype,
                inset: inset,
                axis: .down
            )
            ZStack {
                // Tarmac, then a hairline down the middle of it so the
                // ribbon reads as a road rather than a drawn shape.
                Path(loop.path())
                    .stroke(Theme.Color.cream.opacity(0.17),
                            style: StrokeStyle(lineWidth: trackWidth,
                                               lineCap: .round, lineJoin: .round))
                Path(loop.path())
                    .stroke(Theme.Color.cream.opacity(0.07), lineWidth: 1)

                furniture(loop)
            }
        }
    }

    /// Kerbs, sector gates and the start line. One Canvas rather than a
    /// node per mark — a busy circuit is sixty-odd stripes and they are
    /// all static.
    private func furniture(_ loop: CircuitLoop) -> some View {
        Canvas { context, _ in
            for kerb in loop.kerbStripes(offset: trackWidth / 2 - 0.5, density: 150) {
                let stripe = Path(CGRect(x: -3.1, y: -1.5, width: 6.2, height: 3.0))
                    .applying(CGAffineTransform(translationX: kerb.point.x, y: kerb.point.y)
                        .rotated(by: kerb.heading))
                context.fill(stripe, with: .color(
                    kerb.isRed ? Theme.Color.signal.opacity(0.85)
                               : Theme.Color.cream.opacity(0.8)))
            }

            // Sector gates. Index 0 is the start line, drawn below.
            let gates = loop.sectorGateArcs
            for (i, t) in gates.enumerated() where i > 0 {
                let mark = Path(CGRect(x: -1.4, y: -(trackWidth / 2 + 1),
                                       width: 2.8, height: trackWidth + 2))
                    .applying(CGAffineTransform(translationX: loop.point(at: t).x,
                                                y: loop.point(at: t).y)
                        .rotated(by: loop.heading(at: t)))
                context.fill(mark, with: .color(
                    (i == 1 ? Theme.Color.cream : Theme.Color.notice).opacity(0.8)))
            }

            // Start/finish, checkered — the one marking everybody reads
            // without being told what it is.
            let origin = loop.point(at: 0)
            let place = CGAffineTransform(translationX: origin.x, y: origin.y)
                .rotated(by: loop.heading(at: 0))
            let cell: CGFloat = 3.0
            for row in 0..<2 {
                for col in 0..<4 {
                    let square = Path(CGRect(
                        x: (CGFloat(row) - 0.5) * cell - cell / 2,
                        y: (CGFloat(col) - 1.5) * cell - cell / 2,
                        width: cell, height: cell
                    )).applying(place)
                    context.fill(square, with: .color(
                        (row + col) % 2 == 0 ? Theme.Color.cream : Theme.Color.ink))
                }
            }
        }
    }
}
