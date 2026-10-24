import CoreGraphics
import Foundation
import SwiftTUIRuntime
import Testing

@_spi(Raster) @testable import SwiftUIHost

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit

  @MainActor
  struct AdversarialSetASceneTests {
    @Test(arguments: Array(66...75))
    func contract(id: Int) async throws {
      if id == 74 {
        do {
          _ = try await s1Bridge().startSession()
          Issue.record("missing session must throw")
        } catch { #expect(error as? NativeSceneBridge.BridgeError == .missingSession) }
        return
      }
      if id == 75 {
        let bridge = s1Bridge()
        let session = S1Session()
        let surface = s1Surface()
        bridge.attach(session: session, surface: surface)
        #expect(try await bridge.startSession() == .inputEnded)
        bridge.stopSession()
        #expect(session.starts == 1 && session.stops == 1)
        return
      }
      if id == 73 {
        weak var retained: SwiftUIHostSceneHost?
        try autoreleasepool {
          let state = try SwiftUIHostAppState(app: S1App())
          let host = try #require(state.sceneHost(for: "first"))
          retained = host
          #expect(retained != nil)
        }
        #expect(retained == nil)
        return
      }
      let requested: WindowIdentifier? = id == 67 ? "second" : id == 68 ? "unknown" : nil
      let state = try SwiftUIHostAppState(app: S1App(), selectedSceneID: requested)
      switch id {
      case 66, 68: #expect(state.selectedSceneID == "first")
      case 67: #expect(state.selectedSceneID == "second")
      case 69:
        state.selectScene("second")
        state.selectScene("unknown")
        #expect(state.selectedSceneID == "second")
      case 70:
        let first = try #require(state.sceneHost(for: "first"))
        let second = try #require(state.sceneHost(for: "second"))
        state.selectScene("second")
        state.selectScene("first")
        #expect(state.sceneHost(for: "first") === first)
        #expect(state.sceneHost(for: "second") === second)
      case 71:
        state.selectScene("second")
        var style = SwiftUIHostTerminalStyle.default
        style.palette.foreground = .red
        state.setStyle(style)
        #expect(state.sceneHost(for: "first")?.style == style)
        #expect(state.sceneHost(for: "second")?.style == style)
      case 72:
        #expect(state.scenes.map(\.id) == ["first", "second"])
        #expect(state.scenes.map(\.title) == ["First", "Second"])
      default: Issue.record("unknown scenario")
      }
    }
  }
#endif
