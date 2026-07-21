import SwiftUI
import AppKit
import Combine
import ServiceManagement

@main
struct SSDWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class SSDStatusBarButton: NSButton {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        onLeftClick?()
    }
    
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    let monitor = DiskMonitor()
    var cancellables = Set<AnyCancellable>()
    var smartWindow: NSWindow? // Переменная для окна SMART отчета

    
    var contextMenu = NSMenu()
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Настройка Popover (окна с графиком)
        popover.contentSize = NSSize(width: 360, height: 220)
        popover.behavior = .transient
        
        // Читаем выбранный язык и внедряем его в окружение SwiftUI графика
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? ["ru"]
        let currentLang = languages.first ?? "ru"
        
        popover.contentViewController = NSHostingController(
            rootView: GraphPopoverView(monitor: monitor)
                .environment(\.locale, Locale(identifier: currentLang)) // Жестко фиксируем язык для SwiftUI
        )

        
        // Создаем элемент строки меню с фиксированной шириной иконки
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Вместо стандартной кнопки кастомный класс
        let customButton = SSDStatusBarButton()
        customButton.image = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: "SSD Watch")
        customButton.isBordered = false
        
        customButton.onLeftClick = { [weak self] in
            self?.showGraphPopover()
        }
        customButton.onRightClick = { [weak self] in
            self?.showContextMenu()
        }
        
        // Интегрируем кнопку в статус-бар
        statusItem?.button?.addSubview(customButton)
        customButton.frame = statusItem?.button?.bounds ?? .zero
        
        // Подвязываем тултип
        if let button = statusItem?.button {
            button.toolTip = monitor.tooltipText
            monitor.$tooltipText
                .receive(on: RunLoop.main)
                .sink { [weak button] text in
                    button?.toolTip = text
                }
                .store(in: &cancellables)
        }
        // ДОБАВЛЕНО: Следим за открытием и закрытием окна графика
        NotificationCenter.default.addObserver(self, selector: #selector(popoverWillShow), name: NSPopover.willShowNotification, object: popover)
        NotificationCenter.default.addObserver(self, selector: #selector(popoverDidClose), name: NSPopover.didCloseNotification, object: popover)

    }
    
    // Функция вызова живого графика (левый клик)
    func showGraphPopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    // Функция вызова меню настроек (правый клик)
    func showContextMenu() {
        constructContextMenu()
        // Используем официальный метод вызова контекстного меню прямо под иконкой
        if let button = statusItem?.button {
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
    
    // Сборщик меню
    // Динамически пересобираем меню правого клика
    func constructContextMenu() {
        contextMenu.items.removeAll()
        
        // 1. Заголовок приложения
        let titleItem = NSMenuItem(title: NSLocalizedString("Мониторинг SSD Watch", comment: ""), action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let titleImg = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil) {
            titleImg.isTemplate = false // Выключаем ч/б маску
            // Раскрашиваем пульс в фирменный оранжевый цвет
            titleItem.image = titleImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        }
        contextMenu.addItem(titleItem)
        contextMenu.addItem(NSMenuItem.separator())
        
        // 2. ПОДМЕНЮ: Выбор накопителя
        let diskMenuItem = NSMenuItem(title: NSLocalizedString("Выбор накопителя", comment: ""), action: nil, keyEquivalent: "")
        if let diskImg = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil) {
            diskImg.isTemplate = false
            // Диск сделаем классическим синим/акцентным
            diskMenuItem.image = diskImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor]))
        }
        
        let diskSubmenu = NSMenu()
        monitor.detectAvailableDisks()
        
        for disk in monitor.availableDisks {
            let item = NSMenuItem(title: disk, action: #selector(selectDiskAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = disk
            
            if let subDiskImg = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil) {
                subDiskImg.isTemplate = false
                item.image = subDiskImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
            }
            
            if disk == monitor.targetDisk {
                item.state = .on
            }
            diskSubmenu.addItem(item)
        }
        diskMenuItem.submenu = diskSubmenu
        contextMenu.addItem(diskMenuItem)
        
        // 3. Автозапуск с оранжевой ракетой 🚀
        let autoStartItem = NSMenuItem(title: NSLocalizedString("Запускать при старте системы", comment: ""), action: #selector(toggleAutoStartAction(_:)), keyEquivalent: "")
        autoStartItem.target = self
        
        // Получаем нативную ракету (shuttle)
        var rocketImg = NSImage(systemSymbolName: "shuttle", accessibilityDescription: nil)
        if rocketImg == nil {
            rocketImg = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)
        }
        
        if let finalRocket = rocketImg {
            finalRocket.isTemplate = false // Разрешаем цвет!
            // Красим ракету в сочный оранжевый градиент/цвет
            autoStartItem.image = finalRocket.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        }
        
        if #available(macOS 13.0, *) {
            autoStartItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
        contextMenu.addItem(autoStartItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        // СТРОКА: S.M.A.R.T. отчет...
        let isRussian = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first?.hasPrefix("ru") ?? true
        
        let smartReportItem = NSMenuItem(
            title: isRussian ? "S.M.A.R.T. отчет..." : "S.M.A.R.T. Report...",
            action: #selector(openSmartReportWindow),
            keyEquivalent: "s"
        )
        smartReportItem.target = self
        if let docImg = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil) {
            docImg.isTemplate = false
            smartReportItem.image = docImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        }
        contextMenu.addItem(smartReportItem)
        
        contextMenu.addItem(NSMenuItem.separator()) // Красивый разделитель перед Инфо


        
        // 4. СТРОКА: Инфо...
        let infoItem = NSMenuItem(
            title: NSLocalizedString("menu_info_item", comment: ""),
            action: #selector(openSettingsWindow),
            keyEquivalent: "i"
        )
        infoItem.target = self
        if let infoImg = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) {
            infoImg.isTemplate = false
            // Инфо сделаем приятно-зеленым или стандартным серым
            infoItem.image = infoImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemGreen]))
        }
        contextMenu.addItem(infoItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        // ПОДМЕНЮ: Выбор языка
        let langMenuItem = NSMenuItem(title: "Language / Язык", action: nil, keyEquivalent: "")
        
        // Для глобуса не нужно отключать isTemplate,
        // система сама покрасит стандартный монохромный силуэт в выбранный цвет!
        if let langImg = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) {
            langMenuItem.image = langImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemCyan]))
        }
        
        let langSubmenu = NSMenu()
        let ruItem = NSMenuItem(title: "Русский", action: #selector(setLanguageRu), keyEquivalent: "")
        let enItem = NSMenuItem(title: "English", action: #selector(setLanguageEn), keyEquivalent: "")
        
        ruItem.target = self
        enItem.target = self
        
        // Читаем сохраненный язык как МАССИВ строк [String]
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? ["ru"]
        let currentLang = languages.first ?? "ru"
        
        // Выставляем системные галочки (checkmark)
        if currentLang.hasPrefix("ru") {
            ruItem.state = .on
            enItem.state = .off
        } else {
            enItem.state = .on
            ruItem.state = .off
        }
        
        langSubmenu.addItem(ruItem)
        langSubmenu.addItem(enItem)
        langMenuItem.submenu = langSubmenu
        contextMenu.addItem(langMenuItem)


        
        // 5. СТРОКА: Выйти
        let quitItem = NSMenuItem(title: NSLocalizedString("Выйти из программы", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let powerImg = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            powerImg.isTemplate = false // Разрешаем цвет!
            // Красим кнопку выхода в предупреждающий нативный красный цвет
            quitItem.image = powerImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        }
        contextMenu.addItem(quitItem)
    }
    
    @objc func openSmartReportWindow() {
        monitor.loadFullSmartReport()
        
        // Всегда создаем окно с нуля, чтобы сбросить языковой кэш SwiftUI
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "S.M.A.R.T. Diagnostics"
        window.isReleasedWhenClosed = false
        
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? ["ru"]
        let currentLang = languages.first ?? "ru"
        
        window.contentView = NSHostingView(
            rootView: SmartReportView(monitor: monitor)
                .environment(\.locale, Locale(identifier: currentLang))
        )
        self.smartWindow = window
        
        smartWindow?.level = .floating
        smartWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func selectDiskAction(_ sender: NSMenuItem) {
        if let diskName = sender.representedObject as? String {
            monitor.targetDisk = diskName
            
            // Если Popover был открыт, плавно обновляем его
            if popover.isShown, let button = statusItem?.button {
                popover.performClose(nil)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    @objc func setLanguageRu() {
        UserDefaults.standard.set(["ru"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        relaunchApp()
    }

    @objc func setLanguageEn() {
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        relaunchApp()
    }


    // МЕТОД ПЕРЕЗАПУСКА ПРИЛОЖЕНИЯ НА MACOS
    private func relaunchApp() {
        // Получаем путь к исполняемому файлу текущего запущенного приложения
        let bundleURL = Bundle.main.bundleURL
        
        // Создаем системный фоновый процесс, который откроет наше приложение заново
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path] // Флаг "-n" открывает новый чистый экземпляр программы
        
        do {
            try task.run() // Запускаем копию приложения
            NSApplication.shared.terminate(nil) // Мгновенно завершаем текущую (старую) копию приложения
        } catch {
            print("Ошибка перезапуска приложения: \(error)")
            // Если что-то пошло не так, просто перерисовываем меню как откат
            constructContextMenu()
        }
    }

    
    @objc func toggleAutoStartAction(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                    sender.state = .off
                } else {
                    try service.register()
                    sender.state = .on
                }
            } catch {
                print("Ошибка автозапуска: \(error)")
            }
        }
    }
    
    @objc func popoverWillShow() {
        // Окно открывается -> Мгновенно будим таймер iostat, нагрузка 1% только пока смотрим на экран 🏃‍♂️
        monitor.startSpeedMonitoring()
    }
    
    @objc func popoverDidClose() {
        // Окно закрылось -> Полностью усыпляем секундный таймер. Нагрузка на CPU падает до 0.0% 💤
        monitor.stopSpeedMonitoring()
    }

    
    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 210),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = LanguageManager.shared.localizedString(for: "ui_about_title")
            window.isReleasedWhenClosed = false
            
            //Передаем локаль в окно Инфо
            let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? ["ru"]
            let currentLang = languages.first ?? "ru"
            
            window.contentView = NSHostingView(
                rootView: SettingsView()
                    .environment(\.locale, Locale(identifier: currentLang))
            )
            self.settingsWindow = window
        }
        settingsWindow?.level = .floating
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

