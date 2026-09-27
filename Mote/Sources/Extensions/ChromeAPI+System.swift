import AVFoundation
import AppKit
import IOKit.pwr_mgt
import MoteCore
import NaturalLanguage
import UserNotifications
import WebKit

// The Mac, as extensions ask about it: fonts, languages, notifications,
// speech, idleness, power and hardware; and what Mote doesn't have.

@available(macOS 15.4, *)
extension ChromeAPI {
    /// Fonts can be listed, not changed.
    static func fontSettings(_ call: ChromeCall) async throws -> Any? {
        let fixed = "not_controllable"
        switch call.method {
        case "getFontList": return NSFontManager.shared.availableFontFamilies.map { ["fontId": $0, "displayName": $0] }
        case "getFont": return ["fontId": "", "levelOfControl": fixed]
        case "getDefaultFontSize": return ["pixelSize": 16, "levelOfControl": fixed]
        case "getDefaultFixedFontSize": return ["pixelSize": 13, "levelOfControl": fixed]
        case "getMinimumFontSize": return ["pixelSize": 0, "levelOfControl": fixed]
        case let method where method.hasPrefix("set") || method.hasPrefix("clear"): return nil
        default: throw unavailable(call)
        }
    }

    static func i18n(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "detectLanguage" else { throw unavailable(call) }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(call.first as? String ?? "")
        let guesses = recognizer.languageHypotheses(withMaximum: 3)
        return [
            "isReliable": (guesses.values.max() ?? 0) > 0.6,
            "languages": guesses.sorted { $0.value > $1.value }.map { ["language": $0.key.rawValue, "percentage": Int($0.value * 100)] },
        ]
    }

    // MARK: - notifications

    static func notifications(_ call: ChromeCall) async throws -> Any? {
        let center = UNUserNotificationCenter.current()
        let name = call.context.webExtension.displayName ?? ""
        switch call.method {
        case "create":
            // create(id, options) or create(options).
            let given = call.first as? String
            let options = (given == nil ? call.first : call.arg(1)) as? [String: Any] ?? [:]
            let key = given ?? UUID().uuidString
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = options["title"] as? String ?? name
            content.body = options["message"] as? String ?? ""
            content.subtitle = name
            try? await center.add(UNNotificationRequest(identifier: "\(call.id).\(key)", content: content, trigger: nil))
            return key
        case "clear":
            if let key = call.first as? String { center.removeDeliveredNotifications(withIdentifiers: ["\(call.id).\(key)"]) }
            return true
        case "getAll": return [String: Any]()
        case "getPermissionLevel": return "granted"
        case "update": return false
        default: throw unavailable(call)
        }
    }

    // MARK: - tts

    static let speaker = AVSpeechSynthesizer()

    static func tts(_ call: ChromeCall) async throws -> Any? {
        switch call.method {
        case "speak":
            let options = call.arg(1) as? [String: Any] ?? [:]
            if options["enqueue"] as? Bool != true { speaker.stopSpeaking(at: .immediate) }
            speaker.speak(utterance(call.first as? String ?? "", options: options))
        case "stop": speaker.stopSpeaking(at: .immediate)
        case "pause": speaker.pauseSpeaking(at: .immediate)
        case "resume": speaker.continueSpeaking()
        case "isSpeaking": return speaker.isSpeaking
        case "getVoices":
            return AVSpeechSynthesisVoice.speechVoices().map {
                ["voiceName": $0.name, "lang": $0.language, "remote": false, "eventTypes": ["start", "end"]] as [String: Any]
            }
        default: throw unavailable(call)
        }
        return nil
    }

