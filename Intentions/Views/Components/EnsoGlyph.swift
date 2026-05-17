//
//  EnsoGlyph.swift
//  Intentions
//
//  Shared rendition of the canonical Intent ensō, ported from the spec SVG
//  (`docs/superpowers/specs/2026-04-11-app-icon-redesign-design.md`).
//  Four cubic Beziers form a hand-drawn brush circle with a wide top-right
//  gap; the dot is an organic ellipse anchored at (50, 51) rotated -12°.
//
//  Default stroke / dot colors match the shield-preview spec (#BBBBBB / #DDDDDD).
//  Pass custom colors to recolour the glyph for in-app contexts (e.g. the
//  state-lock banner uses `AppConstants.Colors.textSecondary` for both).
//

import SwiftUI

struct EnsoGlyph: View {
    var stroke: Color = Color(red: 0xBB / 255, green: 0xBB / 255, blue: 0xBB / 255)
    var dot: Color = Color(red: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let s = size / 100.0   // spec viewBox 100×100

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 66 * s, y: 22 * s))
                    path.addCurve(
                        to: CGPoint(x: 80 * s, y: 68 * s),
                        control1: CGPoint(x: 84 * s, y: 32 * s),
                        control2: CGPoint(x: 88 * s, y: 52 * s)
                    )
                    path.addCurve(
                        to: CGPoint(x: 32 * s, y: 82 * s),
                        control1: CGPoint(x: 72 * s, y: 84 * s),
                        control2: CGPoint(x: 48 * s, y: 90 * s)
                    )
                    path.addCurve(
                        to: CGPoint(x: 20 * s, y: 34 * s),
                        control1: CGPoint(x: 16 * s, y: 74 * s),
                        control2: CGPoint(x: 12 * s, y: 50 * s)
                    )
                    path.addCurve(
                        to: CGPoint(x: 58 * s, y: 16 * s),
                        control1: CGPoint(x: 27 * s, y: 20 * s),
                        control2: CGPoint(x: 48 * s, y: 14 * s)
                    )
                }
                .stroke(
                    stroke,
                    style: StrokeStyle(lineWidth: 7.5 * s, lineCap: .round)
                )

                Ellipse()
                    .fill(dot)
                    .frame(width: 11 * s, height: 10 * s)
                    .rotationEffect(.degrees(-12))
                    .offset(x: 50 * s - (11 * s) / 2, y: 51 * s - (10 * s) / 2)
            }
            .frame(width: size, height: size)
        }
    }
}
