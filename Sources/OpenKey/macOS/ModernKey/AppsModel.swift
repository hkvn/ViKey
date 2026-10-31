//
//  AppsModel.swift
//  ViKey
//
//  Apps in the "Ứng dụng" settings tab: apps which always use English, and the
//  Vietnamese / English mode and code table ViKey remembers for each app.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// an app shown in the list, found by its bundle id
struct AppEntry: Identifiable {
    let bundleId: String
    let name: String
    let icon: NSImage?
    /// false when the app is not on this Mac any more, or was saved by name because it has no bundle id
    let isInstalled: Bool
    var id: String { bundleId }

    /// slow (about 1 ms per app): AppsModel calls it in the background
    init(bundleId: String) {
        self.bundleId = bundleId
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let displayName = FileManager.default.displayName(atPath: url.path)
            name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
            icon = NSWorkspace.shared.icon(forFile: url.path)
            isInstalled = true
        } else {
            name = bundleId
            icon = nil
            isInstalled = false
        }
    }

    /// shown until the name and icon are found
    init(placeholder bundleId: String) {
        self.bundleId = bundleId
        name = bundleId
        icon = nil
        isInstalled = true
    }
}

/// apps already looked up, used on the main thread and on the lookup queue
private enum AppEntryCache {
    private static let lock = NSLock()
    private static var entries: [String: AppEntry] = [:]

    static subscript(bundleId: String) -> AppEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[bundleId]
    }

    static func add(_ entry: AppEntry) {
        lock.lock()
        entries[entry.bundleId] = entry
        lock.unlock()
    }

    /// apps which were not installed: look them up again, they may be installed now
    static func removeUninstalled() {
        lock.lock()
        entries = entries.filter { $0.value.isInstalled }
        lock.unlock()
    }
}

final class AppsModel: ObservableObject {
    @Published private(set) var excludedApps: [AppEntry] = []
    @Published private(set) var rememberedApps: [AppEntry] = []
    /// names and icons of new apps are being looked up
    @Published private(set) var isLoading = false
    /// bundle id -> status (bit 0: Vietnamese, other bits: code table)
    @Published private var statuses: [String: Int] = [:]

    private static let lookupQueue = DispatchQueue(label: "com.hkvn.vikey.apps", qos: .userInitiated)
    private var generation = 0

    init() {
        reload()
        //smart switch changes the remembered modes while the window is open
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange),
                                               name: SettingsWindowController.settingsDidChangeNotification, object: nil)
    }

    @objc private func settingsDidChange() {
        reload()
    }

    /// the lists are shown at once; names and icons not looked up yet follow from the background.
    /// recheckUninstalled: look up again the apps which were not installed
    func reload(recheckUninstalled: Bool = false) {
        if recheckUninstalled {
            AppEntryCache.removeUninstalled()
        }
        statuses = VKAppMemory.allApps().mapValues { $0.intValue }
        showEntries()
        let missing = Set(VKExcludedApps.bundleIds).union(statuses.keys).filter { AppEntryCache[$0] == nil }
        guard !missing.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        generation += 1
        let current = generation
        Self.lookupQueue.async { [weak self] in
            //an earlier reload may have looked them up already
            for bundleId in missing where AppEntryCache[bundleId] == nil {
                AppEntryCache.add(AppEntry(bundleId: bundleId))
            }
            DispatchQueue.main.async {
                guard let self, current == self.generation else { return }
                self.isLoading = false
                self.showEntries()
            }
        }
    }

    private func showEntries() {
        func entry(_ bundleId: String) -> AppEntry {
            AppEntryCache[bundleId] ?? AppEntry(placeholder: bundleId)
        }
        excludedApps = Self.sorted(VKExcludedApps.bundleIds.map(entry))
        rememberedApps = Self.sorted(statuses.keys.map(entry))
    }

    private static func sorted(_ apps: [AppEntry]) -> [AppEntry] {
        apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    //MARK: always English
    func addExcludedApps() {
        let panel = NSOpenPanel()
        panel.message = "Chọn ứng dụng luôn dùng English"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var bundleIds = VKExcludedApps.bundleIds
        for url in panel.urls {
            if let bundleId = Bundle(url: url)?.bundleIdentifier, !bundleIds.contains(bundleId) {
                bundleIds.append(bundleId)
            }
        }
        VKExcludedApps.bundleIds = bundleIds
        reload()
    }

    func removeExcludedApp(_ bundleId: String) {
        VKExcludedApps.bundleIds = VKExcludedApps.bundleIds.filter { $0 != bundleId }
        reload()
    }

    //MARK: remembered apps
    func languageBinding(for bundleId: String) -> Binding<Int> {
        Binding(get: { (self.statuses[bundleId] ?? 0) & 1 },
                set: { self.setStatus((self.currentStatus(bundleId) & ~1) | $0, for: bundleId) })
    }

    func codeTableBinding(for bundleId: String) -> Binding<Int> {
        Binding(get: { (self.statuses[bundleId] ?? 0) >> 1 },
                set: { self.setStatus((self.currentStatus(bundleId) & 1) | ($0 << 1), for: bundleId) })
    }

    /// from the engine, not the list: smart switch may have changed it since the list was read
    private func currentStatus(_ bundleId: String) -> Int {
        let status = VKAppMemory.status(forApp: bundleId)
        return status >= 0 ? status : (statuses[bundleId] ?? 0)
    }

    private func setStatus(_ status: Int, for bundleId: String) {
        VKAppMemory.setStatus(Int32(status), forApp: bundleId)
        statuses[bundleId] = status
    }

    func forget(_ bundleId: String) {
        VKAppMemory.removeApp(bundleId)
        reload()
    }

    /// remembered apps which are not on this Mac any more
    var uninstalledApps: [AppEntry] {
        isLoading ? [] : rememberedApps.filter { !$0.isInstalled }
    }

    func forgetUninstalledApps() {
        for app in uninstalledApps {
            VKAppMemory.removeApp(app.bundleId)
        }
        reload()
    }

    func forgetAll() {
        VKAppMemory.removeAllApps()
        reload()
    }
}
