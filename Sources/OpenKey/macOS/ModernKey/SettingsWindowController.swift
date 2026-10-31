//
//  SettingsWindowController.swift
//  OpenKey
//
//  Settings window with toolbar tabs, like the settings of other Mac apps.
//

import AppKit
import SwiftUI

extension NSWindowController {
    /// ViKey is a menu bar app: bring it to the front so the window is not behind other apps.
    /// On macOS 14+ the system may ignore NSApp.activate() when it is called from the menu bar menu
    /// (cooperative activation, FB13212424): the window then opens behind the frontmost app.
    /// The old call still activates the app, and orderFrontRegardless shows the window even if it does not
    func showInFront() {
        window?.collectionBehavior.insert(.moveToActiveSpace)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

@objc final class SettingsWindowController: NSWindowController {
    /// posted when settings change outside the settings window (menu bar, smart switch,...)
    @objc static let settingsDidChangeNotification = Notification.Name("OpenKeySettingsDidChange")

    @objc static let aboutTab = 5

    private let model = SettingsModel()
    private let apps = AppsModel()
    private let tabs = NSTabViewController()

    @objc convenience init() {
        self.init(window: nil)

        tabs.tabStyle = .toolbar
        addTab(TypingSettingsView(model: model), title: "Bộ gõ", symbol: "keyboard")
        addTab(SpellingSettingsView(model: model), title: "Chính tả", symbol: "textformat.abc")
        addTab(MacroSettingsView(model: model), title: "Gõ tắt", symbol: "text.badge.plus")
        addTab(AppsSettingsView(apps: apps), title: "Ứng dụng", symbol: "square.grid.2x2")
        addTab(SystemSettingsView(model: model), title: "Hệ thống", symbol: "gearshape")
        addTab(AboutSettingsView(), title: "Giới thiệu", symbol: "info.circle")

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    private func addTab<Content: View>(_ view: Content, title: String, symbol: String) {
        let controller = NSHostingController(rootView: view)
        controller.title = title
        //the window takes the height of the selected tab
        controller.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }

    @objc func show(tab: Int) {
        tabs.selectedTabViewItemIndex = tab
        show()
    }

    @objc func show() {
        model.reload()
        apps.reload()
        showInFront()
    }
}