    /// Chrome's rate and pitch are multipliers around 1.
    private static func utterance(_ text: String, options: [String: Any]) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        if let name = options["voiceName"] as? String, let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == name }) {
            utterance.voice = voice
        } else if let language = options["lang"] as? String {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        if let rate = options["rate"] as? Double {
            utterance.rate = ChromeAPIRules.speechRate(
                rate, standard: AVSpeechUtteranceDefaultSpeechRate, lowest: AVSpeechUtteranceMinimumSpeechRate,
                highest: AVSpeechUtteranceMaximumSpeechRate)
        }
        if let pitch = options["pitch"] as? Double { utterance.pitchMultiplier = min(max(Float(pitch), 0.5), 2) }
        if let volume = options["volume"] as? Double { utterance.volume = min(max(Float(volume), 0), 1) }
        return utterance
    }

    // MARK: - idle and power

    static func idle(_ call: ChromeCall) async throws -> Any? {
        switch call.method {
        case "queryState":
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            if session?["CGSSessionScreenIsLocked"] as? Bool == true { return "locked" }
            let quiet = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            return quiet >= (call.first as? Double ?? 60) ? "idle" : "active"
        case "getAutoLockDelay":
            return 0
        default:
            throw unavailable(call)
        }
    }

    private static let powerReason = "An extension in Mote" as CFString

    static func power(_ call: ChromeCall) async throws -> Any? {
        let id = call.id
        switch call.method {
        case "requestKeepAwake":
            ExtensionShims.awake.removeValue(forKey: id).map { _ = IOPMAssertionRelease($0) }
            let kind =
                (call.first as? String) == "display"
                ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
            var assertion: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(kind as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), powerReason, &assertion)
                == kIOReturnSuccess
            {
                ExtensionShims.awake[id] = assertion
            }
        case "releaseKeepAwake":
            ExtensionShims.awake.removeValue(forKey: id).map { _ = IOPMAssertionRelease($0) }
        case "reportActivity":
            var assertion: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity(powerReason, kIOPMUserActiveLocal, &assertion)
        default:
            throw unavailable(call)
        }
        return nil
    }

    // MARK: - system

    static func system(_ call: ChromeCall) async throws -> Any? {
        let memory = Double(ProcessInfo.processInfo.physicalMemory)
        switch call.method {
        case "cpu.getInfo":
            return [
                "numOfProcessors": ProcessInfo.processInfo.processorCount, "archName": "arm64", "modelName": "Apple silicon",
                "features": [], "processors": [], "temperatures": [],
            ]
        case "memory.getInfo":
            return ["capacity": memory, "availableCapacity": memory / 2]
        case "storage.getInfo":
            return []
        case "display.getInfo":
            return NSScreen.screens.enumerated().map { index, screen in
                let whole = screen.frame, usable = screen.visibleFrame
                let dpi = 96 * screen.backingScaleFactor
                return [
                    "id": String(index), "name": screen.localizedName, "isPrimary": index == 0, "isInternal": index == 0, "isEnabled": true,
                    "dpiX": dpi, "dpiY": dpi, "rotation": 0, "bounds": box(whole), "workArea": box(usable),
                ] as [String: Any]
            }
        default:
            throw unavailable(call)
        }
    }

    private static func box(_ rect: CGRect) -> [String: CGFloat] {
        ["left": rect.minX, "top": rect.minY, "width": rect.width, "height": rect.height]
    }

    /// Mote has no tab groups.
    static func tabGroups(_ call: ChromeCall) async throws -> Any? {
        guard call.method == "query" else { throw Refusal("Mote has no tab groups") }
        return []
    }

    // MARK: - identity

    static func identity(_ call: ChromeCall) async throws -> Any? {
        switch call.method {
        case "launchWebAuthFlow":
            guard let url = (call.option("url") as String?).flatMap(URL.init(string:)) else { throw Refusal("No authorization url") }
            return try await ExtensionAuth.run(url, extension: call.id, browser: call.browser).absoluteString
        case "getProfileUserInfo":
            return ["email": "", "id": ""]
        case "removeCachedAuthToken", "clearAllCachedAuthTokens":
            return nil
        case "getAuthToken":
            throw Refusal("getAuthToken needs a Google account signed into Chrome; this extension would need launchWebAuthFlow instead")
        default:
            throw unavailable(call)
        }
    }
}
