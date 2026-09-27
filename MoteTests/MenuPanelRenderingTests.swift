import AppKit
import SwiftUI
import Testing

@testable import Mote

/// Presents a menu the way the sidebar's bookmarks button does.
@MainActor
private final class Presenting: ObservableObject {
    @Published var open = false
}

private struct Anchored: View {
    @ObservedObject var presenting: Presenting
    let browser: Browser

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Rectangle().fill(Palette.wash).frame(width: 26, height: 26)
                    .menuPanel(isPresented: $presenting.open, edge: .trailing) {
                        BookmarksDropdown(browser: browser, bookmarks: browser.bookmarks)
                    }
                Spacer()
            }
            .padding(10)
        }
        .frame(width: 500, height: 400)
        .background(Palette.ground)
    }
}

extension MenuPanelOnScreenTests {
    @Suite("Rendering")
    @MainActor
    struct Rendering {
        /// The bookmarks menu opened from a button at the bottom of a window that
        /// sits on the bottom of the screen, as the sidebar's does: where a popover's
        /// arrow was pushed into its bottom corner. Returns the menu as drawn.
        private func openBookmarksMenu() async throws -> NSBitmapImageRep {
            let browser = Browser()
            let presenting = Presenting()
            let screen = try #require(NSScreen.main).visibleFrame
            let window = NSWindow(
                contentRect: NSRect(x: screen.minX + 40, y: screen.minY, width: 500, height: 400),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: Anchored(presenting: presenting, browser: browser))
            window.makeKeyAndOrderFront(nil)
            defer {
                presenting.open = false
                window.close()
            }
            try await Task.sleep(for: .milliseconds(200))

            presenting.open = true
            let menu = try await eventually {
                NSApp.windows.first { $0.isVisible && $0.className.contains("MenuPanel") }
            }
            let view = try #require(menu.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }

        /// How many pixels differ between the menu's bottom-left corner and its
        /// top-left corner turned upside down, comparing only whether each pixel
        /// is part of the menu. A plain rounded menu has alike corners; an arrow
        /// squeezed into a corner changes that corner's outline.
        private func cornerDifference(in bitmap: NSBitmapImageRep) -> (differing: Int, compared: Int) {
            let size = 28 * bitmap.pixelsWide / Int(bitmap.size.width)
            func inside(_ x: Int, _ y: Int) -> Bool { (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
            var differing = 0
            for dy in 0..<size {
                for dx in 0..<size where inside(dx, dy) != inside(dx, bitmap.pixelsHigh - 1 - dy) {
                    differing += 1
                }
            }
            return (differing, size * size)
        }

        /// The colors inside the menu's bottom-left corner, away from its outline:
        /// pixels whose neighbours two pixels away on every side are opaque too.
        private func cornerColors(in bitmap: NSBitmapImageRep) -> [NSColor] {
            let size = 28 * bitmap.pixelsWide / Int(bitmap.size.width)
            func opaque(_ x: Int, _ y: Int) -> Bool { (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.95 }
            var colors: [NSColor] = []
            for y in (bitmap.pixelsHigh - size)..<(bitmap.pixelsHigh - 2) {
                for x in 2..<size {
                    let interior = [(-2, 0), (2, 0), (0, -2), (0, 2), (-2, -2), (2, 2), (-2, 2), (2, -2)]
                        .allSatisfy { opaque(x + $0.0, y + $0.1) }
                    guard interior, let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    colors.append(color)
                }
            }
            return colors
        }

        @Test("The bookmarks menu's corner keeps its shape when it opens at the bottom of the screen")
        func bookmarksMenuCornerKeepsItsShape() async throws {
            let bitmap = try await openBookmarksMenu()
            // The drawing has the menu's real outline: its rounded corners are see-through.
            #expect((bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1)?.alphaComponent ?? 1) < 0.1)
            #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
            let (differing, compared) = cornerDifference(in: bitmap)
            // A few antialiased pixels may round differently at the two corners.
            #expect(differing < compared / 50, "\(differing) of \(compared) corner pixels differ from the opposite corner")
        }

        @Test("The bookmarks menu's corner is one surface")
        func bookmarksMenuIsOneSurface() async throws {
            let colors = cornerColors(in: try await openBookmarksMenu())
            let surface = try #require(colors.first)
            // A second surface behind the card (such as a popover's own material)
            // shows as other colors here.
            let others = colors.filter { color in
                max(
                    abs(color.redComponent - surface.redComponent),
                    abs(color.greenComponent - surface.greenComponent),
                    abs(color.blueComponent - surface.blueComponent)) > 0.02
            }
            #expect(!colors.isEmpty)
            #expect(others.isEmpty, "\(others.count) of \(colors.count) corner pixels differ from the surface")
        }
    }
}
