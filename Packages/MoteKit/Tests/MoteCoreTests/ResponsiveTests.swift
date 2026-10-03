import Foundation
import Testing

@testable import MoteCore

@Suite("Responsive workspaces")
struct ResponsiveTests {
    @Test("Profiles preserve CSS dimensions and rotate without changing identity")
    func rotate() throws {
        let phone = try ResponsiveViewport(name: "Phone", width: 390, height: 844)
        #expect(phone.rotated.width == 844)
        #expect(phone.rotated.height == 390)
        #expect(phone.rotated.id == phone.id)
        #expect(phone.rotated.rotated == phone)
    }

    @Test("Dimensions, labels and user agents are validated at the boundary")
    func validation() throws {
        #expect(throws: ResponsiveError.self) { try ResponsiveViewport(name: " ", width: 390, height: 844) }
        #expect(throws: ResponsiveError.self) { try ResponsiveViewport(name: "Phone", width: 0, height: 844) }
        #expect(throws: ResponsiveError.self) { try ResponsiveViewport(name: "Phone", width: 390, height: 9000) }
        #expect(throws: ResponsiveError.self) {
            try ResponsiveViewport(name: "Phone", width: 390, height: 844, userAgent: "agent\r\nheader")
        }
        let profile = try ResponsiveViewport(name: " Phone ", width: 390, height: 844, userAgent: " ")
        #expect(profile.name == "Phone")
        #expect(profile.userAgent == nil)
    }

    @Test("Saved views round-trip, preserving order and user agent")
    func saved() throws {
        let phone = try ResponsiveViewport(name: "Phone", width: 390, height: 844, userAgent: "Test agent")
        let desktop = try ResponsiveViewport(name: "Desktop", width: 1440, height: 900)
        let layout = try ResponsiveLayout(name: "Daily", viewports: [desktop, phone])
        #expect(try JSONDecoder().decode(ResponsiveLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }

    @Test("Empty, duplicate and oversized workspaces cannot be loaded")
    func limits() throws {
        let phone = try ResponsiveViewport(name: "Phone", width: 390, height: 844)
        #expect(throws: ResponsiveError.self) { try ResponsiveLayout(name: "Daily", viewports: []) }
        #expect(throws: ResponsiveError.self) { try ResponsiveLayout(name: "Daily", viewports: [phone, phone]) }
        let tooMany = try (0...ResponsiveLayout.maximumViews).map { try ResponsiveViewport(name: "\($0)", width: 390, height: 844) }
        #expect(throws: ResponsiveError.self) { try ResponsiveLayout(name: "Daily", viewports: tooMany) }
        let data = try JSONEncoder().encode(phone)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["width"] = -1
        #expect(throws: ResponsiveError.self) {
            try JSONDecoder().decode(ResponsiveViewport.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }

    @Test("Built-in profiles are valid and do not claim device emulation")
    func presets() throws {
        #expect(ResponsiveViewport.presets.map(\.width) == [390, 768, 1440])
        #expect(ResponsiveViewport.presets.allSatisfy { $0.userAgent == nil })
        _ = try ResponsiveLayout(name: "Default", viewports: ResponsiveViewport.presets)
    }
}
