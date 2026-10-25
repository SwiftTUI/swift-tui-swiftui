import CoreGraphics
import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftUIHost

@MainActor
@Suite(.serialized)
struct SwiftUIHostAccessibilityTests {
  @MainActor
  @Test
  func scene_host_stores_latest_semantic_snapshot() async throws {
    let host = try SwiftUIHostSceneHost(
      app: AccessibilityHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )

    let frameSignal = MainActorConditionSignal()
    host.onFrameForTesting = { frameSignal.notify() }
    host.start()
    defer {
      host.stop()
    }

    await frameSignal.wait {
      host.latestSurface?.renderedText.contains("Host") == true
        && host.latestSemanticSnapshot?.accessibilityNodes.contains {
          $0.label == "Host action"
        } == true
        && host.focusedAccessibilityIdentity != nil
    }

    let snapshot = try #require(host.latestSemanticSnapshot)
    let focusedIdentity = try #require(host.focusedAccessibilityIdentity)
    let actionNode = try #require(
      snapshot.accessibilityNodes.first {
        $0.label == "Host action"
      }
    )

    #expect(focusedIdentity == actionNode.identity)

    let overlay = HostedAccessibilityOverlay(
      semanticSnapshot: snapshot,
      focusedIdentity: focusedIdentity,
      cellSize: CGSize(width: 8, height: 16)
    )

    #expect(overlay.requestedNativeFocusID == focusedIdentity.path)
  }

  @MainActor
  @Test
  func scene_host_receives_snapshot_with_accessibility_hidden_subtrees_pruned() async throws {
    let host = try SwiftUIHostSceneHost(
      app: HiddenAccessibilityHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )

    let frameSignal = MainActorConditionSignal()
    host.onFrameForTesting = { frameSignal.notify() }
    host.start()
    defer {
      host.stop()
    }

    await frameSignal.wait {
      host.latestSemanticSnapshot?.accessibilityNodes.contains {
        $0.label == "Visible action"
      } == true
    }

    let labels = host.latestSemanticSnapshot?.accessibilityNodes.compactMap(\.label) ?? []
    #expect(labels.contains("Visible action"))
    #expect(!labels.contains("Hidden action"))
  }

  @MainActor
  @Test
  func scene_host_drops_stale_semantic_host_frames() throws {
    let host = try SwiftUIHostSceneHost(
      app: AccessibilityHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )
    let root = Identity(components: ["root"])

    host.receiveFrameForTesting(
      SemanticHostFrame(
        sequence: 2,
        raster: RasterSurface(size: .init(width: 3, height: 1), lines: ["new"]),
        semantics: SemanticSnapshot(
          accessibilityNodes: [
            AccessibilityNode(
              identity: root.child("new"),
              parentIdentity: root,
              rect: .init(origin: .zero, size: .init(width: 3, height: 1)),
              role: .status,
              label: "new"
            )
          ]
        ),
        focusedIdentity: root.child("new")
      )
    )
    host.receiveFrameForTesting(
      SemanticHostFrame(
        sequence: 1,
        raster: RasterSurface(size: .init(width: 3, height: 1), lines: ["old"]),
        semantics: SemanticSnapshot(
          accessibilityNodes: [
            AccessibilityNode(
              identity: root.child("old"),
              parentIdentity: root,
              rect: .init(origin: .zero, size: .init(width: 3, height: 1)),
              role: .status,
              label: "old"
            )
          ]
        ),
        focusedIdentity: root.child("old")
      )
    )

    #expect(host.latestSurface?.renderedText.contains("new") == true)
    #expect(host.latestSemanticSnapshot?.accessibilityNodes.first?.label == "new")
    #expect(host.focusedAccessibilityIdentity == root.child("new"))
  }

  // STUI-1211: runtime focus on a List row names the row's selection button
  // through its action identity, the rule the host wire applies
  // (`(actionIdentity ?? identity) == focusedIdentity`). The browser ARIA tree
  // focuses that button; the SwiftUI overlay must request the same element.
  @MainActor
  @Test(.timeLimit(.minutes(1)), arguments: RuntimeFocusListScene.allCases)
  func list_row_runtime_focus_requests_native_focus_on_selection_button(
    _ scene: RuntimeFocusListScene
  ) async throws {
    let harness = try RuntimeFocusHarness(scene: scene)
    defer { harness.stop() }

    await harness.waitForFocus(marker: scene.firstRowText)
    try harness.expectListRowFocus(selectionLabel: "Select row 1")

    await harness.sendKey(.arrowDown) { $0.focusedIdentity != $1.focusedIdentity }
    try harness.expectListRowFocus(selectionLabel: "Select row 2")
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func button_runtime_focus_moves_native_focus_with_tab() async throws {
    let harness = try RuntimeFocusHarness(app: RuntimeFocusButtonsApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "One")
    let one = try #require(harness.node(role: .button, label: "One"))
    #expect(harness.focusedIdentity == one.identity)
    #expect(harness.overlay.requestedNativeFocusID == one.identity.path)
    #expect(harness.overlay.mappings.filter(\.isFocused).map(\.id) == [one.identity.path])

    await harness.sendKey(.tab) { $0.focusedIdentity != $1.focusedIdentity }
    let two = try #require(harness.node(role: .button, label: "Two"))
    #expect(harness.focusedIdentity == two.identity)
    #expect(harness.overlay.requestedNativeFocusID == two.identity.path)
    #expect(harness.overlay.mappings.filter(\.isFocused).map(\.id) == [two.identity.path])
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func table_runtime_focus_stays_on_table_node_across_row_selection() async throws {
    let harness = try RuntimeFocusHarness(app: RuntimeFocusTableApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Row 0")
    try harness.expectTableFocus()

    await harness.sendKey(.arrowDown) { $0.raster != $1.raster }
    try harness.expectTableFocus()
  }
}

@MainActor
private struct AccessibilityHostApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      Button("Host") {}
        .accessibilityLabel("Host action")
    }
  }
}

