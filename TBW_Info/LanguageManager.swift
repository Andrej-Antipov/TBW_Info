import Foundation
import Combine

enum Language: String, CaseIterable {
    case russian = "ru"
    case english = "en"
    
    var displayName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @Published var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "SelectedLanguage")
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }
    
    private init() {
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? ["ru"]
        let currentLang = languages.first ?? "ru"
        
        if currentLang.hasPrefix("ru") {
            self.currentLanguage = .russian
        } else {
            self.currentLanguage = .english
        }
    }


    
    func localizedString(for key: String) -> String {
        let dictionary = currentLanguage == .russian ? ruDict : enDict
        return dictionary[key] ?? key
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("LanguageChanged")
}

private let ruDict: [String: String] = [
    "menu_title": "Мониторинг SSD Watch",
    "menu_select_disk": "Выбор накопителя",
    "menu_autostart": "Запускать при старте системы",
    "menu_info": "Инфо...",
    "menu_quit": "Выйти из программы",
    "ui_graph_title": "Активность записи",
    "ui_update_rate": "Скорость обновления: 1 раз в секунду",
    "ui_current_speed": "Скорость записи:",
    "ui_session_write": "За сессию:",
    "ui_boot_write": "С момента старта:",
    "ui_lifetime_tbw": "Ресурс (TBW):",
    "ui_about_title": "О программе",
    "ui_version": "Версия 1.0.0 (Swift Native)",
    "ui_description": "Легковесная утилита для посекундного мониторинга активности записи и контроля общего износа (Lifetime TBW) ваших накопителей.",
    "ui_close": "Готово",
    "ui_not_supported": "Не поддерживается",
    "ui_loading": "Загрузка...",
    "ui_smart_report_title": "Полный S.M.A.R.T. отчет" 
]

private let enDict: [String: String] = [
    "menu_title": "SSD Watch Monitoring",
    "menu_select_disk": "Select Drive",
    "menu_autostart": "Launch at System Startup",
    "menu_info": "Info...",
    "menu_quit": "Quit Application",
    "ui_graph_title": "Write Activity",
    "ui_update_rate": "Update rate: 1 time per second",
    "ui_current_speed": "Write Speed:",
    "ui_session_write": "This Session:",
    "ui_boot_write": "Since Launch:",
    "ui_lifetime_tbw": "Lifetime TBW:",
    "ui_about_title": "About",
    "ui_version": "Version 1.0.0 (Swift Native)",
    "ui_description": "A lightweight utility for second-by-second write activity monitoring and controlling the total wear (Lifetime TBW) of your drives.",
    "ui_close": "Done",
    "ui_not_supported": "Not supported",
    "ui_loading": "Loading...",
    "ui_smart_report_title": "Full S.M.A.R.T. Report"
]

