import CoreGraphics
import SwiftTUIRuntime
import Testing

@testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  @Test
  func native_input_mapper_maps_command_v_to_the_primary_editing_modifier() throws {
    let event = try #require(keyEvent(character: "v", modifiers: .command, keyCode: 9))

    #expect(
      NativeInputMapper.inputEvent(for: event)
        == .key(KeyPress(.character("v"), modifiers: .ctrl))
    )
  }

  @MainActor
  @Test
  func native_input_mapper_maps_control_v_to_the_primary_editing_modifier() throws {
    let event = try #require(keyEvent(character: "v", modifiers: .control, keyCode: 9))

    #expect(
      NativeInputMapper.inputEvent(for: event)
        == .key(KeyPress(.character("v"), modifiers: .ctrl))
    )
  }

  @MainActor
  @Test
  func native_surface_view_emits_mouse_down_before_mouse_up() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let metrics = NativeTerminalMetrics(style: .default)
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }

    let localPoint = NSPoint(
      x: metrics.cellSize.width * 2.5,
      y: metrics.cellSize.height * 1.5
    )
    let point = windowPoint(forLocal: localPoint, in: view)
    view.mouseDown(
      with: mouseEvent(
        type: .leftMouseDown,
        location: point,
        eventNumber: 1
      )
    )

    #expect(events.count == 1)
    #expect(events.first?.mouseKind == .down(.primary))
    let downLocation = try #require(events.first?.mouseLocation)
    #expect(downLocation.cell == CellPoint(x: 2, y: 1))
    #expect(abs(downLocation.location.x - 2.5) < 0.0001)
    #expect(abs(downLocation.location.y - 1.5) < 0.0001)
    guard
      case .subCell(source: .nativePixels, metrics: let precisionMetrics) =
        downLocation.precision
    else {
      Issue.record("expected native sub-cell precision")
      return
    }
    #expect(precisionMetrics.source == .reported)
    #expect(downLocation.rawPixel != nil)

    view.mouseUp(
      with: mouseEvent(
        type: .leftMouseUp,
        location: point,
        eventNumber: 2
      )
    )

    #expect(events.map(\.mouseKind) == [.down(.primary), .up(.primary)])
  }

  @MainActor
  @Test
  func native_surface_view_restores_text_input_first_responder_after_window_resize() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false
    )
    let contentView = NSView(frame: window.contentLayoutRect)
    let surface = NativeTerminalSurfaceView(frame: contentView.bounds)
    let chrome = FirstResponderProbeView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    surface.applyFocusPolicy(
      FocusPresentation(focusedIdentity: nil, semantics: .edit),
      allowsTextInput: true
    )
    contentView.addSubview(surface)
    contentView.addSubview(chrome)
    window.contentView = contentView

    // The representable is configured before AppKit attaches it to a window.
    // Runtime-origin editing focus must take effect when that attachment occurs.
    #expect(window.firstResponder === surface)
    #expect(window.makeFirstResponder(surface))
    #expect(window.firstResponder === surface)

    #expect(window.makeFirstResponder(chrome))
    #expect(window.firstResponder === chrome)
    window.setContentSize(NSSize(width: 480, height: 320))

    // SwiftUI reconfigures the representable with the same runtime-origin
    // editing focus after a resize. That update must restore keyboard input to
    // the terminal surface even though the value itself did not change.
    surface.applyFocusPolicy(
      FocusPresentation(focusedIdentity: nil, semantics: .edit),
      allowsTextInput: true
    )

    #expect(window.firstResponder === surface)
  }

  @MainActor
  @Test(
    arguments: [
      FocusPresentation(focusedIdentity: nil, semantics: .activate),
      FocusPresentation.none,
    ]
  )
  func native_surface_view_does_not_steal_chrome_focus_when_text_input_deactivates(
    nextFocus: FocusPresentation
  ) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled, .resizable],
      backing: .buffered,
      defer: false
    )
    let contentView = NSView(frame: window.contentLayoutRect)
    let surface = NativeTerminalSurfaceView(frame: contentView.bounds)
    let chrome = FirstResponderProbeView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    contentView.addSubview(surface)
    contentView.addSubview(chrome)
    window.contentView = contentView

    surface.applyFocusPolicy(
      FocusPresentation(focusedIdentity: nil, semantics: .edit),
      allowsTextInput: true
    )
    #expect(window.firstResponder === surface)

    #expect(window.makeFirstResponder(chrome))
    #expect(window.firstResponder === chrome)

    surface.applyFocusPolicy(nextFocus, allowsTextInput: false)

    #expect(window.firstResponder === chrome)
  }

  @MainActor
  @Test
  func native_surface_view_emits_drag_and_scroll_events() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let metrics = NativeTerminalMetrics(style: .default)
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }
    let localPoint = NSPoint(
      x: metrics.cellSize.width * 3.25,
      y: metrics.cellSize.height * 1.75
    )
    let point = windowPoint(forLocal: localPoint, in: view)

    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: point,
        eventNumber: 1
      )
    )
    view.scrollWheel(
      with: scrollEvent(
        location: point,
        units: .line,
        scrollingDeltaY: -3
      )
    )

    #expect(events.count == 2)
    #expect(events[0].mouseKind == .dragged(.primary))
    #expect(events[1].mouseKind == .scrolled(deltaX: 0, deltaY: 3))
    let dragLocation = try #require(events[0].mouseLocation)
    #expect(dragLocation.cell == CellPoint(x: 3, y: 1))
    #expect(abs(dragLocation.location.x - 3.25) < 0.0001)
    #expect(abs(dragLocation.location.y - 1.75) < 0.0001)
    let scrollLocation = try #require(events[1].mouseLocation)
    guard case .subCell(source: .nativePixels, metrics: _) = scrollLocation.precision else {
      Issue.record("expected native sub-cell precision")
      return
    }
  }

  @MainActor
  @Test
  func native_surface_view_preserves_sub_cell_drag_inside_one_cell() throws {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let metrics = NativeTerminalMetrics(style: .default)
    var events: [InputEvent] = []
    view.onInputEvent = { events.append($0) }

    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: windowPoint(
          forLocal: NSPoint(
            x: metrics.cellSize.width * 2.10,
            y: metrics.cellSize.height * 1.40
          ),
          in: view
        ),
        eventNumber: 1
      )
    )
    view.mouseDragged(
      with: mouseEvent(
        type: .leftMouseDragged,
        location: windowPoint(
          forLocal: NSPoint(
            x: metrics.cellSize.width * 2.70,
            y: metrics.cellSize.height * 1.40
          ),
          in: view
        ),
        eventNumber: 2
      )
    )

    let first = try #require(events.first?.mouseLocation)
    let second = try #require(events.dropFirst().first?.mouseLocation)
    #expect(first.cell == CellPoint(x: 2, y: 1))
    #expect(second.cell == CellPoint(x: 2, y: 1))
    #expect(first.location != second.location)
  }

  @MainActor
  @Test
  func native_surface_view_growth_probe_is_not_undone_by_unchanged_layout_bounds() {
    let metrics = NativeTerminalMetrics(style: .default)
    let visibleGrid = CellSize(width: 5, height: 3)
    let probeGrid = CellSize(width: 12, height: 6)
    let view = NativeTerminalSurfaceView(
      frame: NSRect(
        x: 0,
        y: 0,
        width: metrics.cellSize.width * CGFloat(visibleGrid.width),
        height: metrics.cellSize.height * CGFloat(visibleGrid.height)
      )
    )
    var resizes: [CellSize] = []
    view.onResize = { size, _ in
      resizes.append(size)
    }
    view.preferredGridSize = visibleGrid
    view.present(
      surface: RasterSurface(
        size: visibleGrid,
        lines: Array(repeating: "", count: visibleGrid.height)
      ),
      damage: nil
    )

    view.layout()
    _ = view.negotiatedSizeThatFits(
      proposedWidth: metrics.cellSize.width * CGFloat(probeGrid.width),
      proposedHeight: metrics.cellSize.height * CGFloat(probeGrid.height),
      preferredGridSize: visibleGrid
    )
    view.layout()

    #expect(resizes == [visibleGrid, probeGrid])
  }

  @MainActor
  @Test
  func native_surface_view_initial_probe_is_not_undone_by_placeholder_layout_bounds() {
    let metrics = NativeTerminalMetrics(style: .default)
    let placeholderGrid = CellSize(width: 1, height: 1)
    let probeGrid = CellSize(width: 12, height: 6)
    let view = NativeTerminalSurfaceView(
      frame: NSRect(
        x: 0,
        y: 0,
        width: metrics.cellSize.width * CGFloat(placeholderGrid.width),
        height: metrics.cellSize.height * CGFloat(placeholderGrid.height)
      )
    )
    var resizes: [CellSize] = []
    view.onResize = { size, _ in
      resizes.append(size)
    }

    _ = view.negotiatedSizeThatFits(
      proposedWidth: metrics.cellSize.width * CGFloat(probeGrid.width),
      proposedHeight: metrics.cellSize.height * CGFloat(probeGrid.height),
      preferredGridSize: nil
    )
    view.layout()

    #expect(resizes == [probeGrid])
  }

  // STUI-1216: AppKit reports precise scrolling (trackpad, Magic Mouse and
  // momentum) in points and discrete wheels in lines; the runtime's scroll
  // deltas are whole terminal cells (`ScrollWheelEvent`). The rule matches
  // the browser host: points divide by the presented cell pitch, a line is one
  // cell, sub-cell travel carries until it reverses, and each axis of one
  // record is bounded to 16 cells.
  @MainActor
  @Test
  func native_surface_view_converts_precise_points_to_cells() {
    let probe = ScrollProbe()

    probe.scroll(scrollEvent(scrollingDeltaY: -3 * probe.cell.height))

    #expect(probe.scrolls == [.scrolled(deltaX: 0, deltaY: 3)])
  }

  @MainActor
  @Test
  func native_surface_view_carries_sub_cell_points_and_drops_carry_on_reversal() {
    let probe = ScrollProbe()
    let height = probe.cell.height

    probe.scroll(scrollEvent(scrollingDeltaY: -(height - 1)))
    #expect(probe.scrolls.isEmpty)
    probe.scroll(scrollEvent(scrollingDeltaY: -1))
    #expect(probe.scrolls == [.scrolled(deltaX: 0, deltaY: 1)])

    probe.events.removeAll()
    probe.scroll(scrollEvent(scrollingDeltaY: -(height - 1)))
    probe.scroll(scrollEvent(scrollingDeltaY: (height / 2).rounded(.down)))
    probe.scroll(scrollEvent(scrollingDeltaY: -(height - 1)))
    #expect(probe.scrolls.isEmpty, "a reversal drops the opposing sub-cell carry")
    probe.scroll(scrollEvent(scrollingDeltaY: -1))
    #expect(probe.scrolls == [.scrolled(deltaX: 0, deltaY: 1)])
  }

  @MainActor
  @Test
  func native_surface_view_bounds_each_axis_to_sixteen_cells() {
    let probe = ScrollProbe()

    probe.scroll(scrollEvent(scrollingDeltaY: -40 * probe.cell.height))
    probe.scroll(scrollEvent(scrollingDeltaY: -1))
    #expect(
      probe.scrolls == [.scrolled(deltaX: 0, deltaY: 16)],
      "clamped travel is discarded, not carried")

    probe.events.removeAll()
    probe.scroll(scrollEvent(units: .line, scrollingDeltaY: -25))
    #expect(probe.scrolls == [.scrolled(deltaX: 0, deltaY: 16)])

    probe.events.removeAll()
    probe.scroll(scrollEvent(scrollingDeltaX: 40 * probe.cell.width))
    #expect(probe.scrolls.map(\.horizontalMagnitude) == [16])
  }

  @MainActor
  @Test
  func native_surface_view_carries_fractional_wheel_lines() {
    let probe = ScrollProbe()

    for _ in 0..<3 {
      probe.scroll(scrollEvent(units: .line, scrollingDeltaY: -0.25))
    }
    #expect(probe.scrolls.isEmpty)
    probe.scroll(scrollEvent(units: .line, scrollingDeltaY: -0.25))
    #expect(probe.scrolls == [.scrolled(deltaX: 0, deltaY: 1)])
  }

  @MainActor
  @Test
  func native_surface_view_converts_horizontal_points_by_cell_width() {
    let probe = ScrollProbe()
    let cell = probe.cell

    probe.scroll(scrollEvent(scrollingDeltaX: 2 * cell.width, scrollingDeltaY: -cell.height))
    #expect(probe.scrolls.map(\.horizontalMagnitude) == [2])
    #expect(probe.scrolls.map(\.verticalDelta) == [1])

    probe.events.removeAll()
    probe.scroll(
      scrollEvent(scrollingDeltaX: cell.width - 1, scrollingDeltaY: -(cell.height - 1)))
    #expect(probe.scrolls.isEmpty)
    probe.scroll(scrollEvent(scrollingDeltaX: 1))
    #expect(probe.scrolls.map(\.horizontalMagnitude) == [1])
    #expect(probe.scrolls.map(\.verticalDelta) == [0], "each axis carries independently")
    probe.scroll(scrollEvent(scrollingDeltaY: -1))
    #expect(probe.scrolls.map(\.verticalDelta) == [0, 1])
  }

  @MainActor
  @Test
  func native_surface_view_converts_gesture_and_momentum_phases_alike() {
    let probe = ScrollProbe()
    let height = probe.cell.height

    probe.scroll(scrollEvent(phase: .mayBegin))
    probe.scroll(scrollEvent(scrollingDeltaY: -10, phase: .began))
    #expect(probe.scrolls.isEmpty)
    probe.scroll(scrollEvent(scrollingDeltaY: -10, phase: .changed))
    probe.scroll(scrollEvent(phase: .ended))
    #expect(probe.scrolls == [.scrolled(deltaX: 0, deltaY: 1)])

    probe.scroll(scrollEvent(scrollingDeltaY: -2 * height, momentumPhase: .begin))
    probe.scroll(scrollEvent(scrollingDeltaY: -2 * height, momentumPhase: .continuous))
    probe.scroll(scrollEvent(momentumPhase: .end))
    probe.scroll(scrollEvent(units: .line))
    #expect(
      probe.scrolls == [
        .scrolled(deltaX: 0, deltaY: 1),
        .scrolled(deltaX: 0, deltaY: 2),
        .scrolled(deltaX: 0, deltaY: 2),
      ])
  }

  @MainActor
  @Test
  func native_surface_view_keeps_discrete_wheel_lines_as_cells() throws {
    let probe = ScrollProbe()

    probe.scroll(scrollEvent(units: .line, scrollingDeltaY: 1))
    // Option, not Shift: AppKit turns a Shift-held vertical wheel into
    // horizontal scrolling before the view sees it.
    probe.scroll(scrollEvent(units: .line, scrollingDeltaY: -3, flags: .maskAlternate))

    #expect(
      probe.scrolls == [
        .scrolled(deltaX: 0, deltaY: -1),
        .scrolled(deltaX: 0, deltaY: 3),
      ])
    guard case .mouse(let modified) = try #require(probe.events.last) else {
      Issue.record("expected a mouse event")
      return
    }
    #expect(modified.modifiers == .alt)
  }

  // STUI-1217: AppKit scroll views move their viewport left for a positive
  // `scrollingDeltaX` and up for a positive `scrollingDeltaY`; the runtime's
  // positive deltas move right and down, so both axes are negated.
  @MainActor
  @Test
  func native_surface_view_horizontal_direction_follows_appkit_scroll_views() {
    let probe = ScrollProbe()

    probe.scroll(scrollEvent(units: .line, scrollingDeltaX: 1))

    #expect(probe.scrolls == [.scrolled(deltaX: -1, deltaY: 0)])
  }

  // STUI-1217: AppKit turns a Shift-held vertical wheel into horizontal
  // scrolling; Shift with the wheel turned down scrolls right.
  @MainActor
  @Test
  func native_surface_view_shift_wheel_scrolls_right_like_appkit() throws {
    let probe = ScrollProbe()

    probe.scroll(scrollEvent(units: .line, scrollingDeltaY: -3, flags: .maskShift))

    #expect(probe.scrolls == [.scrolled(deltaX: 3, deltaY: 0)])
    guard case .mouse(let shifted) = try #require(probe.events.last) else {
      Issue.record("expected a mouse event")
      return
    }
    #expect(shifted.modifiers == .shift)
  }

  @MainActor
  @Test
  func native_surface_view_converts_horizontal_momentum_in_appkit_direction() {
    let probe = ScrollProbe()
    let width = probe.cell.width

    probe.scroll(scrollEvent(scrollingDeltaX: -2 * width, momentumPhase: .begin))
    probe.scroll(scrollEvent(scrollingDeltaX: -2 * width, momentumPhase: .continuous))
    probe.scroll(scrollEvent(momentumPhase: .end))

    #expect(
      probe.scrolls == [
        .scrolled(deltaX: 2, deltaY: 0),
        .scrolled(deltaX: 2, deltaY: 0),
      ])
  }

  @MainActor
  @Test
  func native_surface_view_vertical_direction_is_unchanged_by_the_horizontal_fix() {
    let probe = ScrollProbe()
    let height = probe.cell.height

    probe.scroll(scrollEvent(units: .line, scrollingDeltaY: 1))
    probe.scroll(scrollEvent(scrollingDeltaY: -height))
    probe.scroll(scrollEvent(scrollingDeltaY: -2 * height, momentumPhase: .begin))

    #expect(
      probe.scrolls == [
        .scrolled(deltaX: 0, deltaY: -1),
        .scrolled(deltaX: 0, deltaY: 1),
        .scrolled(deltaX: 0, deltaY: 2),
      ])
  }

  @MainActor
  private func windowPoint(
    forLocal local: NSPoint,
    in view: NativeTerminalSurfaceView
  ) -> NSPoint {
    NSPoint(
      x: local.x,
      y: view.bounds.height - local.y
    )
  }

  private func mouseEvent(
    type: NSEvent.EventType,
    location: NSPoint,
    eventNumber: Int
  ) -> NSEvent {
    NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      eventNumber: eventNumber,
      clickCount: 1,
      pressure: 1
    )!
  }

  private func keyEvent(
    character: String,
    modifiers: NSEvent.ModifierFlags,
    keyCode: UInt16
  ) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: character,
      charactersIgnoringModifiers: character,
      isARepeat: false,
      keyCode: keyCode
    )
  }

  /// A scroll event as AppKit delivers it. Pixel units are precise
  /// (`hasPreciseScrollingDeltas`) and report whole points; line units are a
  /// discrete wheel and report (possibly fractional) lines.
  private func scrollEvent(
    location: NSPoint = .zero,
    units: CGScrollEventUnit = .pixel,
    scrollingDeltaX: CGFloat = 0,
    scrollingDeltaY: CGFloat = 0,
    phase: CGScrollPhase? = nil,
    momentumPhase: CGMomentumScrollPhase? = nil,
    flags: CGEventFlags = []
  ) -> NSEvent {
    let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: units,
      wheelCount: 2,
      wheel1: Int32(scrollingDeltaY.rounded(.towardZero)),
      wheel2: Int32(scrollingDeltaX.rounded(.towardZero)),
      wheel3: 0
    )!
    if units == .line {
      event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: scrollingDeltaY)
      event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: scrollingDeltaX)
    }
    if let phase {
      event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
    }
    if let momentumPhase {
      event.setIntegerValueField(
        .scrollWheelEventMomentumPhase, value: Int64(momentumPhase.rawValue))
    }
    event.flags = flags
    event.location = location
    return NSEvent(cgEvent: event)!
  }

  /// A surface view at the default style that records the input it emits.
  @MainActor
  private final class ScrollProbe {
    let view = NativeTerminalSurfaceView(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
    let cell = NativeTerminalMetrics(style: .default).cellSize
    var events: [InputEvent] = []

    init() {
      view.onInputEvent = { [unowned self] in events.append($0) }
    }

    var scrolls: [MouseEvent.Kind] { events.compactMap(\.mouseKind) }

    func scroll(_ event: NSEvent) {
      view.scrollWheel(with: event)
    }
  }

  private final class FirstResponderProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
  }
