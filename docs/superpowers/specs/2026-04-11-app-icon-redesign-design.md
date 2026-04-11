# App Icon Redesign — Ensō + Dot

**Date:** 2026-04-11
**Status:** Approved

## Summary

Replace the current serif "I" app icon with an ensō (zen brush circle) containing a center dot. The design communicates calm discipline and intentionality, aligning with the app's purpose of mindful phone usage.

## Design Specification

### Concept

An incomplete brush-stroke circle (ensō) with a wide gap at the top-right, cradling a slightly irregular dot at the center. The ensō represents wholeness and the moment of creation; the gap represents openness and breath; the dot represents focused intention.

### SVG Definition

```svg
<svg viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M 66 22 C 84 32, 88 52, 80 68 C 72 84, 48 90, 32 82 C 16 74, 12 50, 20 34 C 27 20, 48 14, 58 16"
        stroke="#bbb" stroke-width="7.5" stroke-linecap="round"/>
  <ellipse cx="50" cy="51" rx="5.5" ry="5" fill="#ddd"
           transform="rotate(-12 50 51)"/>
</svg>
```

### Visual Properties

| Property | Value |
|----------|-------|
| Background | Pure black (#000000) |
| Stroke color | Light grey (#bbbbbb) |
| Stroke weight | 7.5 (bold) |
| Stroke caps | Round |
| Gap position | Top-right, wide opening |
| Gap rotation | Slight clockwise rotation |
| Dot shape | Organic ellipse (rx=5.5, ry=5) |
| Dot color | Bright grey (#dddddd) |
| Dot rotation | -12° (brush-like irregularity) |
| Dot position | Center, offset 1 unit below vertical center |

### Palette

Monochrome only — black, light grey, bright grey. No color accents.

### Required Assets

- `AppIcon~ios-marketing.png` — 1024x1024px (App Store)
- iOS automatically generates all other sizes from the 1024px source

### Design Rationale

- **Ensō** — a traditional zen symbol representing enlightenment, the universe, and strength. Resonates with the app's mindfulness philosophy.
- **Bold stroke** — conveys discipline and confidence, not fragility.
- **Wide gap** — provides breathing room, avoids feeling closed or rigid.
- **Brush dot** — organic, hand-made quality contrasts with the geometric precision of most app icons. Anchors the composition.
- **Monochrome** — consistent with the app's grayscale UI, reduces visual stimulation in line with the app's purpose.

## Implementation Notes

The SVG must be rendered to a 1024x1024 PNG with the black background filling the full canvas and the ensō centered. The icon should be tested at small sizes (40pt, 60pt) to ensure the gap and dot remain legible — they do based on the size previews reviewed during design.
