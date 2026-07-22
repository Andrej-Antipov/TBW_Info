import SwiftUI
import Charts

struct GraphPopoverView: View {
    @ObservedObject var monitor: DiskMonitor
    @Environment(\.locale) var locale
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Раздел 1: Шапка окна
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("ui_graph_title")
                    .font(.headline)
                
                Text("[\(monitor.targetDisk)]")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.orange)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("menu_quit", comment: ""))
            }
            
            // Расчет шкалы Y на основе текущей секундной истории (30 секунд)
            let displayedPoints = monitor.statsHistory
            let currentMax = displayedPoints.map { $0.megabytesWritten }.max() ?? 0.0
            let yMaxLimit = max(10.0, currentMax * 1.1)
            
            // Раздел 2: Живой график скорости записи (МБ/с)
            Chart(displayedPoints) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Speed", point.megabytesWritten)
                )
                .foregroundStyle(Color.orange.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Speed", point.megabytesWritten)
                )
                .foregroundStyle(Color.orange.opacity(0.15).gradient)
                .interpolationMethod(.catmullRom)
            }
            .frame(width: 320, height: 80)
            .id(monitor.targetDisk)
            .chartYScale(domain: 0...yMaxLimit)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                // Автоматическое распределение меток времени, исключающее слияние в полосу
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel(format: .dateTime.minute().second())
                }
            }
            
            Divider() // Первый разделитель: между графиком и текстовой статистикой
            
            // Раздел 3: Накопительная текстовая статистика
            VStack(spacing: 5) {
                // Строка 1: Текущая скорость записи
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .foregroundColor(.secondary)
                    Text("ui_current_speed")
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    let lastPoints = displayedPoints.suffix(5)
                    let maxSpeed = !lastPoints.isEmpty ? (lastPoints.map { $0.megabytesWritten }.max() ?? 0.0) : 0.0
                    
                    let isRu = locale.identifier.hasPrefix("ru")
                    let speedUnit = isRu ? "МБ/с" : "MB/s"
                    
                    Text(String(format: "%.1f \(speedUnit)", maxSpeed))
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 2: За текущую сессию
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text("ui_session_write")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(monitor.sessionWriteDisplay)
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 3: С момента загрузки macOS
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .foregroundColor(.secondary)
                    Text("ui_boot_write")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(monitor.totalSinceBootDisplay)
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 4: Общий ресурс накопителя (TBW)
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.orange)
                    Text("ui_lifetime_tbw")
                        .foregroundColor(.orange)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    if monitor.targetDisk != "disk0" {
                        Text("(USB / Flash)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(monitor.lifetimeTBW)
                        .font(.system(.subheadline, design: .monospaced)).bold()
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 2)
            
            Divider() // Второй разделитель: между статистикой и списком процессов
            
            // Раздел 4: Список самых активных приложений (ТОП-3) по логике Stats
            VStack(alignment: .leading, spacing: 4) {
                Text(locale.identifier.hasPrefix("ru") ? "Скорость записи (ТОП процессов):" : "Write Speed (Top Processes):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .bold()
                    .padding(.bottom, 2)
                
                if monitor.topProcesses.isEmpty {
                    HStack {
                        Text(locale.identifier.hasPrefix("ru") ? "Анализ активности..." : "Analyzing activity...")
                            .font(.caption.monospaced())
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(height: 50) // Резервируем высоту, чтобы поповер не прыгал
                } else {
                    VStack(spacing: 4) {
                        ForEach(monitor.topProcesses) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                                    .frame(width: 14)
                                
                                // Фиксируем ширину под название процесса, убирая микро-сдвиги
                                Text(item.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(width: 170, alignment: .leading)
                                
                                Spacer()
                                
                                // Конвертер байт в КБ/с или МБ/с в реальном времени
                                let isRu = locale.identifier.hasPrefix("ru")
                                let bytes = item.write // Скорость записи в байтах за интервал
                                
                                if bytes >= 1024 * 1024 * 1024 {
                                    let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
                                    Text(String(format: "%.1f \(isRu ? "ГБ/с" : "GB/s")", gb))
                                        .font(.system(.caption, design: .monospaced)).bold()
                                        .frame(width: 75, alignment: .trailing)
                                } else if bytes >= 1024 * 1024 {
                                    let mb = Double(bytes) / (1024.0 * 1024.0)
                                    Text(String(format: "%.1f \(isRu ? "МБ/с" : "MB/s")", mb))
                                        .font(.system(.caption, design: .monospaced)).bold()
                                        .frame(width: 75, alignment: .trailing)
                                } else if bytes >= 1024 {
                                    let kb = Double(bytes) / 1024.0
                                    Text(String(format: "%.1f \(isRu ? "КБ/с" : "KB/s")", kb))
                                        .font(.system(.caption, design: .monospaced)).bold()
                                        .frame(width: 75, alignment: .trailing)
                                } else {
                                    Text("\(bytes) \(isRu ? "Б/с" : "B/s")")
                                        .font(.system(.caption, design: .monospaced)).bold()
                                        .frame(width: 75, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .frame(height: 50, alignment: .top) // Фиксируем общую высоту контейнера ТОП-3
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        // Высота зафиксирована на 310 пикселях для идеального баланса геометрии
        .frame(width: 360, height: 310)
        .onAppear {
            // Включаем секундный опрос скорости и фоновый поиск процессов при открытии окна
            monitor.startSpeedMonitoring()
        }
        .onDisappear {
            // Полностью тушим все секундные таймеры при закрытии окна для экономии ресурсов
            monitor.stopSpeedMonitoring()
        }
    }
}

