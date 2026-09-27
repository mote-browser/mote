/// Middle-button autoscroll, implemented in the page, which knows the element
/// under the pointer and its scroll container.
enum AutoScroll {
    /// Backs Settings › General › Scroll with the middle button.
    @MainActor static var on = false

    /// Disables the script in pages that already loaded it.
    static let off = "window.__moteAutoScrollOff = true;"

    /// See Scripts/src/autoscroll.ts.
    static let script = InjectedScript.source("autoscroll")
}
