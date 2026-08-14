import SwiftTUI
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
        scrollingDeltaX: 0,
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

  private func scrollEvent(
    location: NSPoint,
    scrollingDeltaX: CGFloat,
    scrollingDeltaY: CGFloat
  ) -> NSEvent {
    let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 2,
      wheel1: Int32(scrollingDeltaY),
      wheel2: Int32(scrollingDeltaX),
      wheel3: 0
    )!
    event.location = location
    return NSEvent(cgEvent: event)!
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
