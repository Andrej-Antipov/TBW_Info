import Foundation
import Combine

// Структура точки данных для живого графика общей скорости
struct DiskPoint: Identifiable {
    let id = UUID()
    let time: Date
    let megabytesWritten: Double
}

// Структура процесса с точными полями чтения и записи в байтах (как в Stats)
struct DiskProcess: Identifiable {
    let id = UUID()
    let pid: Int
    let name: String
    let read: Int
    let write: Int
}

// Вспомогательная структура для хранения истории накопительного ввода-вывода (I/O)
struct ProcessSnapshotBytes {
    var read: Int
    var write: Int
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
    @Published var topProcesses: [DiskProcess] = [] // ТОП процессов для отображения в поповере
    
    @Published var targetDisk: String {
        didSet {
            UserDefaults.standard.set(targetDisk, forKey: "TargetDisk")
            resetTimer()
        }
    }
    
    @Published var updateInterval: Double = 1.0
    
    // Внутренние таймеры и словари истории
    private var speedTimer: Timer?
    private var smartTimer: Timer?
    private var processTimer: Timer?
    private var lastTotalBytes: UInt64 = 0
    private var initialSessionBytes: UInt64 = 0
    
    // Секретный буфер из Stats: хранит прошлые накопительные байты процессов по их PID
    private var processHistorySnapshot: [Int32: ProcessSnapshotBytes] = [:]
    
    init() {
        // Проверяем, есть ли уже сохраненный пользователем диск
        if let savedDisk = UserDefaults.standard.string(forKey: "TargetDisk") {
            self.targetDisk = savedDisk
        } else {
            // Если это ПЕРВЫЙ запуск — автоматически и нативно находим системный диск
            let detectedSystemDisk = DiskMonitor.findSystemDisk()
            self.targetDisk = detectedSystemDisk
            // Сразу сохраняем его, чтобы зафиксировать первый запуск
            UserDefaults.standard.set(detectedSystemDisk, forKey: "TargetDisk")
        }
        
        detectAvailableDisks()
        setupInitialStats()
        startMonitoring()
    }
    
    // НОВАЯ НА ТИВНАЯ ФУНКЦИЯ: определяет BSD-имя диска, с которого загружена текущая macOS
    private static func findSystemDisk() -> String {
        var stats = statfs()
        // Опрашиваем корневую директорию системы "/"
        if statfs("/", &stats) == 0 {
            // Получаем имя устройства (например, "/dev/disk1s1s1" или "/dev/disk0s2")
            let cString = withUnsafePointer(to: stats.f_mntfromname) { ptr in
                return String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
            }
            
            // С помощью регулярного выражения вырезаем чистое базовое имя диска (disk0, disk1 и т.д.)
            if let range = cString.range(of: "disk[0-9]{1,2}", options: .regularExpression) {
                return String(cString[range])
            }
        }
        
        // Резервный вариант на случай непредвиденной ошибки ядра — возвращаем стандартный disk0
        return "disk0"
    }


    // Часть 2
    private func setupInitialStats() {
        statsHistory.removeAll()
        lastTotalBytes = 0
        initialSessionBytes = 0
        lifetimeTBW = LanguageManager.shared.localizedString(for: "ui_loading")
        
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
    
    func startMonitoring() {
        smartTimer?.invalidate()
        smartTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.fetchLifetimeTBW()
        }
    }
    
    // ИСПРАВЛЕНО: Сброс истории процессов и зануление буфера iostat исключают "горб" на графике
    func startSpeedMonitoring() {
        speedTimer?.invalidate()
        speedTimer = nil
        processTimer?.invalidate()
        processTimer = nil
        
        topProcesses.removeAll()
        processHistorySnapshot.removeAll() // Очищаем историю процессов, чтобы не было старых скачков
        self.lastTotalBytes = 0
        
        // 1. Запускаем таймер скорости общей записи (раз в 1.0 секунду)
        self.speedTimer = Timer.scheduledTimer(withTimeInterval: self.updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        
        // 2. Сразу собираем ТОП процессов по логике Stats
        self.fetchTopWritingProcesses()
        
        // 3. Запускаем таймер обновления процессов (раз в 2.0 секунды, как в Stats для отзывчивости)
        self.processTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetchTopWritingProcesses()
        }
    }
    
    func stopSpeedMonitoring() {
        speedTimer?.invalidate()
        speedTimer = nil
        processTimer?.invalidate()
        processTimer = nil
    }
    
