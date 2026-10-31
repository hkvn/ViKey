//
//  MacroSync.swift
//  ViKey
//
//  Keeps the macros in a file in iCloud Drive (or another synced folder), so the Macs of the user share one list.
//  ViKey is not sandboxed, so it uses the iCloud Drive folder like any other folder, without iCloud entitlements.
//
//  The file has the macros, a revision id, and the revision it was made from. Each Mac remembers the last
//  revision it read or wrote, and its macros:
//  - the file was made from our last revision: it has all our changes, it is used (removed macros too)
//  - else (two Macs wrote at the same time, or a Mac starts to sync): the lists are merged. Changes made on
//    this Mac since the last sync win; a macro which only the other side does not have is kept, because the
//    other side may never have seen it
//  - a file which can not be read is never overwritten
//  The file is read and written on a background queue: an iCloud file may have to download first.
//

import AppKit

struct MacroSyncFile: Codable, Equatable {
    struct Macro: Codable, Equatable {
        var text: String
        var content: String
    }
    var revision: String
    /// the revision this one was made from, nil for the first one
    var base: String?
    var macros: [Macro]

    var dictionary: [String: String] {
        Dictionary(macros.map { ($0.text, $0.content) }, uniquingKeysWith: { first, _ in first })
    }
}

enum MacroMerge {
    /// three-way merge of macro lists (text -> content). remoteHasOurChanges: the remote list was made from
    /// `base`, so a macro missing there was removed on purpose
    static func merge(base: [String: String], local: [String: String], remote: [String: String],
                      remoteHasOurChanges: Bool) -> [String: String] {
        var result: [String: String] = [:]
        for text in Set(base.keys).union(local.keys).union(remote.keys) {
            let old = base[text], mine = local[text], theirs = remote[text]
            let value: String?
            if mine == theirs {
                value = mine
            } else if mine == old { //only the other side changed it
                value = theirs == nil && !remoteHasOurChanges ? mine : theirs
            } else { //only this Mac changed it, or both did: this Mac wins
                value = mine
            }
            if let value {
                result[text] = value
            }
        }
        return result
    }
}

@objc final class MacroSync: NSObject, ObservableObject {
    @objc static let shared = MacroSync()

    static let fileName = "ViKey Macros.json"
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

    /// tests and quitting: file work on the calling thread
    var runsSynchronously = false
    private(set) var isBusy = false

    private let defaults: UserDefaults
    private let ioQueue = DispatchQueue(label: "com.hkvn.vikey.macro-sync")
    private var timer: Timer?
    private var pendingWrite: DispatchWorkItem?
    private var needsSync = false
    private var applyingFile = false

    private enum Key {
        static let enabled = "MacroSyncEnabled"
        static let folder = "MacroSyncFolder"
        static let revision = "MacroSyncRevision"
        static let snapshot = "MacroSyncSnapshot"
        static let fileDate = "MacroSyncFileDate"
    }

    private enum ReadResult {
        case missing
        case unreadable(String)
        case file(MacroSyncFile, Date?) //and its modification date when it was read
    }

