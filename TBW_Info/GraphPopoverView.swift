import SwiftUI
import Charts

struct GraphPopoverView: View {
    @ObservedObject var monitor: DiskMonitor
    @Environment(\.locale) var locale
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Шапка окна
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
            
            // РЕШЕНИЕ: Берем только последние 60 точек (1 минута),
            // чтобы фоновый накопленный хвост не ломал ось X
            let displayedPoints = monitor.statsHistory.suffix(60)
            
            // Вычисление динамического масштаба шкалы Y только для видимых точек
            let currentMax = displayedPoints.map { $0.megabytesWritten }.max() ?? 0.0
            let yMaxLimit = max(10.0, currentMax * 1.1)
            
            // Компонент живого графика скорости записи (МБ/с)
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
                // РЕШЕНИЕ: Убираем жесткий stride по 10 сек.
                // Просим систему нарисовать всего 4 метки времени, они никогда не сольются.
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.gray.opacity(0.2))
                    AxisValueLabel(format: .dateTime.minute().second())
                }
            }
            
            Divider()
            
            // Текстовая статистика
            VStack(spacing: 5) {
                // Строка 1: Скорость записи
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .foregroundColor(.secondary)
                    Text("ui_current_speed")
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    // Расчет по последним точкам
                    let lastPoints = displayedPoints.suffix(5)
                    let maxSpeed = !lastPoints.isEmpty ? (lastPoints.map { $0.megabytesWritten }.max() ?? 0.0) : 0.0
                    
                    let isRu = locale.identifier.hasPrefix("ru")
                    let speedUnit = isRu ? "МБ/с" : "MB/s"
                    
                    Text(String(format: "%.1f \(speedUnit)", maxSpeed))
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 2: За сессию
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.secondary)
                    Text("ui_session_write")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(monitor.sessionWriteDisplay)
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 3: С момента старта
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .foregroundColor(.secondary)
                    Text("ui_boot_write")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(monitor.totalSinceBootDisplay)
                        .font(.system(.subheadline, design: .monospaced)).bold()
                }
                
                // Строка 4: Ресурс (TBW)
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
        }
        .padding(10)
        .frame(width: 360, height: 220)
    }
}

