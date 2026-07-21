
import SwiftUI

struct SmartReportView: View {
    @ObservedObject var monitor: DiskMonitor
    @ObservedObject var lang = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Шапка окна
            HStack {
                Image(systemName: "doc.plaintext.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                // чтение из словаря
                Text(lang.localizedString(for: "ui_smart_report_title"))
                    .font(.headline)
                
                Text("[\(monitor.targetDisk)]")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Лог Терминала
            ScrollView {
                let loadingText = lang.currentLanguage == .russian ? "Чтение данных из NVMe контроллера..." : "Reading data from NVMe controller..."
                
                Text(monitor.fullSmartReport.isEmpty ? loadingText : monitor.fullSmartReport)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Кнопка закрытия
            HStack {
                Spacer()
                // Исправлено: чтение из словаря + исправлена опечатка ui_close
                Button(lang.localizedString(for: "ui_close")) {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 420)
    }
}
