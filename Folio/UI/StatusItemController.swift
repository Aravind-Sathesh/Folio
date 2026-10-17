import AppKit
import SwiftUI

/// The tray icon. A click opens the Folio window; there is no menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init()
        item.button?.image = NSImage(systemSymbolName: "tray.2", accessibilityDescription: "Folio")
        item.button?.target = self
        item.button?.action = #selector(clicked)
    }

    @objc private func clicked() { onClick() }
}

/// Plain AppKit windows hosting SwiftUI, so the tray icon can open them directly (SwiftUI's openWindow needs a live view).
@MainActor
final class WindowManager {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(_ id: String, title: String, size: NSSize, resizable: Bool = true, @ViewBuilder content: () -> Content) {
        let window = windows[id] ?? makeWindow(id, title: title, size: size, resizable: resizable, content: content())
        windows[id] = window
        NSApp.activate(ignoringOtherApps: true) // a tray-only app isn't frontmost, so the window would open behind
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: String) { windows[id]?.close() }

    private func makeWindow<Content: View>(_ id: String, title: String, size: NSSize, resizable: Bool, content: Content) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = NSHostingController(rootView: content)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("folio.\(id)")
        window.center()
        return window
    }
}
