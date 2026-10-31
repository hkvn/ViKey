//
//  SettingsModelTests.swift
//  ViKey
//
//  The settings model must save the same values as the old settings window did.
//  Run with scripts/run-tests.sh
//

import Foundation

var checks = 0
var failures = 0

func check(_ name: String, _ ok: Bool) {
    checks += 1
    if !ok {
        failures += 1
        print("FAIL  \(name)")
    }
}

@main
struct SettingsModelTests {
    static func main() {
        let suiteName = "vikey.settings.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        //same start state as the engine
        defaults.set(1, forKey: "Spelling")
        vCheckSpelling = 1
        vSwitchKeyStatus = 0
        let model = SettingsModel(defaults: defaults)

        //hotkey, see Engine.h: low byte key code, 0x100 control, 0x200 option, 0x400 command, 0x800 shift, 0x8000 beep, high byte character
        model.switchKeyBinding(.option).wrappedValue = true
        model.setSwitchKey(keyCode: 6, character: 0x7A)
        check("option + z is 0x7A000206 (the default hotkey)", vSwitchKeyStatus == 0x7A000206)
        check("hotkey is saved", defaults.integer(forKey: "SwitchKeyStatus") == 0x7A000206)
        check("title of z is Z", model.switchKeyTitle == "Z")

        model.switchKeyBinding(.beep).wrappedValue = true
        check("beep sets 0x8000 and keeps the key", vSwitchKeyStatus & 0x8000 != 0 && vSwitchKeyStatus & 0xFF == 6)
        model.switchKeyBinding(.beep).wrappedValue = false
        check("beep off clears 0x8000", vSwitchKeyStatus & 0x8000 == 0)

        model.switchKeyBinding(.control).wrappedValue = true
        model.switchKeyBinding(.shift).wrappedValue = true
        model.setSwitchKey(keyCode: HotKey.noKey, character: HotKey.noKey)
        check("control + option + shift, no key is 0xFE000BFE", UInt32(bitPattern: vSwitchKeyStatus) == 0xFE000BFE)
        check("title of no key", model.switchKeyTitle == "Không")
        model.setSwitchKey(keyCode: 49, character: 49)
        check("space key", model.switchKeyTitle == "Space" && vSwitchKeyStatus & 0xFF == 49)

        //"check update on startup" is saved inverted as DontCheckUpdate
        model.binding(.checkUpdateOnStartup).wrappedValue = false
        check("check update off saves DontCheckUpdate = 1", defaults.integer(forKey: "DontCheckUpdate") == 1)
        model.binding(.checkUpdateOnStartup).wrappedValue = true
        check("check update on saves DontCheckUpdate = 0", defaults.integer(forKey: "DontCheckUpdate") == 0)

        //a normal option is saved and applied to the engine
        model.binding(.checkSpelling).wrappedValue = false
        check("spelling off", defaults.integer(forKey: "Spelling") == 0 && vCheckSpelling == 0)
        model.binding(.checkSpelling).wrappedValue = true
        check("spelling on", defaults.integer(forKey: "Spelling") == 1 && vCheckSpelling == 1)
        model.binding(.quickTelex).wrappedValue = true
        check("quick telex on", defaults.integer(forKey: "QuickTelex") == 1 && vQuickTelex == 1)

        //reload reads saved values but does not apply them
        defaults.set(0, forKey: "Spelling")
        model.reload()
        check("reload reads the saved value", model[.checkSpelling] == false)
        check("reload does not change the engine", vCheckSpelling == 1)

        //per-app memory, status bit 0: Vietnamese, other bits: code table
        VKAppMemory.removeAllApps()
        VKAppMemory.setStatus(1, forApp: "com.apple.TextEdit")
        let apps = AppsModel()
        check("remembered app is listed", apps.rememberedApps.map(\.bundleId) == ["com.apple.TextEdit"])
        func waitForLookup() {
            let timeout = Date().addingTimeInterval(5)
            while apps.isLoading && Date() < timeout {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        waitForLookup()
        check("app name is looked up in the background", !apps.isLoading && apps.rememberedApps.first?.name != "com.apple.TextEdit"
              && apps.rememberedApps.first?.isInstalled == true)
        VKAppMemory.setStatus(1, forApp: "com.example.removed")
        apps.reload()
        waitForLookup()
        check("app which is not installed", apps.uninstalledApps.map(\.bundleId) == ["com.example.removed"])
        apps.forgetUninstalledApps()
        check("forget apps which are not installed", apps.rememberedApps.map(\.bundleId) == ["com.apple.TextEdit"])
        check("app mode is Vietnamese", apps.languageBinding(for: "com.apple.TextEdit").wrappedValue == 1)
        apps.codeTableBinding(for: "com.apple.TextEdit").wrappedValue = 2
        check("code table keeps the mode", VKAppMemory.allApps()["com.apple.TextEdit"]?.intValue == 1 | 2 << 1)
        apps.languageBinding(for: "com.apple.TextEdit").wrappedValue = 0
        check("mode keeps the code table", VKAppMemory.allApps()["com.apple.TextEdit"]?.intValue == 2 << 1)
        VKAppMemory.setStatus(0 | 2 << 1, forApp: "com.apple.TextEdit") //smart switch changes it while the list is shown
        apps.codeTableBinding(for: "com.apple.TextEdit").wrappedValue = 1
        check("a change starts from the status in the engine", VKAppMemory.status(forApp: "com.apple.TextEdit") == 1 << 1)
        apps.forget("com.apple.TextEdit")
        check("forgotten app", apps.rememberedApps.isEmpty && VKAppMemory.allApps().isEmpty)

        //hotkey helper shared with the convert tool
        check("hotkey with no key and no modifier", HotKey.title(of: Int32(bitPattern: 0xFE0000FE)) == "Không")
        check("hotkey never set", HotKey.title(of: 0) == "Không")
        check("the key 1 is not Space", HotKey.title(of: Int32(0x31 << 24 | 0x0B00 | 18)) == "1")
        check("hotkey option flag", HotKey.with(.option, on: true, in: 0) == 0x200 && HotKey.with(.option, on: false, in: 0x200) == 0)

        testMacroFile()
        testMacroSync(defaults: defaults)
        testMergeRules()

        defaults.removePersistentDomain(forName: suiteName)
        print("settings: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    //macro files of UniKey, EVKey, OpenKey and the macOS text replacements
    static func testMacroFile() {
        let unikey = ";DO NOT DELETE THIS LINE*** version=1 ***\r\nvn:Việt Nam\r\n:):☺\r\nno colon\r\nk:a:b\r\n"
        let expected = [MacroFile.Entry(text: "vn", content: "Việt Nam"), .init(text: ":)", content: "☺"), .init(text: "k", content: "a:b")]
        check("UniKey file", MacroFile.read(Data(unikey.utf8)) == expected)
        check("UTF-8 file with a BOM", MacroFile.read(Data([0xEF, 0xBB, 0xBF]) + Data(unikey.utf8)) == expected)
        check("UTF-16 file with a BOM", MacroFile.read(Data([0xFF, 0xFE]) + unikey.data(using: .utf16LittleEndian)!) == expected)
        check("UTF-16 file without a BOM", MacroFile.read(unikey.data(using: .utf16LittleEndian)!) == expected)
        check("file without a header keeps the first line", MacroFile.read(Data("a:b\nc:d".utf8)).count == 2)
        check("ASCII UTF-16 file without a BOM", MacroFile.read("vk:ViKey\r\n".data(using: .utf16LittleEndian)!) == [.init(text: "vk", content: "ViKey")])

        let plist = try! PropertyListSerialization.data(fromPropertyList: [["shortcut": "omw", "phrase": "On my way!"], ["phrase": "no shortcut"]],
                                                        format: .xml, options: 0)
        check("macOS text replacements", MacroFile.read(plist) == [.init(text: "omw", content: "On my way!")])

        let written = MacroFile.text(of: expected)
        check("written file starts with the UniKey header", written.hasPrefix(MacroFile.header + "\n"))
        check("written file is read back", MacroFile.read(Data(written.utf8)) == expected)
        check("line breaks become spaces", MacroFile.text(of: [.init(text: "a", content: "x\ny")]).contains("\na:x y\n"))
    }

    //macro sync through a file in a synced folder. Two Macs: two MacroSync objects with their own settings;
    //the engine has one macro list, so each step first puts in it the macros of the Mac which acts
    static func testMacroSync(defaults: UserDefaults) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vikey-sync-tests-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent(MacroSync.fileName)

        func macros() -> [String: String] {
            Dictionary(VKMacroStore.allMacros().map { ($0.text, $0.content) }, uniquingKeysWith: { first, _ in first })
        }
        func setMacros(_ list: [String: String]) {
            VKMacroStore.addMacros(list.map { VKMacro(text: $0.key, content: $0.value) }, keepCurrent: false)
        }
        func file() -> MacroSyncFile? {
            (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(MacroSyncFile.self, from: $0) }
        }
        func mac(_ name: String) -> (MacroSync, UserDefaults) {
            let suite = "vikey.sync.tests.\(name)"
            let macDefaults = UserDefaults(suiteName: suite)!
            macDefaults.removePersistentDomain(forName: suite)
            let sync = MacroSync(defaults: macDefaults)
            sync.runsSynchronously = true
            sync.setFolder(folder)
            return (sync, macDefaults)
        }
        let (macA, defaultsA) = mac("a")
        let (macB, defaultsB) = mac("b")
        defer {
            macA.setEnabled(false)
            macB.setEnabled(false)
            defaultsA.removePersistentDomain(forName: "vikey.sync.tests.a")
            defaultsB.removePersistentDomain(forName: "vikey.sync.tests.b")
            setMacros([:])
        }

        //Mac A turns sync on: there is no file yet
        setMacros(["a": "from A"])
        macA.setEnabled(true)
        check("first Mac writes the file", file()?.dictionary == ["a": "from A"] && file()?.base == nil)
        var listA = macros()

        //Mac B turns sync on: both lists are kept
        setMacros(["b": "from B", "a": "B's a"])
        macB.setEnabled(true)
        check("second Mac keeps both lists, its own change wins", macros() == ["a": "B's a", "b": "from B"])
        check("second Mac writes the merged list", file()?.dictionary == macros())
        var listB = macros()

        //Mac A sees the file made from its revision: it uses it
        setMacros(listA)
        macA.sync()
        check("first Mac gets the merged list", macros() == listB)

        //a macro removed on A is removed on B
        VKMacroStore.deleteMacro("b")
        macA.sync()
        listA = macros()
        setMacros(listB)
        macB.sync()
        check("a removed macro is removed on the other Mac", macros() == ["a": "B's a"])
        listB = macros()

        //both change at the same time: both changes are kept
        setMacros(listA)
        VKMacroStore.setMacro("c", content: "from A")
        macA.sync()
        listA = macros()
        setMacros(listB)
        VKMacroStore.setMacro("d", content: "from B")
        macB.sync()
        check("changes of both Macs are kept", macros().keys.sorted() == ["a", "c", "d"] && file()?.dictionary == macros())
        listB = macros()

        //a Mac which writes without having seen the file (it was not downloaded yet) does not remove the macros of the other
        let (macC, defaultsC) = mac("c")
        defer { macC.setEnabled(false); defaultsC.removePersistentDomain(forName: "vikey.sync.tests.c") }
        try! FileManager.default.removeItem(at: fileURL)
        setMacros(["e": "from C"])
        macC.setEnabled(true)
        check("new Mac wrote only its list", file()?.dictionary == ["e": "from C"])
        setMacros(listA)
        macA.sync()
        check("macros missing in a file which was not made from ours are kept", Set(macros().keys) == ["a", "c", "e"])
        listA = macros()
        setMacros(listB)
        macB.sync()
        check("nothing is lost: the other Mac brings back its macros", Set(macros().keys) == ["a", "c", "d", "e"]
              && file()?.dictionary == macros())
        setMacros(listA)

        //a file which can not be read is not overwritten
        try! Data("not json".utf8).write(to: fileURL)
        VKMacroStore.setMacro("f", content: "new")
        macA.sync()
        check("a broken file is not overwritten", (try? String(contentsOf: fileURL)) == "not json")
        check("the error is shown", macA.status.hasPrefix("Lỗi"))

        //names with ":" and line breaks keep their text
        try! FileManager.default.removeItem(at: fileURL)
        setMacros(["a:b": "x\ny"])
        macA.sync()
        check("names with a colon and contents with line breaks", file()?.dictionary == ["a:b": "x\ny"])
    }

    static func testMergeRules() {
        let base = ["kept": "1", "removed": "1", "changed": "1"]
        let local = ["kept": "1", "removed": "1", "changed": "1", "mine": "1"]
        let remote = ["kept": "1", "changed": "2", "theirs": "1"]
        check("merge with a file made from ours", MacroMerge.merge(base: base, local: local, remote: remote, remoteHasOurChanges: true)
              == ["kept": "1", "changed": "2", "mine": "1", "theirs": "1"])
        check("merge with another file keeps what it does not have", MacroMerge.merge(base: base, local: local, remote: remote, remoteHasOurChanges: false)
              == ["kept": "1", "removed": "1", "changed": "2", "mine": "1", "theirs": "1"])
        check("this Mac wins when both changed", MacroMerge.merge(base: ["x": "1"], local: ["x": "mine"], remote: ["x": "theirs"], remoteHasOurChanges: true)
              == ["x": "mine"])
    }
}
