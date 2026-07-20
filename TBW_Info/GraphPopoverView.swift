import SwiftUI
import Charts

struct GraphPopoverView: View {
    @ObservedObject var monitor: DiskMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Верхняя шапка окна (Добавлено имя диска в заголовок)
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Активность записи")
                            .font(.headline)
                        
                        // Яркий, моноширинный бейдж с именем текущего диска
                        Text("[\(monitor.targetDisk)]")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Text("Скорость обновления: 1 раз в секунду")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Закрыть приложение")
            }
            
            // Компонент живого графика скорости записи (МБ/с)
            Chart(monitor.statsHistory) { point in
                LineMark(
                    x: .value("Время", point.time),
                    y: .value("Скорость (МБ/с)", point.megabytesWritten)
                )
                .foregroundStyle(Color.orange.gradient)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Время", point.time),
                    y: .value("Скорость (МБ/с)", point.megabytesWritten)
                )
                .foregroundStyle(Color.orange.opacity(0.15).gradient)
                .interpolationMethod(.catmullRom)
            }
            .frame(height: 120)
            .padding(.trailing, 10)
            .id(monitor.targetDisk)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .second, count: 10)) { _ in
                    AxisValueLabel(format: .dateTime.minute().second())
                }
            }
            
            Divider()
            
            // Текстовая статистика строчками друг под другом
            VStack(spacing: 8) {
                
                // Строка 1: Текущая скорость
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .foregroundColor(.secondary)
                    Text("Текущая скорость записи:")
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    let lastPoints = monitor.statsHistory.suffix(5)
                    let maxSpeed = !lastPoints.isEmpty ? (lastPoints.map { $0.megabytesWritten }.max() ?? 0.0) : 0.0
                    
                    Text(String(format: "%.1f МБ/с", maxSpeed))
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 2: Записано за сессию приложения
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text("Записано за текущую сессию:")
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    let sessionComponents = monitor.tooltipText.components(separatedBy: "\n")
                    // ИСПРАВЛЕНИЕ: если в массиве больше 2 элементов, берем строку с индексом [2]
                    let sessionText = sessionComponents.count > 2 ? sessionComponents[2] : "За сессию: 0.0 ГБ"
                    Text(sessionText.replacingOccurrences(of: "За сессию: ", with: ""))
                        .font(.system(.subheadline, design: .monospaced)).bold()

                }
                
                // Строка 3: Записано с момента включения Mac
                HStack(spacing: 8) {
                    Image(systemName: "macmini")
                        .foregroundColor(.secondary)
                    Text("Записано с момента подключения диска:") // Скорректирован текст для универсальности
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(monitor.totalSinceBootDisplay)
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 4: Общий износ
                HStack(spacing: 8) {
                    Image(systemName: "bolt.shield.fill")
                        .foregroundColor(.orange)
                    Text("Общий износ SSD (Lifetime TBW):")
                        .foregroundColor(.orange)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    // дополнение подписи, если накопитель внешний или флешка без SMART
                    if monitor.lifetimeTBW == "Не поддерживается" {
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
        }
        .padding()
        // Оставили ширину 430, чтобы длинные серийники или логи SMART гарантированно влезали
        .frame(width: 430, height: 320)
    }
}

