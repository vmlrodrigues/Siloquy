import SwiftUI
import AppKit

/// The menu-bar item's icon.
///
/// Carries the active language's flag once there is more than one to choose between.
/// With a single language there is nothing to disambiguate, and a flag that never
/// changes is decoration — so the icon stays exactly as it was for anyone who has not
/// added a second language.
struct MenuBarLabel: View {
    @ObservedObject private var languages = DictationLanguageManager.shared

    var body: some View {
        let image: NSImage = {
            let ratio = $0.size.height / $0.size.width
            $0.size.height = 22
            $0.size.width = 22 / ratio
            return $0
        }(NSImage(named: "menuBarIcon")!)

        Image(nsImage: image)

        if languages.enabled.count > 1 {
            Text(languages.current.flag)
        }

        #if LOCAL_BUILD
        // Dev build (`make local`): label the menu-bar item so it's distinguishable
        // from the release app's icon at a glance.
        Text("DEV")
        #endif
    }
}
