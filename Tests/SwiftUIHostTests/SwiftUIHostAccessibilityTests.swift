import CoreGraphics
import Foundation
@_spi(Runners) import SwiftTUIRuntime
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

  // STUI-1256: reported identities are occurrence-free, so duplicate siblings share
  // `identity.path`. SwiftUI's `ForEach` and `accessibilityFocused(_:equals:)` need one
  // element per value, so every overlay element gets a distinct id: the first keeps the
  // path and a later one takes its runtime focus identity, which keeps the occurrence. The
  // focus request then names the focused element alone (w3ca22, w3ca23).
  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func duplicate_sibling_overlay_ids_keep_the_occurrence() async throws {
    let harness = try RuntimeFocusHarness(app: HuntDuplicateButtonsApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Same")
    let nodes = try #require(harness.host.latestSemanticSnapshot?.accessibilityNodes)
    let buttons = nodes.filter { $0.role == .button && $0.label == "Same" }
    try #require(buttons.count == 2)
    #expect(buttons[0].identity == buttons[1].identity)
    #expect(buttons[1].runtimeFocusIdentity.path.hasSuffix(##"ID["Same"#1]"##))
    #expect(harness.focusedIdentity == buttons[0].runtimeFocusIdentity)

    let overlay = harness.overlay
    let ids = overlay.mappings.map(\.id)
    #expect(Set(ids).count == ids.count, "\(ids)")
    let buttonIDs = overlay.mappings.filter { $0.role == .button && $0.label == "Same" }.map(\.id)
    #expect(buttonIDs == [buttons[0].identity.path, buttons[1].runtimeFocusIdentity.path])
    let duplicatedPath = buttons[0].identity.path
    #expect(
      overlay.mappings.filter { $0.identity.path != duplicatedPath }.allSatisfy {
        $0.id == $0.identity.path
      })
    let requested = try #require(overlay.requestedNativeFocusID)
    #expect(ids.filter { $0 == requested } == [buttons[0].identity.path])
  }

  // STUI-1256: duplicate List rows report one selection-button path, while their action
  // identities are distinct row identities (w3ca24).
  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func duplicate_list_row_selectors_get_distinct_overlay_ids() async throws {
    let harness = try RuntimeFocusHarness(app: DuplicateRowsListApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Same")
    await harness.sendKey(.arrowDown) { $0.focusedIdentity != $1.focusedIdentity }
    let overlay = harness.overlay
    let ids = overlay.mappings.map(\.id)
    #expect(Set(ids).count == ids.count, "\(ids)")
    #expect(overlay.mappings.filter(\.isFocused).map(\.label) == ["Select row 2"])
    let requested = try #require(overlay.requestedNativeFocusID)
    #expect(overlay.mappings.filter { $0.id == requested }.map(\.label) == ["Select row 2"])
  }

  // STUI-1256: the overlay presents each node's enabled state. A disabled control and a
  // disabled List row's selection button are presented disabled, as the browser host does
  // (w3ca27).
  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func overlay_presents_disabled_controls_disabled() async throws {
    let harness = try RuntimeFocusHarness(app: DisabledControlsApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Row 3")
    let nodes = try #require(harness.host.latestSemanticSnapshot?.accessibilityNodes)
    let mappings = harness.overlay.mappings
    func isEnabled(_ label: String) -> Bool? {
      mappings.first { $0.label == label }?.isEnabled
    }
    #expect(isEnabled("On") == true)
    #expect(isEnabled("Off") == false)
    #expect(isEnabled("Select row 1") == true)
    #expect(isEnabled("Select row 2") == false)
    #expect(isEnabled("Select row 3") == true)
    for mapping in mappings {
      let node = nodes.first {
        $0.identity == mapping.identity && $0.role == mapping.role && $0.label == mapping.label
      }
      #expect(mapping.isEnabled == node?.isEnabled, "\(mapping.id)")
    }
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
private struct DuplicateRowsListApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      DuplicateRowsList()
    }
  }
}

private struct DuplicateRowsList: View {
  @State private var selected: String? = nil

  var body: some View {
    List(["Same", "Same"], id: \.self, selection: $selected) { name in
      Text(name)
    }
  }
}

@MainActor
private struct DisabledControlsApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      DisabledControls()
    }
  }
}

