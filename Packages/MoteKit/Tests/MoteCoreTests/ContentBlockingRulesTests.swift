import Foundation
import Testing

@testable import MoteCore

@Suite("ContentBlockingRules")
struct ContentBlockingRulesTests {
    @Test("The filter matches the domain and its subdomains, and nothing that merely ends like it")
    func urlFilter() throws {
        let filter = try Regex(ContentBlockingRules.urlFilter(for: "doubleclick.net"))
        #expect("https://doubleclick.net/ad".contains(filter))
        #expect("https://stats.g.doubleclick.net/x".contains(filter))
        #expect(!"https://notdoubleclick.net/x".contains(filter))
        #expect(!"https://doubleclickxnet.com/x".contains(filter))
    }

    @Test("One third-party block rule per domain, plus the cosmetic rule")
    func json() throws {
        let data = Data(try ContentBlockingRules.json().utf8)
        let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: [String: Any]]])
        #expect(rules.count == ContentBlockingRules.blockedDomains.count + 1)

        let blocks = rules.filter { $0["action"]?["type"] as? String == "block" }
        #expect(blocks.count == ContentBlockingRules.blockedDomains.count)
        #expect(blocks.allSatisfy { ($0["trigger"]?["load-type"] as? [String]) == ["third-party"] })

        let cosmetic = try #require(rules.last)
        #expect(cosmetic["action"]?["type"] as? String == "css-display-none")
    }

    @Test("Domains are unique")
    func uniqueDomains() {
        #expect(Set(ContentBlockingRules.blockedDomains).count == ContentBlockingRules.blockedDomains.count)
    }
}
