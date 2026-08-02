import CoreText
import Foundation

/// The bundled terminal fonts that ship with `SwiftUIHost`.
///
/// Core Text registers the TTF files in `Resources/` when the process first accesses them.
/// Thus, callers do not need to add the fonts to `Info.plist` (`UIAppFonts` or `ATSApplicationFontsPath`).
enum BundledFonts {
  /// The PostScript name of the regular face.
  /// After you call `registerIfNeeded()`, use this name with `NSFont(name:size:)` or `UIFont(name:size:)`.
  static let regularPostScriptName = "AnonymiceProNFP"

  /// The family name in the `name` table of the TTF files.
  /// Use this value to set `SwiftUIHostTerminalStyle.fontFamily` explicitly.
  static let familyName = "AnonymicePro Nerd Font Propo"

  /// Registers the fonts at most once and accepts calls from any thread.
  static func registerIfNeeded() {
    _ = registration
  }

  /// Returns the PostScript name for a specified emphasis combination.
  /// Embedded fonts can give inconsistent results for `NSFontManager.convert(toHaveTrait:)` and symbolic-trait derivation.
  /// Thus, this function resolves each face directly.
  static func postScriptName(forBold bold: Bool, italic: Bool) -> String {
    switch (bold, italic) {
    case (true, true):
      "AnonymiceProNFP-BoldItalic"
    case (true, false):
      "AnonymiceProNFP-Bold"
    case (false, true):
      "AnonymiceProNFP-Italic"
    case (false, false):
      regularPostScriptName
    }
  }

  /// Registers each bundled `.ttf` one time when code first accesses this property.
  /// The registration ignores all errors, including "already registered".
  private static let registration: Void = {
    let baseNames = [
      "AnonymiceProNerdFontPropo-Regular",
      "AnonymiceProNerdFontPropo-Bold",
      "AnonymiceProNerdFontPropo-Italic",
      "AnonymiceProNerdFontPropo-BoldItalic",
    ]

    for name in baseNames {
      guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
        continue
      }
      var error: Unmanaged<CFError>?
      _ = unsafe CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
      unsafe error?.release()
    }
  }()
}