    private enum WriteResult {
        case written
        case changed //another Mac wrote the file after it was read
        case failed(String)
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
        sync()
        startTimer()
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        defaults.set(on, forKey: Key.enabled)
        if on {
            VKLogger.log("sync on: \(fileURL.path)", category: "sync")
            sync()
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
        //another file: the first sync with it merges both lists
        lastRevision = nil
        snapshot = [:]
        knownFileDate = nil
        if isEnabled {
            VKLogger.log("sync folder: \(url.path)", category: "sync")
            sync()
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

    /// writes a change which is still waiting, when ViKey quits
    @objc func flushPendingWrite() {
        guard pendingWrite != nil, isEnabled else { return }
        let synchronously = runsSynchronously
        runsSynchronously = true
        isBusy = false
        sync()
        runsSynchronously = synchronously
    }

    //MARK: - Sync

    /// the timer: sync when the file changed since the last sync
    func checkFile() {
        guard isEnabled, !isBusy, pendingWrite == nil else { return }
        if let date = fileDate(), isSameDate(date, knownFileDate) {
            return
        }
        sync()
    }

    @objc private func macrosDidChange() {
        guard isEnabled, !applyingFile else { return }
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWrite = nil
            self?.sync()
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDelay, execute: work)
    }

    /// reads the file, merges it with the macros of this Mac, and writes the result when the file needs it
    func sync() {
        guard isEnabled else { return }
        //a waiting local change is part of this sync
        pendingWrite?.cancel()
        pendingWrite = nil
        if isBusy {
            needsSync = true
            return
        }
        if let problem = folderProblem() {
            setError(problem, nil)
            return
        }
        isBusy = true
        let url = fileURL
        perform({ Self.read(url) }) { [weak self] result in
            self?.merge(result)
        }
    }

    private func merge(_ result: ReadResult) {
        let remote: MacroSyncFile?
        var readDate: Date?
        switch result {
        case .unreadable(let message):
            finish(error: message)
            return
        case .missing:
            remote = nil
        case .file(let file, let date):
            remote = file
            readDate = date
        }
        let local = localMacros()
        if let remote, remote.revision == lastRevision, local == snapshot {
            knownFileDate = readDate
            finish(error: nil)
            return
        }
        var merged = local
        if let remote {
            let fromOurs = lastRevision != nil && (remote.revision == lastRevision || remote.base == lastRevision)
            merged = MacroMerge.merge(base: snapshot, local: local, remote: remote.dictionary, remoteHasOurChanges: fromOurs)
        }
        if merged != local {
            VKLogger.log("macros from the file: \(local.count) -> \(merged.count)", category: "sync")
            applyLocal(merged)
        }
        //the engine may refuse some macros (too long)
        let applied = localMacros()
        if let remote, applied == remote.dictionary {
            lastRevision = remote.revision
            snapshot = applied
            knownFileDate = readDate
            finish(error: nil)
            return
        }
        let file = MacroSyncFile(revision: UUID().uuidString, base: remote?.revision ?? lastRevision,
                                 macros: applied.sorted { $0.key < $1.key }.map { MacroSyncFile.Macro(text: $0.key, content: $0.value) })
        let url = fileURL, folder = self.folder
        perform({ Self.write(file, to: url, folder: folder, expectedRevision: remote?.revision) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .written:
                self.lastRevision = file.revision
                self.snapshot = applied
                self.knownFileDate = self.fileDate()
                self.finish(error: nil)
            case .changed:
                self.needsSync = true
                self.finish(error: nil)
            case .failed(let message):
                self.finish(error: message)
            }
        }
    }

    private func finish(error: String?) {
        isBusy = false
        if let error {
            setError(error, nil)
        } else {
            setSyncedStatus()
        }
        if needsSync {
            needsSync = false
            sync()
        }
    }

    //MARK: - File

    private static func read(_ url: URL) -> ReadResult {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            //macOS 13 keeps a file which is only in iCloud as ".name.icloud"
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
            if fileManager.fileExists(atPath: placeholder.path) {
                try? fileManager.startDownloadingUbiquitousItem(at: url)
                return .unreadable("file đang được tải từ iCloud")
            }
            return .missing
        }
        var data: Data?
        var date: Date?
        var readError: Error?
        var coordinatorError: NSError?
        //coordinated, so iCloud Drive does not change the file while ViKey reads it
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            do {
                date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                data = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }
        guard let data else {
            return .unreadable("không đọc được file (\((readError ?? coordinatorError)?.localizedDescription ?? "?"))")
        }
        guard let file = try? JSONDecoder().decode(MacroSyncFile.self, from: data) else {
            return .unreadable("file \(url.lastPathComponent) không đúng định dạng")
        }
        return .file(file, date)
    }

    /// expectedRevision: the revision read before (nil if there was no file); another one means another Mac wrote it
    private static func write(_ file: MacroSyncFile, to url: URL, folder: URL, expectedRevision: String?) -> WriteResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else {
            return .failed("không tạo được file")
        }
        do {
            //only the last folder: a missing parent (iCloud Drive turned off) is an error, not a new folder
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            }
        } catch {
            return .failed("không tạo được thư mục (\(error.localizedDescription))")
        }
        var result = WriteResult.failed("không ghi được file")
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], writingItemAt: url, options: .forReplacing,
                                       error: &coordinatorError) { readURL, writeURL in
            if FileManager.default.fileExists(atPath: readURL.path) {
                let current = (try? Data(contentsOf: readURL)).flatMap { try? JSONDecoder().decode(MacroSyncFile.self, from: $0) }
                if current?.revision != expectedRevision {
                    result = .changed
                    return
                }
            }
            do {
                try data.write(to: writeURL, options: .atomic)
                result = .written
            } catch {
                result = .failed("không ghi được file (\(error.localizedDescription))")
            }
        }
        if let coordinatorError {
            return .failed("không ghi được file (\(coordinatorError.localizedDescription))")
        }
        return result
    }

    //MARK: - Helpers

    /// nil when the folder can be used
    private func folderProblem() -> String? {
        if folder.path.hasPrefix(Self.iCloudDrive.path) && !Self.hasICloudDrive {
            return "iCloud Drive chưa bật trên máy Mac này"
        }
        if !FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path) {
            return "không tìm thấy thư mục \(folder.deletingLastPathComponent().path)"
        }
        return nil
    }

    private func perform<T>(_ work: @escaping () -> T, then: @escaping (T) -> Void) {
        if runsSynchronously {
            then(work())
            return
        }
        ioQueue.async {
            let result = work()
            DispatchQueue.main.async {
                then(result)
            }
        }
    }

    private func localMacros() -> [String: String] {
        Dictionary(VKMacroStore.allMacros().map { ($0.text, $0.content) }, uniquingKeysWith: { first, _ in first })
    }

    private func applyLocal(_ macros: [String: String]) {
        applyingFile = true
        VKMacroStore.addMacros(macros.map { VKMacro(text: $0.key, content: $0.value) }, keepCurrent: false)
        applyingFile = false
    }

    /// the last revision of the file this Mac read or wrote
    private var lastRevision: String? {
        get { defaults.string(forKey: Key.revision) }
        set { defaults.set(newValue, forKey: Key.revision) }
    }

    /// the macros of lastRevision: what changed since then, on each side
    private var snapshot: [String: String] {
        get { defaults.dictionary(forKey: Key.snapshot) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.snapshot) }
    }

    /// modification date of the file after the last sync: the timer reads the file only when it changes
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

    private func fileDate() -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func isSameDate(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        return abs(a.timeIntervalSince(b)) < 0.001
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