private struct DisabledControls: View {
  @State private var selected: Int? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("On") {}
      Button("Off") {}.disabled(true)
      List(selection: $selected) {
        ForEach(1..<4, id: \.self) { index in
          Text("Row \(index)").tag(index).disabled(index == 2)
        }
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

// Wave-2 regression hunt, part CA (STUI-1165): neighbours of the STUI-1211
// runtime-focus adoption. Cases w2ca016-w2ca018.
@MainActor
@Suite(.serialized)
struct Wave2RegressionHuntAccessibilityTests {
  // The second of two duplicate siblings is the focused element, so the
  // overlay's requested native focus value must name it alone (repaired by STUI-1256).
  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w2ca016_duplicate_sibling_focus_names_one_native_element() async throws {
    let harness = try RuntimeFocusHarness(app: HuntDuplicateButtonsApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Same")
    let first = try #require(harness.focusedIdentity)
    await harness.sendKey(.tab) { $0.focusedIdentity != $1.focusedIdentity }
    let second = try #require(harness.focusedIdentity)
    #expect(second != first)

    let overlay = harness.overlay
    #expect(overlay.mappings.filter(\.isFocused).count == 1)
    let requested = try #require(overlay.requestedNativeFocusID)
    let carriers = overlay.mappings.filter { $0.id == requested }.count
    #expect(carriers == 1, "\(carriers) overlay elements carry the requested focus id")
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w2ca017_sectioned_list_row_focus_crosses_sections() async throws {
    let harness = try RuntimeFocusHarness(app: HuntSectionedListApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Row 1")
    var seen = [try huntExpectSelectionButtonFocus(harness)]
    for _ in 0..<2 {
      await harness.sendKey(.arrowDown) { $0.focusedIdentity != $1.focusedIdentity }
      seen.append(try huntExpectSelectionButtonFocus(harness))
    }
    #expect(Set(seen).count == 3, "\(seen)")
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w2ca018_multi_selection_list_row_focus() async throws {
    let harness = try RuntimeFocusHarness(app: HuntMultiSelectionListApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Pick 1")
    let first = try huntExpectSelectionButtonFocus(harness)
    await harness.sendKey(.arrowDown) { $0.focusedIdentity != $1.focusedIdentity }
    let second = try huntExpectSelectionButtonFocus(harness)
    #expect(first != second)
  }
}

/// Exactly one mapping is focused; it is a row selection button and the
/// overlay requests native focus on it. Returns its id.
@MainActor
private func huntExpectSelectionButtonFocus(
  _ harness: RuntimeFocusHarness,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> String {
  let overlay = harness.overlay
  let focused = overlay.mappings.filter(\.isFocused)
  #expect(focused.count == 1, sourceLocation: sourceLocation)
  let mapping = try #require(focused.first, sourceLocation: sourceLocation)
  #expect(mapping.role == .button, sourceLocation: sourceLocation)
  #expect(mapping.label?.hasPrefix("Select row") == true, sourceLocation: sourceLocation)
  #expect(overlay.requestedNativeFocusID == mapping.id, sourceLocation: sourceLocation)
  return mapping.id
}

@MainActor
private struct HuntDuplicateButtonsApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["Same", "Same"], id: \.self) { title in
          Button(title) {}
        }
      }
    }
  }
}

@MainActor
private struct HuntSectionedListApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      HuntSectionedList()
    }
  }
}

private struct HuntSectionedList: View {
  @State private var selected: Int? = nil

  var body: some View {
    List(selection: $selected) {
      Section("First") {
        ForEach(1..<3, id: \.self) { index in
          Text("Row \(index)").tag(index)
        }
      }
      Section("Second") {
        ForEach(3..<5, id: \.self) { index in
          Text("Row \(index)").tag(index)
        }
      }
    }
  }
}

@MainActor
private struct HuntMultiSelectionListApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      HuntMultiSelectionList()
    }
  }
}

private struct HuntMultiSelectionList: View {
  @State private var selected: Set<Int> = []

  var body: some View {
    List(selection: $selected) {
      ForEach(1..<4, id: \.self) { index in
        Text("Pick \(index)").tag(index)
      }
    }
  }
}

