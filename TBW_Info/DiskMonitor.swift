import Foundation
import Combine

// Структура точки данных для графика
struct DiskPoint: Identifiable {
    let id = UUID()
    let time: Date
    let megabytesWritten: Double
}

class DiskMonitor: ObservableObject {
    // Наблюдаемые свойства для интерфейса (UI)
    @Published var tooltipText: String = "Загрузка..."
    @Published var statsHistory: [DiskPoint] = []
    @Published var lifetimeTBW: String = "Чтение..."
    @Published var totalSinceBootDisplay: String = "0.0 ГБ"
    @Published var sessionWriteDisplay: String = "0.0 ГБ"
    @Published var availableDisks: [String] = ["disk0"]
    @Published var fullSmartReport: String = ""
    
    @Published var targetDisk: String {
        didSet {
            UserDefaults.standard.set(targetDisk, forKey: "TargetDisk")
            resetTimer()
        }
    }
    
    @Published var updateInterval: Double = 1.0
    
    // Внутренние таймеры и счетчики байт
    private var speedTimer: Timer?
    private var smartTimer: Timer?
    private var lastTotalBytes: UInt64 = 0
    private var initialSessionBytes: UInt64 = 0
    
    init() {
        let savedDisk = UserDefaults.standard.string(forKey: "TargetDisk") ?? "disk0"
        self.targetDisk = savedDisk
        
        detectAvailableDisks()
        setupInitialStats()
        startMonitoring()
    }
    
