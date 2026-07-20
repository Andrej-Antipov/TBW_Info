import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 42))
                .foregroundColor(.orange)
                .padding(.top, 10)
            
            Text("SSD Watch")
                .font(.title3).bold()
            
            Text("Версия 1.0.0 (Swift Native)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Легковесная утилита для посекундного мониторинга активности записи и контроля общего износа (Lifetime TBW) ваших накопителей.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
            
            Spacer()
            
            Button("Закрыть") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, 10)
        }
        .padding(16)
        .frame(width: 340, height: 210) // квадратный размер карточки Инфо
    }
}

