//
//  MacroSync.swift
//  ViKey
//
//  Keeps the macros in a text file in iCloud Drive (or another synced folder), so the Macs of the user share one list.
//  ViKey is not sandboxed, so it uses the iCloud Drive folder like any other folder, without iCloud entitlements.
//
//  - turning sync on keeps the macros of both sides (the ones of this Mac win)
//  - a change on this Mac is written to the file after a short delay
//  - a change of the file (by another Mac) replaces the macros of this Mac
//  - when both changed, the macros of both sides are kept
//

import AppKit

@objc final class MacroSync: NSObject, ObservableObject {
    @objc static let shared = MacroSync()

    static let fileName = "ViKey Macros.txt"
    static let checkInterval: TimeInterval = 10
    static let writeDelay: TimeInterval = 1

    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static var hasICloudDrive: Bool {
        FileManager.default.fileExists(atPath: iCloudDrive.path)
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var folder: URL
    @Published private(set) var status = ""

    private let defaults: UserDefaults
    private var timer: Timer?
    private var pendingWrite: DispatchWorkItem?
    private var applyingFile = false

    private enum Key {
        static let enabled = "MacroSyncEnabled"
        static let folder = "MacroSyncFolder"
        /// modification date of the file when ViKey read or wrote it last
        static let fileDate = "MacroSyncFileDate"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        if let path = defaults.string(forKey: Key.folder) {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folder = Self.iCloudDrive.appendingPathComponent("ViKey", isDirectory: true)
        }
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(macrosDidChange),
                                               name: .VKMacroStoreDidChange, object: nil)
    }

    var fileURL: URL {
        folder.appendingPathComponent(Self.fileName)
    }

    /// "iCloud Drive/ViKey" or "~/Dropbox/ViKey"
    var folderDisplayName: String {
        let iCloud = Self.iCloudDrive.path
        if folder.path.hasPrefix(iCloud) {
            return "iCloud Drive" + folder.path.dropFirst(iCloud.count)
        }
        return (folder.path as NSString).abbreviatingWithTildeInPath
    }

    //MARK: - Actions

    /// called once the engine has loaded the macros
    @objc func start() {
        guard isEnabled else { return }
        //the file may have changed while ViKey was not running
        checkFile()
        startTimer()
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        defaults.set(on, forKey: Key.enabled)
        if on {
            VKLogger.log("sync on: \(fileURL.path)", category: "sync")
            mergeAndWrite()
            startTimer()
        } else {
            VKLogger.log("sync off", category: "sync")
            timer?.invalidate()
            timer = nil
            pendingWrite?.cancel()
            pendingWrite = nil
            status = ""
        }
    }

    func setFolder(_ url: URL) {
        folder = url
        defaults.set(url.path, forKey: Key.folder)
        knownFileDate = nil
        if isEnabled {
            VKLogger.log("sync folder: \(url.path)", category: "sync")
            mergeAndWrite()
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.message = "Chọn thư mục đồng bộ, ví dụ một thư mục trong iCloud Drive, Dropbox hoặc Google Drive"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = Self.hasICloudDrive ? Self.iCloudDrive : nil
        if panel.runModal() == .OK, let url = panel.url {
            setFolder(url)
        }
    }

    /// writes a change which is still waiting, such as when ViKey quits
    @objc func flushPendingWrite() {
        guard let work = pendingWrite else { return }
        work.cancel()
        pendingWrite = nil
        writeChanges()
    }

    //MARK: - Sync

    /// first sync with this file: keep the macros of both sides
    func mergeAndWrite() {
        if let entries = readFile() {
            apply(entries, keepCurrent: true)
        }
        writeFile()
    }

    /// another Mac changed the file: use its macros
    func checkFile() {
        guard isEnabled, pendingWrite == nil else { return }
        guard let date = fileDate() else {
            //no file yet, or it was removed: write it
            writeFile()
            return
        }
        guard !isSameDate(date, knownFileDate) else { return }
        guard let entries = readFile() else { return }
        //an empty file is more likely a broken copy than a wish to remove every macro
        if entries.isEmpty && !VKMacroStore.allMacros().isEmpty {
            VKLogger.log("file changed but has no macros: keep the macros of this Mac", category: "sync")
            return
        }
        VKLogger.log("file changed: \(entries.count) macros", category: "sync")
        apply(entries, keepCurrent: false)
        setSyncedStatus()
    }

    @objc private func macrosDidChange() {
        guard isEnabled, !applyingFile else { return }
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWrite = nil
            self?.writeChanges()
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDelay, execute: work)
    }

    /// the macros of this Mac changed: write them; when the file also changed, keep the macros of both
    func writeChanges() {
        if let date = fileDate(), !isSameDate(date, knownFileDate), let entries = readFile() {
            VKLogger.log("both changed: keep the macros of both", category: "sync")
            apply(entries, keepCurrent: true)
        }
        writeFile()
    }

    //MARK: - Helpers

    private var knownFileDate: Date? {
        get { defaults.object(forKey: Key.fileDate) as? Date }
        set { defaults.set(newValue, forKey: Key.fileDate) }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkFile()
        }
        timer.tolerance = Self.checkInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func apply(_ entries: [MacroFile.Entry], keepCurrent: Bool) {
        applyingFile = true
        VKMacroStore.addMacros(entries.map { VKMacro(text: $0.text, content: $0.content) }, keepCurrent: keepCurrent)
        applyingFile = false
    }

    private func fileDate() -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func isSameDate(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        return abs(a.timeIntervalSince(b)) < 0.001
    }

    /// nil if there is no file or it can not be read
    private func readFile() -> [MacroFile.Entry]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        var data: Data?
        var coordinatorError: NSError?
        //coordinated, so iCloud Drive does not change the file while ViKey reads it
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinatorError) { url in
            data = try? Data(contentsOf: url)
        }
        guard let data else {
            setError("không đọc được file", coordinatorError)
            return nil
        }
        knownFileDate = fileDate()
        return MacroFile.read(data)
    }

    private func writeFile() {
        let entries = VKMacroStore.allMacros().map { MacroFile.Entry(text: $0.text, content: $0.content) }
        let data = Data(MacroFile.text(of: entries).utf8)
        var writeError: Error?
        var coordinatorError: NSError?
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { url in
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    writeError = error
                }
            }
        } catch {
            writeError = error
        }
        if let error = writeError ?? coordinatorError {
            setError("không ghi được file", error)
            return
        }
        knownFileDate = fileDate()
        setSyncedStatus()
    }

    private func setSyncedStatus() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        status = "Đã đồng bộ lúc \(formatter.string(from: Date()))"
    }

    private func setError(_ message: String, _ error: Error?) {
        status = "Lỗi: \(message)" + (error.map { " (\($0.localizedDescription))" } ?? "")
        VKLogger.log("\(message): \(error?.localizedDescription ?? "-")", category: "sync")
    }
}