// Wave-3 regression hunt, part CA (STUI-1167): neighbours of the STUI-1256 overlay ids
// and the disabled-state projection (3cdc2fd). Cases w3ca020-w3ca024; the hypotheses
// precede these tests in the hunt's evidence directory.
@MainActor
@Suite(.serialized)
struct Wave3RegressionHuntAccessibilityTests {
  // The second of two duplicates keeps its runtime identity when the first leaves the
  // snapshot; SwiftUI's ForEach and AccessibilityFocusState identify it by its overlay id.
  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w3ca020_overlay_id_survives_an_earlier_duplicate_leaving() async throws {
    let harness = try RuntimeFocusHarness(app: W3HideFirstDuplicateApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Same")
    let toggle = try #require(harness.node(role: .button, label: "Toggle"))
    #expect(harness.focusedIdentity == toggle.runtimeFocusIdentity)
    let before = try #require(w3SameButtons(harness).last)
    try #require(w3SameButtons(harness).count == 2)
    #expect(before.runtimeFocusIdentity.path.hasSuffix(##"ID["Same"#1]"##))
    let idBefore = try #require(w3MappingID(harness, for: before))

    await harness.sendKey(.return) { _, _ in w3SameButtons(harness).count == 1 }
    let after = try #require(w3SameButtons(harness).first)
    // The same runtime element: its identity and frame are unchanged.
    #expect(after.runtimeFocusIdentity == before.runtimeFocusIdentity)
    #expect(after.rect == before.rect)
    let idAfter = try #require(w3MappingID(harness, for: after))
    w3HuntKnown(
      "NEW-2: the remaining duplicate's overlay id changes from ...ID[\"Same\"#1] to ...ID[\"Same\"] (the hidden button's former id) although its runtime identity is unchanged; the first mapped duplicate keeps the reported path; contract: SwiftUI ForEach stable identity; adjacent STUI-1256"
    ) {
      #expect(idAfter == idBefore, "overlay id \(idBefore) became \(idAfter)")
    }
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w3ca021_third_of_three_duplicates_is_requested_alone() async throws {
    let harness = try RuntimeFocusHarness(app: W3ThreeDuplicatesApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Same")
    for _ in 0..<2 {
      await harness.sendKey(.tab) { $0.focusedIdentity != $1.focusedIdentity }
    }
    let buttons = w3SameButtons(harness)
    try #require(buttons.count == 3)
    let third = buttons[2]
    #expect(third.runtimeFocusIdentity.path.hasSuffix(##"ID["Same"#2]"##))
    #expect(harness.focusedIdentity == third.runtimeFocusIdentity)
    let overlay = harness.overlay
    let ids = overlay.mappings.map(\.id)
    #expect(Set(ids).count == ids.count, "\(ids)")
    let requested = try #require(overlay.requestedNativeFocusID)
    #expect(ids.filter { $0 == requested } == [third.runtimeFocusIdentity.path])
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w3ca022_buttons_inside_duplicate_rows_get_distinct_ids() async throws {
    let harness = try RuntimeFocusHarness(app: W3DuplicateRowsWithButtonsApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Go")
    await harness.sendKey(.tab) { $0.focusedIdentity != $1.focusedIdentity }
    let nodes = try #require(harness.host.latestSemanticSnapshot?.accessibilityNodes)
    let goButtons = nodes.filter { $0.role == .button && $0.label == "Go" }
    try #require(goButtons.count == 2)
    #expect(goButtons[0].identity == goButtons[1].identity)
    #expect(harness.focusedIdentity == goButtons[1].runtimeFocusIdentity)
    let overlay = harness.overlay
    let ids = overlay.mappings.map(\.id)
    #expect(Set(ids).count == ids.count, "\(ids)")
    let requested = try #require(overlay.requestedNativeFocusID)
    let carriers = overlay.mappings.filter { $0.id == requested }
    #expect(carriers.count == 1, "\(carriers.map(\.id))")
    let expectedFrame = AccessibilityNodeMapper.frame(
      for: goButtons[1].rect, cellSize: CGSize(width: 8, height: 16))
    #expect(carriers.first?.label == "Go")
    #expect(carriers.first?.frame == expectedFrame)
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w3ca023_disabled_toggle_field_and_ancestor_are_presented_disabled() async throws {
    let harness = try RuntimeFocusHarness(app: W3DisabledKindsApp())
    defer { harness.stop() }

    await harness.waitForFocus(marker: "Live")
    let nodes = try #require(harness.host.latestSemanticSnapshot?.accessibilityNodes)
    let mappings = harness.overlay.mappings
    let toggle = try #require(mappings.first { $0.role == .toggle || $0.role == .checkbox })
    let field = try #require(mappings.first { $0.role == .textField })
    #expect(toggle.isEnabled == false)
    #expect(field.isEnabled == false)
    #expect(mappings.first { $0.label == "Inner" }?.isEnabled == false)
    #expect(mappings.first { $0.label == "Live" }?.isEnabled == true)
    for mapping in mappings {
      let node = nodes.first {
        $0.identity == mapping.identity && $0.role == mapping.role && $0.label == mapping.label
      }
      #expect(mapping.isEnabled == node?.isEnabled, "\(mapping.id)")
    }
  }

  @MainActor
  @Test(.timeLimit(.minutes(1)))
  func w3ca024_framework_disabled_row_selectors_reach_the_overlay() async throws {
    for (name, marker) in [("table", "row1"), ("list", "item1")] {
      let harness: RuntimeFocusHarness =
        name == "table"
        ? try RuntimeFocusHarness(app: W3DisabledTableApp())
        : try RuntimeFocusHarness(app: W3DisabledTaggedListApp())
      defer { harness.stop() }

      await harness.waitForFocus(marker: marker)
      let nodes = try #require(harness.host.latestSemanticSnapshot?.accessibilityNodes)
      let mappings = harness.overlay.mappings
      func isEnabled(_ label: String) -> Bool? {
        mappings.first { $0.label == label }?.isEnabled
      }
      #expect(nodes.first { $0.label == "Select row 2" }?.isEnabled == false, "\(name) node")
      #expect(isEnabled("Select row 1") == true, "\(name)")
      #expect(isEnabled("Select row 2") == false, "\(name)")
      #expect(isEnabled("Select row 3") == true, "\(name)")
    }
  }
}

/// Preserve an unmarked reproduction while guarding only confirmed assertions.
private func w3HuntKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W3HUNT_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}

@MainActor
private func w3SameButtons(_ harness: RuntimeFocusHarness) -> [AccessibilityNode] {
  (harness.host.latestSemanticSnapshot?.accessibilityNodes ?? []).filter {
    $0.role == .button && $0.label == "Same" && !$0.hidden
  }
}

/// The overlay id of the element presenting `node`, matched by its frame.
@MainActor
private func w3MappingID(_ harness: RuntimeFocusHarness, for node: AccessibilityNode) -> String? {
  let frame = AccessibilityNodeMapper.frame(for: node.rect, cellSize: CGSize(width: 8, height: 16))
  let matches = harness.overlay.mappings.filter { $0.label == node.label && $0.frame == frame }
  return matches.count == 1 ? matches[0].id : nil
}

private struct W3Duplicate: Hashable {
  let label: String
  let index: Int
}

@MainActor
private struct W3HideFirstDuplicateApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      W3HideFirstDuplicate()
    }
  }
}

private struct W3HideFirstDuplicate: View {
  @State private var hideFirst = false
  private let items = [W3Duplicate(label: "Same", index: 0), W3Duplicate(label: "Same", index: 1)]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle") { hideFirst.toggle() }
      ForEach(items, id: \.label) { item in
        Button(item.label) {}
          .accessibilityHidden(hideFirst && item.index == 0)
      }
    }
  }
}

