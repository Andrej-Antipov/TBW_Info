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

// Кастомный класс кнопки для строки меню, который разделяет клики штатно на уровне системы
class SSDStatusBarButton: NSButton {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    
    override func mouseDown(with event: NSEvent) {
        // Левый клик мыши
        onLeftClick?()
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Правый клик мыши
        onRightClick?()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    let monitor = DiskMonitor()
    var cancellables = Set<AnyCancellable>()
    
    var contextMenu = NSMenu()
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Настройка Popover (окна с графиком)
        popover.contentSize = NSSize(width: 430, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: GraphPopoverView(monitor: monitor))
        
        // Создаем элемент строки меню с фиксированной шириной иконки
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Вместо стандартной кнопки подставляем наш кастомный класс
        let customButton = SSDStatusBarButton()
        customButton.image = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: "SSD Watch")
        customButton.isBordered = false
        
        // Привязываем штатные действия к кликам
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
    
    // Сборщик меню (без лишних обнулений и скрытых флагов)
    // Динамически пересобираем меню правого клика и делаем его цветным 🎨
    func constructContextMenu() {
        contextMenu.items.removeAll()
        
        // 1. Заголовок приложения
        let titleItem = NSMenuItem(title: "Мониторинг SSD Watch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let titleImg = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil) {
            titleImg.isTemplate = false // Выключаем ч/б маску
            // Раскрашиваем пульс в фирменный оранжевый цвет
            titleItem.image = titleImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        }
        contextMenu.addItem(titleItem)
        contextMenu.addItem(NSMenuItem.separator())
        
        // 2. ПОДМЕНЮ: Выбор накопителя
        let diskMenuItem = NSMenuItem(title: "Выбор накопителя", action: nil, keyEquivalent: "")
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
        
        // 3. СТРОКА: Автозапуск с оранжевой ракетой 🚀
        let autoStartItem = NSMenuItem(title: "Запускать при старте системы", action: #selector(toggleAutoStartAction(_:)), keyEquivalent: "")
        autoStartItem.target = self
        
        // Пытаемся получить нативную ракету (shuttle)
        var rocketImg = NSImage(systemSymbolName: "shuttle", accessibilityDescription: nil)
        if rocketImg == nil {
            rocketImg = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)
        }
        
        if let finalRocket = rocketImg {
            finalRocket.isTemplate = false // КРИТИЧЕСКИ ВАЖНО: Разрешаем цвет!
            // Красим ракету в сочный оранжевый градиент/цвет
            autoStartItem.image = finalRocket.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
        }
        
        if #available(macOS 13.0, *) {
            autoStartItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
        contextMenu.addItem(autoStartItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        // 4. СТРОКА: Инфо...
        let infoItem = NSMenuItem(title: "Инфо...", action: #selector(openSettingsWindow), keyEquivalent: "i")
        infoItem.target = self
        if let infoImg = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) {
            infoImg.isTemplate = false
            // Инфо сделаем приятно-зеленым или стандартным серым
            infoItem.image = infoImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemGreen]))
        }
        contextMenu.addItem(infoItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        // 5. СТРОКА: Выйти (с ярко-красной кнопкой питания) 🔴
        let quitItem = NSMenuItem(title: "Выйти из программы", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let powerImg = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            powerImg.isTemplate = false // Разрешаем цвет!
            // Красим кнопку выхода в предупреждающий нативный красный цвет
            quitItem.image = powerImg.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        }
        contextMenu.addItem(quitItem)
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
    
    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 210),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "О программе"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            self.settingsWindow = window
        }
        
        // Принудительно выводим окно на самый верхний слой
        settingsWindow?.level = .floating
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

