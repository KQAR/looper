import Foundation
import Observation

extension Bundle {
    static var localized: Bundle {
        let code: String
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: saved),
           language != .system
        {
            code = language.rawValue
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            code = preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let b = Bundle(path: path)
        else {
            return .main
        }
        return b
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    func displayName(bundle: Bundle) -> String {
        switch self {
        case .system: String(localized: "settings.language.system", bundle: bundle)
        case .en: "English"
        case .zhHans: "简体中文"
        }
    }
}

@Observable
@MainActor
final class AppLanguageManager {
    static let shared = AppLanguageManager()

    var selected: AppLanguage {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: "appLanguage")
            _cachedBundle = nil
        }
    }

    var locale: Locale {
        switch selected {
        case .system: Locale.current
        case .en: Locale(identifier: "en")
        case .zhHans: Locale(identifier: "zh-Hans")
        }
    }

    var bundle: Bundle {
        if let cached = _cachedBundle { return cached }
        let resolved = resolveBundle()
        _cachedBundle = resolved
        return resolved
    }

    @ObservationIgnored
    private var _cachedBundle: Bundle?

    private init() {
        selected = UserDefaults.standard.string(forKey: "appLanguage")
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    private func resolveBundle() -> Bundle {
        let code: String
        switch selected {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            code = preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        case .en:
            code = "en"
        case .zhHans:
            code = "zh-Hans"
        }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let b = Bundle(path: path)
        else {
            return .main
        }
        return b
    }
}
