# Adopt the Philon design language, add the maker's mark and an info screen

Branch `feat/philon-design-system` · 5 commits · 21 files · +2080 / −377

CrewListr Pro's interface was stock SwiftUI: system greys, `ContentUnavailableView`,
`.bar` materials, `.borderedProminent`. It worked and it looked like nothing in
particular. This brings it onto the design language Philon already uses, adds
Charis Tsevis's maker's mark in the lower-left corner of the window, and replaces
AppKit's stock About panel with an info screen that carries what the app actually
promises.

## Where the values come from

Philon ships two skins in one stylesheet: a dark "web" theme, and layered over it a
macOS skin built from Apple's system greys with one borrowed accent. **The macOS
skin is the one that renders**, so that is the one ported. Every colour, radius and
type size in `UI/Design/Theme.swift` is read out of `philon/src/styles.css` rather
than approximated by eye, and each token carries the CSS selector it came from.

| | Light | Dark | From |
|---|---|---|---|
| Window ground | `#F5F5F7` | `#1C1C1E` | `.workspace` |
| Panel | `#FFFFFF` | `#2C2C2E` | `.conversion-grid` |
| Inset | `#FFFFFF` | `#3A3A3C` | `.queue-list article` |
| Hairline | `rgba(60,60,67,.16)` | `rgba(235,235,245,.13)` | panel border |
| Accent fill | `#74D2A2` | `#74D2A2` | `--accent` |
| Accent as type | `#0F7A55` | `#74D2A2` | `--accent-text` |

The accent is two values, not one, for the reason Philon's own comment gives: the
mint reads well as a fill, but as *type* on a white panel it falls to about 1.9:1,
so accent text on light surfaces uses the same hue taken down to a legible value.

Radii are Philon's three and nothing else — 10 for panels, 7 for controls, 6 inside
a control. Colours are dynamic `NSColor`s rather than a light/dark pair resolved at
read time, so a window dragged to a display with a different profile, or the system
switching at sunset, follows correctly.

**One decision worth a second opinion.** The brief was "like Philon in every
detail", so the accent is Philon's mint. CrewListr Pro's app icon is blue, and the
two do not obviously belong together. The whole interface hangs off `Theme.accent`
and `Theme.accentText` — changing those two constants to the icon's blue re-keys
every screen and touches nothing else.

## What changed on each screen

- **Sidebar** — a brand lockup at the top, Philon's eyebrow over the trip list,
  rows carrying a progress track and a cleared/total count, and a footer that
  states where the data lives before it offers the two actions.
- **Documents** — each row is Philon's `.queue-list article`: a filled status
  disc, the identity, and how far the review has got. The export-readiness strip
  became the verified/warning card used everywhere else, so "ready" and "not
  ready" differ in more than one word.
- **Review pane** — the confirm control is now a filled green disc against an
  empty ring. That was a colour-only distinction before; a ring and a disc differ
  in shape too, so the state survives a reader who cannot separate the tints.
  Extraction notes became verified/warning cards, and a confirmed field's row
  carries a faint green ground.
- **Export sheet** — Philon's batch-report shape: the counts, then the table. When
  it is not ready, every blocker gets its own warning card rather than one
  sentence hiding that a missing yacht name and a missing field are different
  problems.
- **Trip inspector** — heading, insetted field groups, footer whose primary action
  is the only filled control on the panel.

## The maker's mark

`UI/Design/Brand.swift` — Philon's `.makers-mark` exactly: fixed to the lower-left
of the window, 20pt, 55% opacity until the pointer is over it, opening tsevis.com.
It is a window-level overlay rather than a child of the sidebar, because a
collapsed sidebar must not take the mark with it. The asset is 40pt so 20pt is its
@2x. If the resource bundle is missing it degrades to a text glyph rather than
disappearing.

## The info screen

`UI/AboutScreen.swift`, built to the measurements of Philon's splash rather than
something that resembles them: 640 wide, 250pt of full-bleed key art, 26pt
margins, 36/13/11pt in the lockup, 12.5pt body, 10.5pt legal. It shows once at
first launch, keyed by version, and is reachable afterwards from the ⓘ button in
the toolbar and from **About CrewListr Pro** in the app menu, which now replaces
AppKit's stock panel.

The key art is drawn rather than photographed — a crew list's own geometry, header
boxes and ruled rows, over the ink and accent glow of Philon's workspace. Philon
puts real output on its splash; the equivalent here would mean putting a real
person's passport data on the front of the program, so the motif is deliberately a
diagram with no invented names in it.

The text lives in `About.swift` as data with tests on it, following Philon's
`about.ts`, so a claim cannot go missing without a test noticing. Identity is read
from `Version.swift` rather than typed twice.

## Tests

**166 tests, 0 failures, 13 skipped** (opt-in, unchanged).

22 new, in two suites:

- `AboutTests` (14) — asserts what the info screen must *say*, not how it is
  worded. The privacy promise, the review gate, a licence for every shipped
  component, HTTPS on every link, and the first-launch/once-per-version rule.
  Wording can be rewritten freely; a dropped claim fails.
- `BrandAssetTests` (8) — both marks resolve through `Bundle.module`, are square,
  and are large enough for their Retina size; and the packaging step that carries
  them exists.

## Packaging

`Package.swift` gains `resources: [.process("Resources")]` on the executable
target, which makes SwiftPM emit `CrewListrProMac_CrewListrProMac.bundle`.
`release.sh` now copies it into `Contents/Resources`, and fails loudly if it is
missing. **Without that step `Bundle.module` is nil in a packaged build and the
marks degrade to glyphs silently** — the kind of failure nobody notices until a
user asks why the corner is empty. `BrandAssetTests` guards the wiring.

## Regressions deliberately avoided

The session that had been working in these files flagged four defects it had
already fixed here. All four are preserved, and one was a live catch:

- `TripSidebar` still uses `VStack { List; footer }`, never
  `.safeAreaInset(edge: .bottom)` on the List, which clips the rows' leading edge.
- Presentation modifiers still hang off the concrete `NavigationSplitView`. The
  new About sheet and first-launch task were added there too, not to a wrapper.
- **Caught in review:** I had changed the Improve menu to
  `.menuStyle(.borderlessButton)`, which renders the label but stops the menu
  taking clicks. Reverted to `.menuStyle(.button)` with a comment so it does not
  get "tidied" again. No `.accessoryBar` anywhere.
- No hand-copying into `dist/`; build via `./scripts/release.sh`.

## Not verified visually

Per the standing rule not to launch the app to verify a change, **this has not been
run**. It builds clean and the suite is green, but no screen here has been looked
at. Worth a pass before merge, particularly the document column's selection
rendering and the info screen's key art.

## Two things to resolve before this can be a real PR

1. **There is no remote.** `crewlisterpromac` had no git repository at all; this
   branch sits on a repository initialised during this work. Opening an actual PR
   needs a GitHub repository to be created and pushed to.

2. **`MRZ.swift` and `MRZTests.swift` in this diff are not mine.** They are a
   concurrent MRZ expiry-year fix from the other session, swept in by `git add -A`
   while it was editing. Good work, unrelated to the design pass; it should be
   split into its own commit or landed separately.