    // Первоначальное заполнение графической истории "пустыми" точками
    private func setupInitialStats() {
        statsHistory.removeAll()
        lastTotalBytes = 0
        initialSessionBytes = 0
        lifetimeTBW = LanguageManager.shared.localizedString(for: "ui_loading")
        
        // Передаем временный блок, так как получение теперь асинхронное
        fetchDeviceWrittenBytesAsync { [weak self] currentBytes in
            guard let self = self else { return }
            
            let now = Date()
            for i in stride(from: 30, through: 1, by: -1) {
                self.statsHistory.append(DiskPoint(time: now.addingTimeInterval(TimeInterval(-i)), megabytesWritten: 0.0))
            }
            
            if let currentBytes = currentBytes {
                self.lastTotalBytes = currentBytes
                self.initialSessionBytes = currentBytes
                
                let totalBootGB = Double(currentBytes) / (1024.0 * 1024.0 * 1024.0)
                let lang = LanguageManager.shared.currentLanguage
                self.totalSinceBootDisplay = String(format: lang == .russian ? "%.2f ГБ" : "%.2f GB", totalBootGB)
            } else {
                self.totalSinceBootDisplay = "0.00 ГБ"
            }
            
            let lang = LanguageManager.shared.currentLanguage
            self.sessionWriteDisplay = String(format: lang == .russian ? "%.2f ГБ" : "%.2f GB", 0.0)
            self.updateTooltip(deltaMB: 0, totalSessionGB: 0)
            self.fetchLifetimeTBW()
        }
    }
    // Фоновый запуск: при старте запускается ТОЛЬКО редкий таймер SMART раз в 5 минут
    func startMonitoring() {
        smartTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.fetchLifetimeTBW()
        }
    }
    
    // ИСПРАВЛЕНО: Перед запуском таймера синхронизируем счетчик байт с системой,
    // чтобы не было ложного "горба" из накопленных за время закрытия окна данных.
    func startSpeedMonitoring() {
        speedTimer?.invalidate() // Страховка от дублирования
        
        fetchDeviceWrittenBytesAsync { [weak self] currentBytes in
            guard let self = self, let currentBytes = currentBytes else {
                // Если iostat не ответил, просто запускаем таймер
                self?.launchSpeedTimer()
                return
            }
            // Актуализируем точку отсчета перед первым тиком
            self.lastTotalBytes = currentBytes
            self.launchSpeedTimer()
        }
    }
    
    // Вспомогательный метод для старта самого таймера
    private func launchSpeedTimer() {
        speedTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    // Метод полной остановки секундного таймера для экономии CPU (вызывать при onDisappear окна)
    func stopSpeedMonitoring() {
        speedTimer?.invalidate()
        speedTimer = nil
    }

    private func resetTimer() {
        speedTimer?.invalidate()
        smartTimer?.invalidate()
        setupInitialStats()
        startMonitoring()
    }
    
    private func tick() {
        fetchDeviceWrittenBytesAsync { [weak self] currentBytes in
            guard let self = self, let currentBytes = currentBytes else { return }
            
            // Защитная проверка на случай, если это самый первый запуск приложения
            if self.lastTotalBytes == 0 { self.lastTotalBytes = currentBytes }
            if self.initialSessionBytes == 0 { self.initialSessionBytes = currentBytes }
            
            let deltaBytes = currentBytes >= self.lastTotalBytes ? (currentBytes - self.lastTotalBytes) : 0
            let deltaMB = Double(deltaBytes) / (1024.0 * 1024.0)
            self.lastTotalBytes = currentBytes
            
            let newPoint = DiskPoint(time: Date(), megabytesWritten: deltaMB)
            self.statsHistory.append(newPoint)
            
            // Защита от переполнения: на графике всегда ровно 30 точек
            if self.statsHistory.count > 30 {
                self.statsHistory.removeFirst()
            }
            
            let totalSessionBytes = currentBytes >= self.initialSessionBytes ? (currentBytes - self.initialSessionBytes) : 0
            let totalSessionGB = Double(totalSessionBytes) / (1024.0 * 1024.0 * 1024.0)
            let totalBootGB = Double(currentBytes) / (1024.0 * 1024.0 * 1024.0)
            
            let lang = LanguageManager.shared.currentLanguage
            self.totalSinceBootDisplay = String(format: lang == .russian ? "%.2f ГБ" : "%.2f GB", totalBootGB)
            self.sessionWriteDisplay = String(format: lang == .russian ? "%.2f ГБ" : "%.2f GB", totalSessionGB)
            self.updateTooltip(deltaMB: deltaMB, totalSessionGB: totalSessionGB)
        }
    }
    
    func updateTooltip(deltaMB: Double, totalSessionGB: Double) {
        let lang = LanguageManager.shared
        let formattedTotal = String(format: "%.2f", totalSessionGB)
        
        let titleText = lang.localizedString(for: "menu_title")
        let sessionLabel = lang.localizedString(for: "ui_session_write")
        let tbwLabel = lang.localizedString(for: "ui_lifetime_tbw")
        
        tooltipText = """
        \(titleText) (\(targetDisk))
        \(sessionLabel) \(formattedTotal)
        \(tbwLabel) \(lifetimeTBW)
        """
    }

    func fetchLifetimeTBW() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            guard let bundlePath = Bundle.main.path(forResource: "smartctl", ofType: nil) else {
                // ИСПРАВЛЕНО: Сменили sync на async для полной безопасности потоков
                DispatchQueue.main.async { self.lifetimeTBW = "Ошибка утилиты" }
                return
            }
            
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            task.arguments = ["-a", self.targetDisk]
            task.executableURL = URL(fileURLWithPath: bundlePath)
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("Data Units Written:") {
                            let clean = line.replacingOccurrences(of: "Data Units Written:", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            DispatchQueue.main.async {
                                // ИСПРАВЛЕНО: Парсим вывод, оставляя только компактное значение в скобках [например, 12.3 TB]
                                if let bracketRange = clean.range(of: "\\[.*\\]", options: .regularExpression) {
                                    self.lifetimeTBW = String(clean[bracketRange])
                                        .replacingOccurrences(of: "[", with: "")
                                        .replacingOccurrences(of: "]", with: "")
                                } else {
                                    self.lifetimeTBW = clean
                                }
                            }
                            return
                        }
                    }
                }
                DispatchQueue.main.async { self.lifetimeTBW = "Не поддерживается" }
            } catch {
                // ИСПРАВЛЕНО: Сменили sync на async, чтобы избежать зависаний приложения
                DispatchQueue.main.async { self.lifetimeTBW = "Ошибка" }
            }
        }
    }
    
    func detectAvailableDisks() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.arguments = ["list"]
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    var discovered = Set<String>()
                    
                    for line in lines {
                        if line.contains("/dev/disk") && line.contains("physical") {
                            if let range = line.range(of: "disk[0-9]{1,2}", options: .regularExpression) {
                                let diskName = String(line[range])
                                discovered.insert(diskName)
                            }
                        }
                    }
                    
                    let finalDisks = discovered.isEmpty ? ["disk0"] : discovered.sorted()
                    DispatchQueue.main.async {
                        self.availableDisks = finalDisks
                        // Если сохраненный диск пропал (вынули флешку), плавно сбрасываем на первый доступный
                        if !finalDisks.contains(self.targetDisk) {
                            self.targetDisk = finalDisks.first ?? "disk0"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { self.availableDisks = ["disk0"] }
            }
        }
    }
    // ИСПРАВЛЕНО: Полностью асинхронный метод запуска iostat в фоновом потоке.
    // Интерфейс больше не замирает и не дергается раз в секунду.
    private func fetchDeviceWrittenBytesAsync(completion: @escaping (UInt64?) -> Void) {
        let disk = self.targetDisk // Фиксируем имя диска для безопасного использования в фоне
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe() // Глушим системные предупреждения 0x5 в консоли
            
            task.arguments = ["-d", "-I", disk]
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    
                    for line in lines {
                        let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        
                        // Защита от парсинга строк-заголовков (проверяем, что в колонках только числа)
                        if components.count >= 3 {
                            if let totalMB = Double(components.last!), components.allSatisfy({ Double($0) != nil }) {
                                let bytes = UInt64(totalMB * 1024 * 1024)
                                // Возвращаем результат строго в главный поток
                                DispatchQueue.main.async { completion(bytes) }
                                return
                            }
                        }
                    }
                }
            } catch {}
            
            // В случае любой ошибки безопасно возвращаем nil в главный поток
            DispatchQueue.main.async { completion(nil) }
        }
    }
    
    // Метод On-Demand опроса для вывода расширенного лога SMART в окно диагностики
    func loadFullSmartReport() {
        let isRu = LanguageManager.shared.currentLanguage == .russian
        self.fullSmartReport = isRu ? "Чтение расширенных данных из NVMe контроллера..." : "Reading extended data from NVMe controller..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let bundlePath = Bundle.main.path(forResource: "smartctl", ofType: nil) else { return }
            
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe() // Глушим системные ошибки 0x5
            task.arguments = ["-a", self.targetDisk]
            task.executableURL = URL(fileURLWithPath: bundlePath)
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                if let output = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { self.fullSmartReport = output }
                }
            } catch {
                DispatchQueue.main.async { self.fullSmartReport = "Error launching smartctl diagnostics." }
            }
        }
    }
}

