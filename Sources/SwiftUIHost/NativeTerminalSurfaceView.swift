import CoreGraphics
import Foundation
import SwiftTUIRuntime

// The AppKit (`NSView`) and UIKit (`UIView`) terminal surface views below share
// all of their presentation/negotiation logic. That logic lives once in
// `HostedSurfacePresenter` (see `HostedSurfacePresenter.swift`); each platform
// shell here only wires platform events and applies the presenter's neutral
// `Invalidation` results with its own AppKit/UIKit API.

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  final class NativeTerminalSurfaceView: NSView {
    private let presenter = HostedSurfacePresenter()

    var surface: RasterSurface? { presenter.surface }

    var style: SwiftUIHostTerminalStyle = .default {
      didSet {
        guard oldValue != style else {
          return
        }
        applyMetricsUpdate()
        needsDisplay = true
      }
    }

    var focusPresentation: FocusPresentation = .none
    var allowsTextInput = false
    var preferredGridSize: CellSize? {
      get { presenter.preferredGridSize }
      set {
        guard presenter.preferredGridSize != newValue else {
          return
        }
        presenter.preferredGridSize = newValue
        invalidateNegotiatedSize()
      }
    }
    var onResize: ((CellSize, PixelSize?) -> Void)? {
      get { presenter.onResize }
      set { presenter.onResize = newValue }
    }
    var onInputEvent: ((InputEvent) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
      presenter.intrinsicContentSize(noIntrinsicMetric: Double(NSView.noIntrinsicMetric))
    }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.isOpaque = true
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      wantsLayer = true
      layer?.isOpaque = true
    }

    override func layout() {
      super.layout()
      presenter.publishGridIfNeeded(bounds: bounds.size, backingScale: backingScale)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      presenter.publishGridIfNeeded(bounds: bounds.size, backingScale: backingScale)
    }

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)
      guard let context = NSGraphicsContext.current?.cgContext else {
        return
      }
      NativeRasterSurfaceRenderer.draw(
        surface: presenter.surface,
        style: style,
        metrics: presenter.metrics,
        bounds: bounds,
        dirtyRect: dirtyRect,
        context: context
      )
    }

    func present(
      surface: RasterSurface?,
      damage: PresentationDamage?
    ) {
      apply(presenter.present(surface: surface, damage: damage, bounds: bounds))
    }

    override func keyDown(with event: NSEvent) {
      if let inputEvent = NativeInputMapper.inputEvent(for: event) {
        onInputEvent?(inputEvent)
      } else {
        super.keyDown(with: event)
      }
    }

    override func mouseDown(with event: NSEvent) {
      unsafe window?.makeFirstResponder(self)
      onInputEvent?(
        .mouse(
          .init(
            kind: .down(.primary),
            location: pointerLocation(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    override func mouseDragged(with event: NSEvent) {
      onInputEvent?(
        .mouse(
          .init(
            kind: .dragged(.primary),
            location: pointerLocation(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    override func mouseUp(with event: NSEvent) {
      onInputEvent?(
        .mouse(
          .init(
            kind: .up(.primary),
            location: pointerLocation(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    override func scrollWheel(with event: NSEvent) {
      let deltaX = Int(event.scrollingDeltaX.rounded())
      let deltaY = Int((-event.scrollingDeltaY).rounded())
      guard deltaX != 0 || deltaY != 0 else {
        return
      }

      onInputEvent?(
        .mouse(
          .init(
            kind: .scrolled(deltaX: deltaX, deltaY: deltaY),
            location: pointerLocation(for: event.locationInWindow),
            modifiers: NativeInputMapper.modifiers(for: event)
          )
        )
      )
    }

    private func pointerLocation(
      for windowPoint: NSPoint
    ) -> PointerLocation {
      let local = convert(windowPoint, from: nil)
      return presenter.pointerLocation(
        for: CGPoint(x: local.x, y: local.y),
        in: bounds,
        scale: backingScale
      )
    }

    private var backingScale: CGFloat {
      unsafe window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    private func applyMetricsUpdate() {
      apply(
        presenter.updateMetrics(style: style, bounds: bounds.size, backingScale: backingScale)
      )
    }

    func negotiatedSizeThatFits(
      proposedWidth: CGFloat?,
      proposedHeight: CGFloat?,
      preferredGridSize: CellSize?
    ) -> CGSize {
      presenter.negotiatedSizeThatFits(
        proposedWidth: proposedWidth,
        proposedHeight: proposedHeight,
        preferredGridSize: preferredGridSize,
        backingScale: backingScale
      )
    }

    private func invalidateNegotiatedSize() {
      invalidateIntrinsicContentSize()
      needsLayout = true
    }

    private func apply(_ invalidation: HostedSurfacePresenter.Invalidation) {
      if invalidation.invalidatesNegotiatedSize {
        invalidateNegotiatedSize()
      }
      switch invalidation.display {
      case .none:
        break
      case .full:
        needsDisplay = true
      case .rects(let rects):
        for rect in rects {
          setNeedsDisplay(rect)
        }
      }
    }
  }
#elseif canImport(UIKit)
  import UIKit

  final class NativeTerminalSurfaceView: UIView, UIKeyInput {
    private let presenter = HostedSurfacePresenter()

    var surface: RasterSurface? { presenter.surface }

    var style: SwiftUIHostTerminalStyle = .default {
      didSet {
        guard oldValue != style else {
          return
        }
        applyMetricsUpdate()
        setNeedsDisplay()
      }
    }

    var focusPresentation: FocusPresentation = .none {
      didSet { syncFirstResponder() }
    }

    var allowsTextInput = false {
      didSet { syncFirstResponder() }
    }

    var preferredGridSize: CellSize? {
      get { presenter.preferredGridSize }
      set {
        guard presenter.preferredGridSize != newValue else {
          return
        }
        presenter.preferredGridSize = newValue
        invalidateNegotiatedSize()
      }
    }
    var onResize: ((CellSize, PixelSize?) -> Void)? {
      get { presenter.onResize }
      set { presenter.onResize = newValue }
    }
    var onInputEvent: ((InputEvent) -> Void)?

    override init(frame: CGRect) {
      super.init(frame: frame)
      isOpaque = true
      isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      isOpaque = true
      isMultipleTouchEnabled = false
    }

    override var canBecomeFirstResponder: Bool { true }
    override var intrinsicContentSize: CGSize {
      presenter.intrinsicContentSize(noIntrinsicMetric: Double(UIView.noIntrinsicMetric))
    }
    var hasText: Bool { false }

    override func layoutSubviews() {
      super.layoutSubviews()
      presenter.publishGridIfNeeded(bounds: bounds.size, backingScale: backingScale)
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      presenter.publishGridIfNeeded(bounds: bounds.size, backingScale: backingScale)
      syncFirstResponder()
    }

    override func draw(_ rect: CGRect) {
      guard let context = UIGraphicsGetCurrentContext() else {
        return
      }
      NativeRasterSurfaceRenderer.draw(
        surface: presenter.surface,
        style: style,
        metrics: presenter.metrics,
        bounds: bounds,
        dirtyRect: rect,
        context: context
      )
    }

    func present(
      surface: RasterSurface?,
      damage: PresentationDamage?
    ) {
      apply(presenter.present(surface: surface, damage: damage, bounds: bounds))
    }

    func insertText(_ text: String) {
      for character in text {
        if character == "\n" || character == "\r" {
          onInputEvent?(.key(.init(.return)))
        } else if character == "\t" {
          onInputEvent?(.key(.init(.tab)))
        } else if character == " " {
          onInputEvent?(.key(.init(.space)))
        } else {
          onInputEvent?(.key(.init(.character(character))))
        }
      }
    }

    func deleteBackward() {
      onInputEvent?(.key(.init(.backspace)))
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      var handled = false
      for press in presses {
        guard let inputEvent = NativeInputMapper.inputEvent(for: press) else {
          continue
        }
        onInputEvent?(inputEvent)
        handled = true
      }

      if !handled {
        super.pressesBegan(presses, with: event)
      }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      becomeFirstResponder()
      guard let touch = touches.first else {
        return
      }
      onInputEvent?(
        .mouse(
          .init(
            kind: .down(.primary),
            location: pointerLocation(for: touch.location(in: self))
          )
        )
      )
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else {
        return
      }
      onInputEvent?(
        .mouse(
          .init(
            kind: .dragged(.primary),
            location: pointerLocation(for: touch.location(in: self))
          )
        )
      )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else {
        return
      }
      onInputEvent?(
        .mouse(
          .init(
            kind: .up(.primary),
            location: pointerLocation(for: touch.location(in: self))
          )
        )
      )
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      touchesEnded(touches, with: event)
    }

    private func syncFirstResponder() {
      guard window != nil else {
        return
      }

      if allowsTextInput {
        becomeFirstResponder()
      } else if isFirstResponder, !focusPresentation.prefersTextInput {
        resignFirstResponder()
      }
    }

    private func pointerLocation(
      for local: CGPoint
    ) -> PointerLocation {
      presenter.pointerLocation(
        for: local,
        in: bounds,
        scale: backingScale
      )
    }

    private var backingScale: CGFloat {
      window?.screen.scale ?? UIScreen.main.scale
    }

    private func applyMetricsUpdate() {
      apply(
        presenter.updateMetrics(style: style, bounds: bounds.size, backingScale: backingScale)
      )
    }

    func negotiatedSizeThatFits(
      proposedWidth: CGFloat?,
      proposedHeight: CGFloat?,
      preferredGridSize: CellSize?
    ) -> CGSize {
      presenter.negotiatedSizeThatFits(
        proposedWidth: proposedWidth,
        proposedHeight: proposedHeight,
        preferredGridSize: preferredGridSize,
        backingScale: backingScale
      )
    }

    private func invalidateNegotiatedSize() {
      invalidateIntrinsicContentSize()
      setNeedsLayout()
    }

    private func apply(_ invalidation: HostedSurfacePresenter.Invalidation) {
      if invalidation.invalidatesNegotiatedSize {
        invalidateNegotiatedSize()
      }
      switch invalidation.display {
      case .none:
        break
      case .full:
        setNeedsDisplay()
      case .rects(let rects):
        for rect in rects {
          setNeedsDisplay(rect)
        }
      }
    }
  }
#endif

// `NativeTerminalMetrics`, `NativeRasterSurfaceRenderer`, and the platform
// adapters (`NativePlatformFont`/`Color`/`Image`, `NativeInputMapper`) live in
// `NativeTerminalMetrics.swift`, `NativeRasterSurfaceRenderer.swift`, and
// `NativeTerminalPlatformAdapters.swift` respectively.