@MainActor
private struct HiddenAccessibilityHostApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Visible") {}
          .accessibilityLabel("Visible action")
        Button("Hidden") {}
          .accessibilityLabel("Hidden action")
          .accessibilityHidden()
      }
    }
  }
}

enum RuntimeFocusListScene: String, CaseIterable, CustomTestStringConvertible, Sendable {
  case builder
  case data

  var firstRowText: String {
    switch self {
    case .builder: "List row 1"
    case .data: "Item alpha"
    }
  }

  var testDescription: String { rawValue }
}

@MainActor
private final class RuntimeFocusHarness {
  struct State {
    let focusedIdentity: Identity?
    let raster: RasterSurface?
  }

  let host: SwiftUIHostSceneHost
  private let signal = MainActorConditionSignal()

  convenience init(scene: RuntimeFocusListScene) throws {
    switch scene {
    case .builder: try self.init(app: RuntimeFocusBuilderListApp())
    case .data: try self.init(app: RuntimeFocusDataListApp())
    }
  }

  init<A: SwiftTUIRuntime.App>(app: A) throws {
    host = try SwiftUIHostSceneHost(
      app: app,
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )
    let signal = signal
    host.onFrameForTesting = { signal.notify() }
    host.start()
  }

  func stop() {
    host.stop()
  }

  var focusedIdentity: Identity? { host.focusedAccessibilityIdentity }

  var overlay: HostedAccessibilityOverlay {
    HostedAccessibilityOverlay(
      semanticSnapshot: host.latestSemanticSnapshot,
      focusedIdentity: host.focusedAccessibilityIdentity,
      cellSize: CGSize(width: 8, height: 16)
    )
  }

  private var state: State {
    State(focusedIdentity: host.focusedAccessibilityIdentity, raster: host.latestSurface)
  }

