import Foundation

/// What hides the elements someone chose to hide on a site.
///
/// Selectors are stored, and could say anything, so they are never made into CSS
/// or script text here. They go to the page as data — the `element-hiding` page
/// script's `moteConfig`, or `callAsyncJavaScript` arguments — and the page
/// builds one rule per selector through the CSSOM, which takes exactly one rule
/// or refuses it (see `Scripts/src/lib/element-hiding.ts`).
public enum ElementHidingStyle {
    /// The id of the `<style>` element holding the hiding rules.
    public static let styleID = "mote-hidden-elements"

    /// The selectors to hide, as the page scripts are given them.
    public struct Config: Encodable, Equatable, Sendable {
        public let selectors: [String]
    }

    /// `selectors` without `spared` (for previewing one hidden element), blank
    /// selectors and repeats, in their order.
    public static func config(selectors: [String], sparing spared: String? = nil) -> Config {
        var seen = Set<String>()
        let kept = selectors.filter { selector in
            selector != spared && !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert(selector).inserted
        }
        return Config(selectors: kept)
    }
}
