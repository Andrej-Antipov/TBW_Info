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
            
            Text("ui_version")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("ui_description")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
            
            Spacer()
            
            Button("ui_close") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, 10)
        }
        .padding(16)
        .frame(width: 340, height: 210)
    }
}

