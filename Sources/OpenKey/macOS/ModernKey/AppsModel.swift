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
    var id: String { bundleId }

    init(bundleId: String) {
        self.bundleId = bundleId
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let displayName = FileManager.default.displayName(atPath: url.path)
            name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            //not installed any more, or saved by name when the app has no bundle id
            name = bundleId
            icon = nil
        }
    }
}

final class AppsModel: ObservableObject {
    @Published private(set) var excludedApps: [AppEntry] = []
    @Published private(set) var rememberedApps: [AppEntry] = []
    /// bundle id -> status (bit 0: Vietnamese, other bits: code table)
    @Published private var statuses: [String: Int] = [:]

    init() {
        reload()
    }

    func reload() {
        excludedApps = Self.sorted(VKExcludedApps.bundleIds.map(AppEntry.init))
        statuses = VKAppMemory.allApps().mapValues { $0.intValue }
        rememberedApps = Self.sorted(statuses.keys.map(AppEntry.init))
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
                set: { self.setStatus(((self.statuses[bundleId] ?? 0) & ~1) | $0, for: bundleId) })
    }

    func codeTableBinding(for bundleId: String) -> Binding<Int> {
        Binding(get: { (self.statuses[bundleId] ?? 0) >> 1 },
                set: { self.setStatus(((self.statuses[bundleId] ?? 0) & 1) | ($0 << 1), for: bundleId) })
    }

    private func setStatus(_ status: Int, for bundleId: String) {
        VKAppMemory.setStatus(Int32(status), forApp: bundleId)
        statuses[bundleId] = status
    }

    func forget(_ bundleId: String) {
        VKAppMemory.removeApp(bundleId)
        reload()
    }

    func forgetAll() {
        VKAppMemory.removeAllApps()
        reload()
    }
}