#elseif canImport(UIKit)
  import UIKit

  @Test
  func native_input_mapper_maps_command_v_to_the_primary_editing_modifier() {
    #expect(
      NativeInputMapper.inputEvent(
        keyCode: .keyboardV,
        charactersIgnoringModifiers: "v",
        modifierFlags: .command
      ) == .key(KeyPress(.character("v"), modifiers: .ctrl))
    )
  }

  @Test
  func native_input_mapper_maps_control_v_to_the_primary_editing_modifier() {
    #expect(
      NativeInputMapper.inputEvent(
        keyCode: .keyboardV,
        charactersIgnoringModifiers: "v",
        modifierFlags: .control
      ) == .key(KeyPress(.character("v"), modifiers: .ctrl))
    )
  }

  @MainActor
  @Test
  func native_surface_view_claims_and_dispatches_primary_editing_key_commands() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let rootViewController = UIViewController()
    let surface = NativeTerminalSurfaceView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    rootViewController.view.addSubview(surface)
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    #expect(surface.becomeFirstResponder())

    var events: [InputEvent] = []
    surface.onInputEvent = { events.append($0) }

    let commands = try #require(surface.keyCommands)
    let expectedInputs = ["a", "c", "x", "v"]
    let expectedModifierFlags: [UIKeyModifierFlags] = [.command, .control]
    for input in expectedInputs {
      for modifierFlags in expectedModifierFlags {
        let command = try #require(
          commands.first {
            $0.input == input && $0.modifierFlags == modifierFlags
          }
        )
        #expect(command.discoverabilityTitle == nil)

        let eventCountBeforeDispatch = events.count
        surface.perform(command.action, with: command)
        #expect(events.count == eventCountBeforeDispatch + 1)
        #expect(
          events.last
            == .key(KeyPress(.character(Character(input)), modifiers: .ctrl))
        )
      }
    }
  }

  @MainActor
  @Test(
    arguments: [
      FocusPresentation(focusedIdentity: nil, semantics: .activate),
      FocusPresentation.none,
    ]
  )
  func native_surface_view_does_not_steal_chrome_focus_when_text_input_deactivates(
    nextFocus: FocusPresentation
  ) {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let rootViewController = UIViewController()
    let surface = NativeTerminalSurfaceView(frame: window.bounds)
    let chrome = FirstResponderProbeView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    rootViewController.view.addSubview(surface)
    rootViewController.view.addSubview(chrome)
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    surface.applyFocusPolicy(
      FocusPresentation(focusedIdentity: nil, semantics: .edit),
      allowsTextInput: true
    )
    #expect(surface.isFirstResponder)

    #expect(chrome.becomeFirstResponder())
    #expect(chrome.isFirstResponder)

    surface.applyFocusPolicy(nextFocus, allowsTextInput: false)

    #expect(chrome.isFirstResponder)
  }

  @MainActor
  @Test
  func native_surface_view_pointer_lifecycle_defers_first_responder_until_after_action_dispatch() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let rootViewController = UIViewController()
    let surface = NativeTerminalSurfaceView(frame: window.bounds)
    let chrome = FirstResponderProbeView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    rootViewController.view.addSubview(surface)
    rootViewController.view.addSubview(chrome)
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    surface.applyFocusPolicy(
      FocusPresentation(focusedIdentity: nil, semantics: .activate),
      allowsTextInput: false
    )
    #expect(chrome.becomeFirstResponder())
    #expect(chrome.isFirstResponder)

    var events: [InputEvent] = []
    var chromeWasResponderDuringDispatch: [Bool] = []
    surface.onInputEvent = {
      events.append($0)
      chromeWasResponderDuringDispatch.append(chrome.isFirstResponder)
    }
    let touch = TouchProbe(location: CGPoint(x: 40, y: 40))
    surface.touchesBegan([touch], with: nil)
    surface.touchesEnded([touch], with: nil)

    #expect(events.map(\.mouseKind) == [.down(.primary), .up(.primary)])
    #expect(chromeWasResponderDuringDispatch == [true, true])
    #expect(surface.isFirstResponder)

    surface.insertText("k")
    #expect(events.last == .key(KeyPress(.character("k"))))
  }

  @MainActor
  @Test
  func native_surface_view_cancelled_pointer_does_not_steal_chrome_focus() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    let rootViewController = UIViewController()
    let surface = NativeTerminalSurfaceView(frame: window.bounds)
    let chrome = FirstResponderProbeView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
    rootViewController.view.addSubview(surface)
    rootViewController.view.addSubview(chrome)
    window.rootViewController = rootViewController
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    surface.applyFocusPolicy(
      FocusPresentation(focusedIdentity: nil, semantics: .activate),
      allowsTextInput: false
    )
    #expect(chrome.becomeFirstResponder())

    var events: [InputEvent] = []
    surface.onInputEvent = { events.append($0) }
    let touch = TouchProbe(location: CGPoint(x: 40, y: 40))
    surface.touchesBegan([touch], with: nil)
    surface.touchesCancelled([touch], with: nil)

    #expect(events.map(\.mouseKind) == [.down(.primary), .up(.primary)])
    #expect(chrome.isFirstResponder)
  }

  private final class FirstResponderProbeView: UIView {
    override var canBecomeFirstResponder: Bool { true }
  }

  private final class TouchProbe: UITouch {
    private let probeLocation: CGPoint

    init(location: CGPoint) {
      probeLocation = location
      super.init()
    }

    override func location(in view: UIView?) -> CGPoint {
      probeLocation
    }
  }
