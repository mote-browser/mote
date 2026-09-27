import Foundation

/// The part of a host name someone could register: `news.bbc.co.uk` → `bbc.co.uk`.
public enum RegistrableDomain {
    /// - Parameter isPublicSuffix: whether a name is a public suffix (`com`,
    ///   `co.uk`…). Without one, the host is returned as it is.
    public static func of(_ host: String, isPublicSuffix: ((String) -> Bool)?) -> String {
        let name = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = name.split(separator: ".").map(String.init)
        let isIPAddress = name.contains(":") || labels.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard let isPublicSuffix, !isIPAddress, labels.count > 1, !isPublicSuffix(name) else { return name }

        for count in stride(from: labels.count - 1, through: 1, by: -1)
        where isPublicSuffix(labels.suffix(count).joined(separator: ".")) {
            return labels.suffix(count + 1).joined(separator: ".")
        }
        return name
    }
}
