import WebKit

// Pages at 120 Hz on ProMotion displays (Settings › General, off by
// default). WebKit holds page animation and scrolling near 60 fps, which
// saves a good deal of energy; with the setting off Mote never touches the
// flag, so pages get WebKit's own default.

enum FrameRate {
    /// WebKit reads the flag as a page is made. Open tabs get it after a
    /// reload, which isn't forced on them: it could lose what's typed.
    @MainActor static var fast = false {
        didSet {
            guard fast != oldValue else { return }
            if fast {
                Web.pages.allObjects.forEach { apply(to: $0.configuration.preferences) }
            } else {
                // Only what Mote changed goes back.
                changed.allObjects.forEach { set(near60: true, in: $0) }
                changed.removeAllObjects()
            }
        }
    }

    @MainActor private static let changed = NSHashTable<WKPreferences>.weakObjects()

    /// Before the page is made.
    @MainActor static func apply(to preferences: WKPreferences) {
        guard fast, flag != nil else { return }
        set(near60: false, in: preferences)
        changed.add(preferences)
    }

    /// Whether the page is held near 60 fps; nil when WebKit has no such
    /// flag. For the bench.
    static func prefersNear60(_ preferences: WKPreferences) -> Bool? {
        flag.flatMap { preferences.unpublishedFlag("_isEnabledForFeature:", $0) }
    }

    /// WebKit's `PreferPageRenderingUpdatesNear60FPSEnabled` feature, looked
    /// up once: the list runs to several hundred.
    private static let flag: NSObject? = {
        let type: AnyObject = WKPreferences.self
        let list = NSSelectorFromString("_features")
        guard type.responds(to: list), let features = type.perform(list)?.takeUnretainedValue() as? [NSObject] else { return nil }
        return features.first { $0.value(forKey: "key") as? String == "PreferPageRenderingUpdatesNear60FPSEnabled" }
    }()

    private static func set(near60 on: Bool, in preferences: WKPreferences) {
        guard let flag else { return }
        preferences.unpublished("_setEnabled:forFeature:", on, flag)
    }
}
