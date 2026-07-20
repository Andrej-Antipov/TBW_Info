import Foundation
import Combine

struct DiskPoint: Identifiable {
    let id = UUID()
    let time: Date
    let megabytesWritten: Double
}

class DiskMonitor: ObservableObject {
    @Published var tooltipText: String = "Загрузка..."
    @Published var statsHistory: [DiskPoint] = []
    @Published var lifetimeTBW: String = "Чтение..."
    @Published var totalSinceBootDisplay: String = "0.0 ГБ"
    @Published var availableDisks: [String] = ["disk0"] // По умолчанию всегда есть disk0
    
    @Published var targetDisk: String {
        didSet {
            UserDefaults.standard.set(targetDisk, forKey: "TargetDisk")
            resetTimer()
        }
    }
    
    @Published var updateInterval: Double = 1.0
    
    private var speedTimer: Timer?
    private var smartTimer: Timer?
    private var lastTotalBytes: UInt64 = 0
    private var initialSessionBytes: UInt64 = 0
    
    init() {
        // Достаем сохраненный диск ИЛИ ставим дефолтный диск0
        let savedDisk = UserDefaults.standard.string(forKey: "TargetDisk") ?? "disk0"
        self.targetDisk = savedDisk
        
        // Быстро сканируем диски в фоне, чтобы не тормозить запуск приложения
        detectAvailableDisks()
        
        setupInitialStats()
        startMonitoring()
    }
    
    private func setupInitialStats() {
        statsHistory.removeAll()
        lastTotalBytes = 0
        initialSessionBytes = 0
        
        if let currentBytes = fetchDeviceWrittenBytes() {
            lastTotalBytes = currentBytes
            initialSessionBytes = currentBytes
            
            let now = Date()
            for i in stride(from: 30, through: 1, by: -1) {
                statsHistory.append(DiskPoint(time: now.addingTimeInterval(TimeInterval(-i)), megabytesWritten: 0.0))
            }
            
            let totalBootGB = Double(currentBytes) / (1024.0 * 1024.0 * 1024.0)
            self.totalSinceBootDisplay = String(format: "%.2f ГБ", totalBootGB)
            updateTooltip(deltaMB: 0, totalSessionGB: 0)
        } else {
            // Если внешний диск вернул 0 (например, iostat не поддерживает счетчик для этой флешки)
            // Мы искусственно наполняем график нулями, чтобы приложение продолжало работать
            let now = Date()
            for i in stride(from: 30, through: 1, by: -1) {
                statsHistory.append(DiskPoint(time: now.addingTimeInterval(TimeInterval(-i)), megabytesWritten: 0.0))
            }
            self.totalSinceBootDisplay = "0.00 ГБ"
            updateTooltip(deltaMB: 0, totalSessionGB: 0)
        }
        fetchLifetimeTBW()
    }
    
    func startMonitoring() {
        speedTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        
        smartTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.fetchLifetimeTBW()
        }
    }
    
    private func resetTimer() {
        speedTimer?.invalidate()
        smartTimer?.invalidate()
        setupInitialStats()
        startMonitoring()
    }
    
    private func tick() {
        guard let currentBytes = fetchDeviceWrittenBytes() else { return }
        
        // Защита: Если это первый запуск для нового внешнего диска, фиксируем точку отсчета
        if lastTotalBytes == 0 { lastTotalBytes = currentBytes }
        if initialSessionBytes == 0 { initialSessionBytes = currentBytes }
        
        let deltaBytes = currentBytes >= lastTotalBytes ? (currentBytes - lastTotalBytes) : 0
        let deltaMB = Double(deltaBytes) / (1024.0 * 1024.0)
        lastTotalBytes = currentBytes
        
        let newPoint = DiskPoint(time: Date(), megabytesWritten: deltaMB)
        statsHistory.append(newPoint)
        
        if statsHistory.count > 30 {
            statsHistory.removeFirst()
        }
        
        let totalSessionBytes = currentBytes >= initialSessionBytes ? (currentBytes - initialSessionBytes) : 0
        let totalSessionGB = Double(totalSessionBytes) / (1024.0 * 1024.0 * 1024.0)
        let totalBootGB = Double(currentBytes) / (1024.0 * 1024.0 * 1024.0)
        
        DispatchQueue.main.async {
            self.totalSinceBootDisplay = String(format: "%.2f ГБ", totalBootGB)
            self.updateTooltip(deltaMB: deltaMB, totalSessionGB: totalSessionGB)
        }
    }
    
    private func updateTooltip(deltaMB: Double, totalSessionGB: Double) {
        let formattedSpeed = String(format: "%.1f", deltaMB)
        let formattedTotal = String(format: "%.2f", totalSessionGB)
        
        tooltipText = """
        Мониторинг SSD (\(targetDisk))
        Текущая запись: \(formattedSpeed) МБ/с
        За сессию: \(formattedTotal) ГБ
        Всего износ (TBW): \(lifetimeTBW)
        """
    }
    
    func fetchLifetimeTBW() {
        DispatchQueue.global(qos: .background).async {
            guard let bundlePath = Bundle.main.path(forResource: "smartctl", ofType: nil) else {
                DispatchQueue.main.sync { self.lifetimeTBW = "Ошибка утилиты" }
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
                                self.lifetimeTBW = clean
                            }
                            return
                        }
                    }
                }
                DispatchQueue.main.async { self.lifetimeTBW = "Не поддерживается" }
            } catch {
                DispatchQueue.main.sync { self.lifetimeTBW = "Ошибка" }
            }
        }
    }
    
    // ИСПРАВЛЕНИЕ: Перенесли весь вызов diskutil строго в фоновый поток (background), чтобы убрать тормоза интерфейса!
    func detectAvailableDisks() {
        DispatchQueue.global(qos: .userInitiated).async {
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
    
    // ИСПРАВЛЕНИЕ: Переписан парсер iostat. Теперь он четко изолирует переданный targetDisk
    private func fetchDeviceWrittenBytes() -> UInt64? {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        // Запрашиваем iostat общую статистику в ГБ/МБ для выбранного диска targetDisk
        task.arguments = ["-d", "-I", self.targetDisk]
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                
                // Ищем строку значений (обычно iostat выводит заголовок диска, а под ним строку чисел)
                for line in lines {
                    let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    
                    // Защита от парсинга строк-заголовков (в них буквы, а нам нужны только колонки с цифрами)
                    if components.count >= 3 {
                        // Последняя колонка в iostat -d -I - это ВСЕГО переданных МБ на устройство
                        if let totalMB = Double(components.last!), components.allSatisfy({ Double($0) != nil }) {
                            return UInt64(totalMB * 1024 * 1024)
                        }
                    }
                }
            }
        } catch {}
    
        return nil
    }
}
