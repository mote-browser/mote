import CoreGraphics
import Foundation
import Testing

@testable import MoteCore

@Suite("Floating video")
struct FloatGeometryTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let frame = CGRect(x: 400, y: 300, width: 200, height: 100)

    @Test("A diagonal flick goes to the corner it points at")
    func diagonal() {
        #expect(FloatGeometry.corner(for: frame, in: area, toward: CGVector(dx: 1, dy: 1)) == CGPoint(x: 788, y: 688))
        #expect(FloatGeometry.corner(for: frame, in: area, toward: CGVector(dx: -1, dy: -0.8)) == CGPoint(x: 12, y: 12))
    }

    @Test("A straight flick keeps to the nearer edge the other way")
    func straight() {
        let low = CGRect(x: 400, y: 100, width: 200, height: 100)
        #expect(FloatGeometry.corner(for: low, in: area, toward: CGVector(dx: 1, dy: 0.1)) == CGPoint(x: 788, y: 12))
        let right = CGRect(x: 700, y: 300, width: 200, height: 100)
        #expect(FloatGeometry.corner(for: right, in: area, toward: CGVector(dx: 0, dy: 1)) == CGPoint(x: 788, y: 688))
    }

    @Test("Resizing keeps the proportions and the limits, and the point under the fingers")
    func resizing() {
        let bigger = FloatGeometry.resized(frame, toWidth: 400, narrowest: 260, screenWidth: 1000)
        #expect(bigger == CGRect(x: 400, y: 200, width: 400, height: 200))
        #expect(FloatGeometry.resized(frame, toWidth: 100, narrowest: 260, screenWidth: 1000).width == 260)
        #expect(FloatGeometry.resized(frame, toWidth: 2000, narrowest: 260, screenWidth: 1000).width == 850)
        let around = FloatGeometry.resized(frame, toWidth: 400, narrowest: 260, screenWidth: 1000, around: CGPoint(x: 500, y: 350))
        #expect(around == CGRect(x: 300, y: 250, width: 400, height: 200))
    }

    @Test("A glide starts at 0, ends at 1 and never overshoots")
    func glide() {
        #expect(FloatGeometry.glide(at: 0) == 0)
        #expect(FloatGeometry.glide(at: 0.7) == 1)
        let steps = stride(from: 0.0, to: 0.6, by: 0.05).map(FloatGeometry.glide)
        #expect(steps == steps.sorted())
        #expect(steps.allSatisfy { $0 <= 1 })
    }

    @Test("A remembered frame is used only if most of it is on a screen")
    func remembered() {
        #expect(FloatGeometry.remembered(frame, on: [area]) == frame)
        #expect(FloatGeometry.remembered(CGRect(x: 950, y: 0, width: 200, height: 100), on: [area]) == nil)
        #expect(FloatGeometry.remembered(CGRect(x: 0, y: 0, width: 50, height: 30), on: [area]) == nil)
    }

    @Test("A long swipe flicks at once, a short one on lifting, and only once")
    func flick() {
        var flick = FloatGeometry.Flick()
        flick.begin()
        let first = flick.move(by: CGVector(dx: 100, dy: 0), lifted: false)
        let over = flick.move(by: CGVector(dx: 30, dy: 0), lifted: false)
        let again = flick.move(by: CGVector(dx: 100, dy: 0), lifted: true)
        #expect(first == nil)
        #expect(over == CGVector(dx: 130, dy: 0))
        #expect(again == nil)
        let short = flick.move(by: CGVector(dx: 0, dy: 25), lifted: true)
        #expect(short == CGVector(dx: 0, dy: 25))
    }

    @Test("Video sites, their subdomains, and shops' video sections")
    func sites() {
        #expect(VideoSites.contains(URL(string: "https://www.youtube.com/watch?v=x")))
        #expect(VideoSites.contains(URL(string: "https://www.amazon.fr/gp/video/detail")))
        #expect(!VideoSites.contains(URL(string: "https://www.amazon.fr/dp/123")))
        #expect(!VideoSites.contains(URL(string: "https://notyoutube.com")))
        #expect(!VideoSites.contains(nil))
    }
}
