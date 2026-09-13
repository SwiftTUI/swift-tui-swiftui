# Architecture

## The host boundary

`SwiftUIHost` retains SwiftTUI runtime scene sessions
(`HostedSceneSession`) and presents committed frames (raster, damage, focus,
and accessibility) through AppKit/UIKit-backed SwiftUI views. Input,
clipboard writes, and VoiceOver focus bridge back into the runtime.
Raster drawing selects rows and columns from dirty geometry, recovering wide
glyph leads when damage starts in a continuation cell. Full and incremental
paints clip glyph ink to each declared cell span, including italic and fallback
overhang. Blank cells still paint reverse-video backgrounds and line decorations.
Underline and strikethrough support solid, dotted, dashed, dash-dot,
dash-dot-dot, double and curly patterns. Pattern phase uses surface coordinates,
so a partial paint does not restart a dash or wave at the damaged cell.

`HostedSurfacePresenter` owns shared AppKit/UIKit negotiation and damage state.
It retains disjoint dirty rectangles until native draw callbacks consume them,
because the platform may deliver their bounding rectangle. More than 128 pending
rectangles conservatively requests a full paint. Integration tests drive real
NSWindow/UIWindow view invalidation and mirror the executed paint rectangles
into a bitmap; they do not claim window-server screenshot coverage.
Style changes always repaint. They invalidate negotiated size only when the
measured cell dimensions change; palette-only updates retain size negotiation.

Images outside the dirty region are rejected before lookup. Images retain their
original placement under a visible-bounds clip; blend payloads already cropped to
visible bounds use that cropped placement. AppKit/UIKit applies typed attachment
opacity after lookup. Each presenter owns a `NativeImageCache`: 128 encoded
source owners within 32 MiB and 128 eagerly decoded CGImages within 64 MiB.
Both stores evict least-recently-used entries. Encoded bytes and estimated entry
metadata count toward the source budget; CGImage row bytes times height, encoded
bytes and metadata count toward the decoded budget. Oversized entries remain
usable for the current draw without cache admission. Platform image wrappers
are temporary; the retained bitmap has one eagerly decoded first frame and
respects encoded orientation.

An immutable source owner supplies identity independently of placement and
opacity. Embedded byte keys use a bounded sample for hashing and exact equality
for collisions. File keys include device, inode, size, and nanosecond modification
and change times; reads verify the revision before and after capture. Resolved
file/data references are authoritative. A replaced file or changed animation
frame receives a new owner; an unchanged source avoids rereading and decoding.
Clearing the surface or retiring the presenter releases its stores (temporary
Cocoa wrappers finish releasing when the current autorelease pool drains).

A presenter creates its blend compositor only when needed and retires it with
its caches. The released runtime separately bounds decoded sources at 128 MiB
and blend variants at 256 entries, 4,194,304 decoded pixels and 16 MiB of encoded
bytes plus metadata. The adapter passes captured bytes through that existing
SPI, so file replacement is correct even against the released runtime's older
path-keyed cache. No pre-tag API is required by this package's default build.
The damage clip prevents translucent replay from changing untouched pixels.

## The lockstep `@_spi` contract

The host uses the runtime's internal scene and raster surfaces through
`@_spi(Runners)` imports of the `SwiftTUIRuntime` product. That surface is
tracked upstream by `swift-tui`'s `.spi-api-baseline.txt`; an SPI break there
creates a reviewable diff instead of a silent downstream failure here.

Because `@_spi` surfaces carry no semver guarantee, this package and
`swift-tui` are released and consumed in **lockstep**: consumers pin both
packages to the same tag with `exact:`. The org coordination root's
`swiftui_pretag_native_gate` builds this package against the pre-tag
framework before every release to keep the contract honest.

## Consumer surface

The main integration types are `SwiftUIHostAppView` (the SwiftUI `View`),
`SwiftUIHostConfiguration` (presentation options), `SwiftUIHostAppState`
(starts/stops the runtime; throws when the app declares no scenes), and
`SwiftUIHostTerminalStyle` (font size, palette, theme, cursor).

The host view accepts a configuration value that defaults to `.default`.
Its `showsKeyboardToggleButton` option defaults to `false`; enabling it allows
the iOS manual keyboard toggle when no text-input control is focused. Automatic
keyboard presentation for focused text-input controls is independent of this
option. macOS and Mac Catalyst do not display the toggle.
