import CoreGraphics
@_spi(Runners) import SwiftTUIRuntime
import SwiftUI

struct AccessibilityNodeMapping: Equatable {
  enum Trait: Hashable {
    case button
    case header
    case image
    case link
  }

  enum ControlKind: Equatable {
    case action
    case adjustable
    case group
    case image
    case link
    case staticText
    case textInput
  }

  let id: String
  let identity: Identity
  let parentIdentity: Identity?
  let frame: CGRect
  let role: AccessibilityRole
  let roleDescription: String
  let label: String?
  let hint: String?
  let traits: Set<Trait>
  let controlKind: ControlKind
  let isFocused: Bool
  let liveRegion: AccessibilityPoliteness?
  let isEnabled: Bool

  var swiftUITraits: SwiftUI.AccessibilityTraits {
    var traits: SwiftUI.AccessibilityTraits = []
    if self.traits.contains(.button) {
      _ = traits.insert(.isButton)
    }
    if self.traits.contains(.header) {
      _ = traits.insert(.isHeader)
    }
    if self.traits.contains(.image) {
      _ = traits.insert(.isImage)
    }
    if self.traits.contains(.link) {
      _ = traits.insert(.isLink)
    }
    return traits
  }

  /// The same element under another overlay identifier.
  func withID(_ id: String) -> Self {
    Self(
      id: id,
      identity: identity,
      parentIdentity: parentIdentity,
      frame: frame,
      role: role,
      roleDescription: roleDescription,
      label: label,
      hint: hint,
      traits: traits,
      controlKind: controlKind,
      isFocused: isFocused,
      liveRegion: liveRegion,
      isEnabled: isEnabled
    )
  }
}

enum AccessibilityNodeMapper {
  static func mappings(
    for snapshot: SemanticSnapshot?,
    focusedIdentity: Identity?,
    cellSize: CGSize
  ) -> [AccessibilityNodeMapping] {
    guard let snapshot else {
      return []
    }

    let mapped = snapshot.accessibilityNodes.compactMap { node in
      mapping(
        for: node,
        focusedIdentity: focusedIdentity,
        cellSize: cellSize
      ).map { (node: node, mapping: $0) }
    }
    return withDistinctIDs(mapped)
  }

  /// Gives every overlay element its own identifier, derived from the element
  /// itself, so it stays the same while its siblings enter and leave the
  /// snapshot. SwiftUI's `ForEach` and `accessibilityFocused(_:equals:)` need
  /// one element per value and a stable value per element, but reported
  /// identities are occurrence-free, so duplicate siblings share `identity.path`.
  ///
  /// An element whose runtime focus identity keeps a duplicate occurrence
  /// (`ID["Same"#1]`) is a later duplicate or lies inside one, and that
  /// identity's path names it. Every other element is named by its reported
  /// path, so unique elements and the first of duplicates keep it. Elements the
  /// runtime does not tell apart (static text, a duplicate row's selector) can
  /// still share a name: the first in snapshot order keeps it, and a later one
  /// takes its runtime focus identity's path, or else the name with an
  /// occurrence ordinal. Every reported path and every element's own name is
  /// reserved first, so a fallback never takes another element's identifier.
  private static func withDistinctIDs(
    _ mapped: [(node: AccessibilityNode, mapping: AccessibilityNodeMapping)]
  ) -> [AccessibilityNodeMapping] {
    let named = mapped.map { node, mapping in
      let runtimeIdentity = node.runtimeFocusIdentity
      return runtimeIdentity != node.identity && carriesDuplicateOccurrence(runtimeIdentity)
        ? mapping.withID(runtimeIdentity.path) : mapping
    }
    let names = Set(named.map(\.id))
    guard names.count < named.count else {
      return named
    }

    var taken = names.union(mapped.map(\.mapping.id))
    var occurrences: [String: Int] = [:]
    return zip(mapped, named).map { entry, mapping in
      let occurrence = occurrences[mapping.id, default: 0]
      occurrences[mapping.id] = occurrence + 1
      guard occurrence > 0 else {
        return mapping
      }

      var id = entry.node.runtimeFocusIdentity.path
      var ordinal = occurrence
      while taken.contains(id) {
        id = "\(mapping.id)#\(ordinal)"
        ordinal += 1
      }
      taken.insert(id)
      return mapping.withID(id)
    }
  }

  /// Whether `identity` keeps a duplicate-occurrence qualifier, an explicit-ID
  /// component `ID[<id>#<n>]`. The framework qualifies only later duplicates
  /// (occurrence 0 is the unqualified form), percent-escapes an authored `#`,
  /// and strips the qualifier from reported identities; this is the component
  /// rule of its `Identity.strippingEntityOccurrences`.
  static func carriesDuplicateOccurrence(_ identity: Identity) -> Bool {
    identity.components.contains { component in
      guard component.hasPrefix("ID["), component.hasSuffix("]") else {
        return false
      }
      let interior = component.dropFirst(3).dropLast(1)
      guard let hashIndex = interior.lastIndex(of: "#") else {
        return false
      }
      let digits = interior[interior.index(after: hashIndex)...]
      return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }
  }

  static func mapping(
    for node: AccessibilityNode,
    focusedIdentity: Identity?,
    cellSize: CGSize
  ) -> AccessibilityNodeMapping? {
    guard !node.hidden, let frame = frame(for: node.rect, cellSize: cellSize) else {
      return nil
    }

    let roleMapping = roleMapping(for: node.role)
    return AccessibilityNodeMapping(
      id: node.identity.path,
      identity: node.identity,
      parentIdentity: node.parentIdentity,
      frame: frame,
      role: node.role,
      roleDescription: roleMapping.description,
      label: node.label,
      hint: node.hint,
      traits: roleMapping.traits,
      controlKind: roleMapping.controlKind,
      isFocused: node.runtimeFocusIdentity == focusedIdentity,
      liveRegion: node.liveRegion,
      isEnabled: node.isEnabled
    )
  }

  static func frame(
    for rect: CellRect,
    cellSize: CGSize
  ) -> CGRect? {
    guard
      !rect.isEmpty,
      cellSize.width > 0,
      cellSize.height > 0
    else {
      return nil
    }

    return CGRect(
      x: CGFloat(rect.origin.x) * cellSize.width,
      y: CGFloat(rect.origin.y) * cellSize.height,
      width: CGFloat(rect.size.width) * cellSize.width,
      height: CGFloat(rect.size.height) * cellSize.height
    )
  }

  private static func roleMapping(
    for role: AccessibilityRole
  ) -> (
    description: String,
    traits: Set<AccessibilityNodeMapping.Trait>,
    controlKind: AccessibilityNodeMapping.ControlKind
  ) {
    switch role {
    case .button, .disclosureGroup, .menuItem, .tab:
      (role.description, [.button], .action)
    case .checkbox, .toggle:
      (role.description, [.button], .action)
    case .link:
      (role.description, [.link], .link)
    case .heading, .columnHeader, .rowHeader:
      (role.description, [.header], .staticText)
    case .image:
      (role.description, [.image], .image)
    case .textField, .secureField, .textEditor:
      (role.description, [], .textInput)
    case .slider, .stepper, .progressBar:
      (role.description, [], .adjustable)
    case .alert, .status, .timer:
      (role.description, [], .staticText)
    case .cell, .confirmationDialog, .custom, .group, .list, .menu, .picker, .popover, .region,
      .scrollView, .scrollViewWithIndicators, .section, .separator, .sheet, .table,
      .tableRow, .tabPanel, .tabView:
      (role.description, [], .group)
    }
  }
}