#endif

// STUI-1216: the accumulator ports the browser host's wheel rule
// (swift-tui-web STUI-1191 `wheelTravel` and `wholeWheelCells`).
@Test
func scroll_wheel_accumulator_matches_the_browser_rule() {
  func step(
    _ accumulator: inout NativeScrollWheelAccumulator,
    _ travel: Double,
    unit: NativeScrollWheelAccumulator.Unit = .lines
  ) -> Int {
    accumulator.cellDelta(horizontal: 0, vertical: travel, unit: unit).deltaY
  }

  var carry = NativeScrollWheelAccumulator()
  #expect([0.4, 0.4, 0.4].map { step(&carry, $0) } == [0, 0, 1])
  #expect(abs(carry.remainderY - 0.2) < 1e-9)

  var reversal = NativeScrollWheelAccumulator()
  #expect(step(&reversal, 0.9) == 0)
  #expect(step(&reversal, -0.5) == 0)
  #expect(reversal.remainderY == -0.5, "a reversal drops the opposing carry")
  #expect(step(&reversal, 0.5) == 0)
  #expect(reversal.remainderY == 0.5)

  var bound = NativeScrollWheelAccumulator()
  #expect(step(&bound, 16) == 16)
  #expect(bound.remainderY == 0)
  #expect(step(&bound, 16.9) == 16)
  #expect(abs(bound.remainderY - 0.9) < 1e-9, "the bound applies above 16 whole cells")
  var clamped = NativeScrollWheelAccumulator()
  #expect(step(&clamped, 17.5) == 16)
  #expect(clamped.remainderY == 0, "clamped travel is discarded")
  #expect(step(&clamped, 0.2) == 0)
  #expect(step(&clamped, -17) == -16)
  #expect(clamped.remainderY == 0)
  #expect(step(&clamped, .greatestFiniteMagnitude) == 16)

  var nonfinite = NativeScrollWheelAccumulator()
  #expect(step(&nonfinite, 0.5) == 0)
  #expect(step(&nonfinite, .nan) == 0)
  #expect(step(&nonfinite, .infinity) == 0)
  #expect(nonfinite.remainderY == 0.5, "nonfinite travel neither scrolls nor drops the carry")

  var points = NativeScrollWheelAccumulator()
  let cell = CGSize(width: 8, height: 17)
  #expect(
    points.cellDelta(horizontal: 12, vertical: 34, unit: .points(cellSize: cell)) == (1, 2))
  #expect(points.remainderX == 0.5)
  #expect(
    points.cellDelta(horizontal: 4, vertical: 0, unit: .points(cellSize: cell)) == (1, 0),
    "each axis divides by its own pitch and carries independently")

  var degenerate = NativeScrollWheelAccumulator()
  #expect(
    degenerate.cellDelta(horizontal: 3, vertical: -0.25, unit: .points(cellSize: .zero))
      == (1, -1),
    "a nonpositive pitch falls back to one cell in the delta's direction")
}

extension MouseEvent.Kind {
  fileprivate var horizontalMagnitude: Int? {
    guard case .scrolled(let deltaX, _) = self else { return nil }
    return abs(deltaX)
  }

  fileprivate var verticalDelta: Int? {
    guard case .scrolled(_, let deltaY) = self else { return nil }
    return deltaY
  }
}

extension InputEvent {
  fileprivate var mouseKind: MouseEvent.Kind? {
    guard case .mouse(let mouseEvent) = self else {
      return nil
    }
    return mouseEvent.kind
  }

  fileprivate var mouseLocation: PointerLocation? {
    guard case .mouse(let mouseEvent) = self else {
      return nil
    }
    return mouseEvent.location
  }
}