  func waitForFocus(marker: String) async {
    let host = host
    await signal.wait {
      host.focusedAccessibilityIdentity != nil
        && host.latestSurface?.renderedText.contains(marker) == true
    }
  }

  /// Sends one key and resumes on the first committed frame whose state
  /// differs from the state before the key, as `changed(before, now)` decides.
  func sendKey(
    _ key: KeyEvent,
    changed: @escaping @MainActor (State, State) -> Bool
  ) async {
    let before = state
    host.send(.key(.init(key)))
    await signal.wait { [self] in changed(before, state) }
  }

  func node(role: AccessibilityRole, label: String) -> AccessibilityNode? {
    host.latestSemanticSnapshot?.accessibilityNodes.first {
      $0.role == role && $0.label == label && !$0.hidden
    }
  }

  /// The runtime's focused List row is presented on the row's selection
  /// button and nowhere else; the row's review list item is never focused.
  func expectListRowFocus(
    selectionLabel: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let selection = try #require(
      node(role: .button, label: selectionLabel), sourceLocation: sourceLocation)
    let overlay = overlay
    let focused = overlay.mappings.filter(\.isFocused).map(\.id)
    #expect(
      !focused.contains { $0.hasSuffix("/AccessibilityListItem") },
      sourceLocation: sourceLocation)
    #expect(focused.count <= 1, sourceLocation: sourceLocation)
    #expect(
      overlay.requestedNativeFocusID == selection.identity.path, sourceLocation: sourceLocation)
    #expect(focused == [selection.identity.path], sourceLocation: sourceLocation)
  }

  /// A Table's runtime focus is the table node itself; row selection moves
  /// inside it without focusing a row selection button.
  func expectTableFocus(sourceLocation: SourceLocation = #_sourceLocation) throws {
    let focusedIdentity = try #require(focusedIdentity, sourceLocation: sourceLocation)
    let table = try #require(
      host.latestSemanticSnapshot?.accessibilityNodes.first { $0.role == .table },
      sourceLocation: sourceLocation)
    #expect(table.identity == focusedIdentity, sourceLocation: sourceLocation)
    let overlay = overlay
    #expect(
      overlay.requestedNativeFocusID == table.identity.path, sourceLocation: sourceLocation)
    #expect(
      overlay.mappings.filter(\.isFocused).map(\.id) == [table.identity.path],
      sourceLocation: sourceLocation)
  }
}

@MainActor
private struct RuntimeFocusBuilderListApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      RuntimeFocusBuilderList()
    }
  }
}

private struct RuntimeFocusBuilderList: View {
  @State private var selected: Int? = nil

  var body: some View {
    List(selection: $selected) {
      ForEach(1..<4, id: \.self) { index in
        Text("List row \(index)").tag(index)
      }
    }
  }
}

@MainActor
private struct RuntimeFocusDataListApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      RuntimeFocusDataList()
    }
  }
}

private struct RuntimeFocusDataList: View {
  @State private var selected: String? = nil

  var body: some View {
    List(["alpha", "beta", "gamma"], id: \.self, selection: $selected) { name in
      Text("Item \(name)")
    }
  }
}

@MainActor
private struct RuntimeFocusButtonsApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      VStack(alignment: .leading, spacing: 0) {
        Button("One") {}
        Button("Two") {}
      }
    }
  }
}

@MainActor
private struct RuntimeFocusTableApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      RuntimeFocusTable()
    }
  }
}

private struct RuntimeFocusTable: View {
  @State private var selection: Int? = 0

  var body: some View {
    Table(selection: $selection, columns: [.init("Value", width: 12)]) {
      ForEach(0..<3, id: \.self) { row in
        TableRow { Text("Row \(row)") }.tag(row)
      }
    }
  }
}

extension RasterSurface {
  fileprivate var renderedText: String {
    lines.joined(separator: "\n")
  }
}
