public import Observation
public import CoreGraphics
import SwiftTUIRuntime

public struct SwiftUIHostSceneDescriptor: Identifiable, Hashable, Sendable {
  public var id: WindowIdentifier
  public var title: String?
  public var isDefault: Bool

  public init(
    id: WindowIdentifier,
    title: String? = nil,
    isDefault: Bool = false
  ) {
    self.id = id
    self.title = title
    self.isDefault = isDefault
  }

  init(_ descriptor: SceneDescriptor) {
    self.init(
      id: descriptor.id,
      title: descriptor.title,
      isDefault: descriptor.isDefault
    )
  }
}

@MainActor
@Observable
public final class SwiftUIHostAppState<A: SwiftTUIRuntime.App> {
  public let scenes: [SwiftUIHostSceneDescriptor]

  public private(set) var selectedSceneID: WindowIdentifier
  public private(set) var style: SwiftUIHostTerminalStyle {
    didSet {
      applyStyleToHosts()
    }
  }
  public private(set) var isRunning = false

  @ObservationIgnored
  private var hosts: [WindowIdentifier: SwiftUIHostSceneHost] = [:]

  public init(
    app: A,
    selectedSceneID: WindowIdentifier? = nil,
    style: SwiftUIHostTerminalStyle = .default
  ) throws {
    let manifest = SceneManifest(for: app)
    guard !manifest.scenes.isEmpty else {
      throw AppLaunchError.noScenes
    }

    scenes = manifest.scenes.map(SwiftUIHostSceneDescriptor.init)
    self.style = style

    let defaultSceneID = manifest.defaultSceneID
    self.selectedSceneID =
      selectedSceneID.flatMap { requestedID in
        manifest.scenes.contains(where: { $0.id == requestedID })
          ? requestedID
          : nil
      } ?? defaultSceneID

    for descriptor in scenes {
      let host = try SwiftUIHostSceneHost(
        app: app,
        descriptor: descriptor,
        style: style
      )
      hosts[descriptor.id] = host
    }
  }

  public func selectScene(_ sceneID: WindowIdentifier) {
    guard hosts[sceneID] != nil else {
      return
    }
    selectedSceneID = sceneID
  }

  public func setStyle(_ style: SwiftUIHostTerminalStyle) {
    self.style = style
  }

  public func start() {
    guard !isRunning else {
      return
    }

    isRunning = true
    for host in hosts.values {
      host.start()
    }
  }

  public func stop() {
    for host in hosts.values {
      host.stop()
    }
    isRunning = false
  }

  func sceneHost(
    for sceneID: WindowIdentifier
  ) -> SwiftUIHostSceneHost? {
    hosts[sceneID]
  }

  var currentSceneHost: SwiftUIHostSceneHost? {
    hosts[selectedSceneID]
  }

  private func applyStyleToHosts() {
    guard !hosts.isEmpty else {
      return
    }

    for host in hosts.values {
      host.apply(style: style)
    }
  }
}

// MARK: - Offscreen raster capture (Raster SPI)

@_spi(Raster) extension SwiftUIHostAppState {
  /// The monotonic sequence value for the most recent committed frame of the selected scene.
  /// This value supports settling without polling. It is `nil` before the first frame.
  public var selectedSceneFrameSequence: UInt64? {
    currentSceneHost?.latestFrameSequence
  }

  /// Resizes the surface of the selected scene to `size` cells.
  /// This function causes a render for the new grid.
  /// Before you capture the surface, wait for a new ``selectedSceneFrameSequence``.
  public func resizeSelectedScene(to size: CellSize) {
    currentSceneHost?.resize(to: size, cellPixelSize: nil)
  }

  /// Renders the most recent committed surface of the selected scene to an offscreen `CGImage`.
  /// `scale` specifies the number of backing pixels for each point.
  /// The function returns `nil` before the first committed frame or on a non-AppKit platform.
  public func renderSelectedSceneToCGImage(scale: CGFloat) -> CGImage? {
    currentSceneHost?.renderLatestSurfaceToCGImage(scale: scale)
  }
}
