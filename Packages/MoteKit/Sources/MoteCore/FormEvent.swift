import CoreGraphics

/// What the forms script in a page reports (see Scripts/src/forms.ts).
public enum FormEvent: Equatable, Sendable {
    /// A sign-in form was sent with these credentials.
    case sent(user: String, password: String)
    /// The sign-in fields went away without a new page.
    case settled
    /// Focus moved. `typing` when it is in something editable; `field` is the
    /// focused sign-in field's frame in CSS pixels, if it is one.
    case focus(typing: Bool, field: CGRect?)
    /// The page's own word on full screen.
    case fullscreen(Bool)

    /// Reads a message body; nil for anything unknown.
    public init?(_ body: Any) {
        guard let body = body as? [String: Any], let kind = body["kind"] as? String else { return nil }
        switch kind {
        case "submit":
            self = .sent(user: body["user"] as? String ?? "", password: body["password"] as? String ?? "")
        case "settled":
            self = .settled
        case "focus":
            let rect = body["rect"] as? [String: Double]
            let field = rect.flatMap { rect -> CGRect? in
                guard let x = rect["x"], let y = rect["y"], let w = rect["w"], let h = rect["h"] else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
            self = .focus(typing: body["typing"] as? Bool ?? false, field: field)
        case "fullscreen":
            self = .fullscreen(body["on"] as? Bool ?? false)
        default:
            return nil
        }
    }
}
