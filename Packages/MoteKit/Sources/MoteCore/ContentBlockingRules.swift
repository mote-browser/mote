import Foundation

/// The ad blocker's rules, in WebKit's content blocker format.
public enum ContentBlockingRules {
    /// Ad and tracking domains, blocked only as third-party requests: a site's
    /// own requests to these domains are left alone.
    public static let blockedDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "googletagservices.com", "google-analytics.com", "googletagmanager.com",
        "adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "smartadserver.com", "sharethrough.com", "indexww.com", "bidswitch.net",
        "33across.com", "teads.tv", "moatads.com", "adroll.com",
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms",
        "mixpanel.com", "amplitude.com", "segment.com", "segment.io",
        "branch.io", "appsflyer.com", "adjust.com", "analytics.tiktok.com",
        "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
    ]

    /// Cosmetic selectors for unambiguous ad slots, kept short so legitimate
    /// content is never hidden.
    public static let adSelectors = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]",
        "[id^=\"div-gpt-ad\"]", "[id^=\"taboola-\"]", "#taboola-below-article",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication\"]",
        "iframe[src*=\"amazon-adsystem\"]",
    ]

    /// The URL filter that matches `domain` and its subdomains over http(s).
    public static func urlFilter(for domain: String) -> String {
        "^https?://([^/]+\\.)?" + domain.replacingOccurrences(of: ".", with: "\\.")
    }

    /// The rule list as JSON, ready for `WKContentRuleListStore`.
    public static func json() throws -> String {
        var rules: [[String: Any]] = blockedDomains.map { domain in
            [
                "trigger": ["url-filter": urlFilter(for: domain), "load-type": ["third-party"]],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": adSelectors.joined(separator: ", ")],
        ])
        let data = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
