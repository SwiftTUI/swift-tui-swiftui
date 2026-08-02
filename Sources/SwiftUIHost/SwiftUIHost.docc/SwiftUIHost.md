# ``SwiftUIHost``

Embed SwiftTUI scenes inside native SwiftUI apps.

## Overview

`SwiftUIHost` retains SwiftTUI scenes inside a native SwiftUI lifecycle. It owns
the native surface bridge, scene-selection controls, style mapping, clipboard
integration, accessibility overlay, and platform-announcement bridge.

Use this product to add SwiftTUI content to an existing SwiftUI app on an Apple
platform.

## Topics

### Native Host Views

- ``SwiftUIHostAppView``

### Host State

- ``SwiftUIHostAppState``
- ``SwiftUIHostSceneDescriptor``

### Scene Host

- ``SwiftUIHostSceneHost``

### Styling

- ``SwiftUIHostTerminalStyle``
- ``SwiftUIHostTerminalPalette``
- ``SwiftUIHostCursorStyle``