    private func resetTimer() {
        speedTimer?.invalidate()
        speedTimer = nil
        smartTimer?.invalidate()
        smartTimer = nil
        processTimer?.invalidate()
        processTimer = nil
        setupInitialStats()
        startMonitoring()
    }
    //Часть 3
    private func tick() {
        fetchDeviceWrittenBytesAsync { [weak self] currentBytes in
            guard let self = self, let currentBytes = currentBytes else { return }
            
            // Если это первый тик после открытия окна — фиксируем точку отсчета и пропускаем математику
            if self.lastTotalBytes == 0 {
                self.lastTotalBytes = currentBytes
                if self.initialSessionBytes == 0 { self.initialSessionBytes = currentBytes }
                return
            }
            
            let deltaBytes = currentBytes >= self.lastTotalBytes ? (currentBytes - self.lastTotalBytes) : 0
            let deltaMB = Double(deltaBytes) / (1024.0 * 1024.0)
            self.lastTotalBytes = currentBytes
            
            let newPoint = DiskPoint(time: Date(), megabytesWritten: deltaMB)
            self.statsHistory.append(newPoint)
            
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
    private func fetchDeviceWrittenBytesAsync(completion: @escaping (UInt64?) -> Void) {
        let disk = self.targetDisk
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
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
                        
                        // АДАПТИРОВАНО ПОД macOS SEQUOIA: Ищем строку, где ровно 3 числовых элемента.
                        // Пример: ["20.21", "1115917", "22028.66"] -> (KB/t, xfrs, MB)
                        // Проверяем, что первая колонка является числом (Double), чтобы гарантированно отсечь заголовки ["KB/t", "xfrs", "MB"]
                        if components.count == 3, let firstComponent = components.first, Double(firstComponent.replacingOccurrences(of: ",", with: ".")) != nil {
                            
                            // Последний (3-й) элемент массива — это общий I/O объем диска в МБ
                            if let totalMBString = components.last, let totalMB = Double(totalMBString.replacingOccurrences(of: ",", with: ".")) {
                                let bytes = UInt64(totalMB * 1024 * 1024)
                                DispatchQueue.main.async { completion(bytes) }
                                return
                            }
                        }
                    }
                }
            } catch {}
            DispatchQueue.main.async { completion(nil) }
        }
    }


        // СЕКРЕТНЫЙ МЕТОД ИЗ STATS: Сбор активных PID через ps и точечный опрос ядра proc_pid_rusage
    func fetchTopWritingProcesses() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            // Вызываем команду ps для получения списка PID всех активных в данный момент процессов
            task.arguments = ["-Aceo", "pid,comm", "-r"]
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                guard let output = String(data: data, encoding: .utf8) else { return }
                
                var snapshot = self.processHistorySnapshot
                var currentProcesses: [DiskProcess] = []
                
                let lines = output.components(separatedBy: .newlines)
                
                for line in lines {
                    let str = line.trimmingCharacters(in: .whitespaces)
                    let components = str.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    
                    // Убеждаемся, что строка содержит PID и имя команды (минимум 2 компонента)
                    if components.count >= 2, let pidInt = Int32(components[0]) {
                        let pid = pidInt
                        let fullPath = components[1...].joined(separator: " ")
                        let name = URL(fileURLWithPath: fullPath).lastPathComponent
                        
                        // Делаем точечный легальный запрос к rusage_info для этого PID
                        var usage = rusage_info_v3()
                        let rusageResult = withUnsafeMutablePointer(to: &usage) { rusagePtr in
                            rusagePtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { infoPtr in
                                proc_pid_rusage(pid, RUSAGE_INFO_V3, infoPtr)
                            }
                        }
                        
                        // Если ядро успешно вернуло данные для этого конкретного процесса
                        if rusageResult != -1 {
                            let bytesRead = Int(usage.ri_diskio_bytesread)
                            let bytesWritten = Int(usage.ri_diskio_byteswritten)
                            
                            // Если процесса еще не было в нашем словаре — инициализируем его текущими байтами
                            if snapshot[pid] == nil {
                                snapshot[pid] = ProcessSnapshotBytes(read: bytesRead, write: bytesWritten)
                            }
                            
                            if let history = snapshot[pid] {
                                // Вычисляем чистую скорость (дельту) за прошедший интервал таймера
                                let readDelta = bytesRead - history.read
                                let writeDelta = bytesWritten - history.write
                                
                                // Отсекаем системный шум и фоновые оболочки, берем процессы с реальной активностью
                                if writeDelta > 0 && name != "kernel_task" && name != "TBW_Info" && name != "zsh" && name != "sh" {
                                    currentProcesses.append(DiskProcess(pid: Int(pid), name: name, read: readDelta, write: writeDelta))
                                }
                            }
                            
                            // Обновляем исторический буфер новыми накопительными значениями
                            snapshot[pid]?.read = bytesRead
                            snapshot[pid]?.write = bytesWritten
                        }
                    }
                }
                
                // Сохраняем обновленный снапшот истории
                self.processHistorySnapshot = snapshot
                
                // Схлопываем многопоточные процессы с одинаковыми именами, суммируя их запись
                var combined: [String: DiskProcess] = [:]
                for p in currentProcesses {
                    if let existing = combined[p.name] {
                        combined[p.name] = DiskProcess(pid: p.pid, name: p.name, read: existing.read + p.read, write: existing.write + p.write)
                    } else {
                        combined[p.name] = p
                    }
                }
                
                // Сортируем по убыванию чистой скорости записи (пишем в байтах, сортируем по write)
                let sortedTop = combined.values.sorted { $0.write > $1.write }.prefix(3)
                
                DispatchQueue.main.async {
                    // Обновляем UI массив только если лидеры реально изменились, защищая график от микро-рывков
                    if self.topProcesses.map({ $0.name }) != sortedTop.map({ $0.name }) || self.topProcesses.isEmpty {
                        self.topProcesses = Array(sortedTop)
                    }
                }
            } catch {
                print("Ошибка сбора процессов по методу Stats: \(error)")
            }
        }
    }
    
    func loadFullSmartReport() {
        let isRu = LanguageManager.shared.currentLanguage == .russian
        self.fullSmartReport = isRu ? "Чтение расширенных данных из NVMe контроллера..." : "Reading extended data from NVMe controller..."
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let bundlePath = Bundle.main.path(forResource: "smartctl", ofType: nil) else { return }
            
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
                    DispatchQueue.main.async { self.fullSmartReport = output }
                }
            } catch {
                DispatchQueue.main.async { self.fullSmartReport = "Error launching smartctl diagnostics." }
            }
        }
    }
}

