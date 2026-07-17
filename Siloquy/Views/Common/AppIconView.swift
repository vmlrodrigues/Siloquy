import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 160, height: 160)
                .blur(radius: 30)
            
            // Use the running app's actual icon. NSImage(named: "AppIcon") returns nil in the
            // dev build, where the designated app icon is AppIcon-Dev — so the About screen
            // showed nothing. applicationIconImage is whatever this build actually uses.
            if let image = NSApp.applicationIconImage ?? NSImage(named: "AppIcon") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .accentColor.opacity(0.3), radius: 20)
            }
        }
    }
} 