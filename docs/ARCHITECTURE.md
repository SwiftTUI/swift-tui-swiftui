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

Images outside the dirty region are rejected before lookup. Images retain their
original placement under a visible-bounds clip; blend payloads already cropped to
visible bounds use that cropped placement. AppKit/UIKit applies typed attachment
opacity after lookup. The blend compositor caches by content identity; ordinary
file/data image lookup still constructs a platform image for each intersecting
draw. The damage clip prevents translucent replay from changing untouched pixels.

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

Three public types: `SwiftUIHostAppView` (the SwiftUI `View`),
`SwiftUIHostAppState` (starts/stops the runtime; throws when the app declares
no scenes), and `SwiftUIHostTerminalStyle` (font size, palette, theme,
cursor). Everything else is implementation detail.
