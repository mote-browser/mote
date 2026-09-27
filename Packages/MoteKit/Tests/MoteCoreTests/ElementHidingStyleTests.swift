import Foundation
import Testing

@testable import MoteCore

@Suite("ElementHidingStyle")
struct ElementHidingStyleTests {
    @Test("Keeps each selector, in order, once")
    func keepsSelectors() {
        #expect(ElementHidingStyle.config(selectors: ["#a", ".b", "#a"]).selectors == ["#a", ".b"])
        #expect(ElementHidingStyle.config(selectors: []).selectors.isEmpty)
    }

    @Test("Leaves out the spared selector and blank ones")
    func spares() {
        let config = ElementHidingStyle.config(selectors: ["#a", " ", "", ".b"], sparing: "#a")
        #expect(config.selectors == [".b"])
    }

    @Test(
        "A selector is data: it is encoded as a JSON string, exactly as stored",
        arguments: [
            "#none {} body { display: none !important; } #x",
            "`; window.escaped = 'yes'; `",
            "${window.escaped = 'yes'}",
            "\\\"</script><script>window.escaped = 'yes'</script>",
            "#a\u{2028}#b\u{2029}",
        ])
    func encodesAsData(selector: String) throws {
        let config = ElementHidingStyle.config(selectors: [selector])
        let json = try JSONEncoder().encode(config)

        let decoded = try JSONSerialization.jsonObject(with: json) as? [String: [String]]
        #expect(decoded == ["selectors": [selector]])
    }

    @Test("Names the stylesheet the page scripts share")
    func styleID() {
        #expect(ElementHidingStyle.styleID == "mote-hidden-elements")
    }
}
