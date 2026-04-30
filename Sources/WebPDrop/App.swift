import SwiftUI

@main
struct WebPDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            DropZoneView()
        }
        .windowResizability(.contentMinSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            // Strip all menus except the app menu (index 0, contains Quit)
            if let mainMenu = NSApp.mainMenu {
                while mainMenu.items.count > 1 {
                    mainMenu.removeItem(at: 1)
                }
            }

            // Disable the green fullscreen button — fixed-size utility window
            for window in NSApp.windows {
                window.collectionBehavior.remove(.fullScreenPrimary)
            }
        }
    }
}