@MainActor
private struct W3ThreeDuplicatesApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["Same", "Same", "Same"], id: \.self) { title in
          Button(title) {}
        }
      }
    }
  }
}

@MainActor
private struct W3DuplicateRowsWithButtonsApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(["A", "A"], id: \.self) { title in
          HStack(spacing: 1) {
            Text(title)
            Button("Go") {}
          }
        }
      }
    }
  }
}

@MainActor
private struct W3DisabledKindsApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      W3DisabledKinds()
    }
  }
}

private struct W3DisabledKinds: View {
  @State private var isOn = false
  @State private var name = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle("Wifi", isOn: $isOn).disabled(true)
      TextField("Name", text: $name).disabled(true)
      VStack(alignment: .leading, spacing: 0) {
        Button("Inner") {}
      }
      .disabled(true)
      Button("Live") {}
    }
  }
}

@MainActor
private struct W3DisabledTableApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      W3DisabledTable()
    }
  }
}

private struct W3DisabledTable: View {
  @State private var selection: Int? = 1

  var body: some View {
    Table([1, 2, 3], id: \.self, selection: $selection, columns: [TableColumn("Name", width: 12)]) {
      row in
      Text("row\(row)").disabled(row == 2)
    }
    .tableHeaders(.hidden)
  }
}

@MainActor
private struct W3DisabledTaggedListApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      W3DisabledTaggedList()
    }
  }
}

private struct W3DisabledTaggedList: View {
  @State private var selection: Int? = nil

  var body: some View {
    List(selection: $selection) {
      ForEach(1..<4, id: \.self) { index in
        HStack(spacing: 1) {
          Text("item\(index)").tag(index).disabled(index == 2)
          Text("x")
        }
      }
    }
  }
}
