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
        check("app mode is Vietnamese", apps.languageBinding(for: "com.apple.TextEdit").wrappedValue == 1)
        apps.codeTableBinding(for: "com.apple.TextEdit").wrappedValue = 2
        check("code table keeps the mode", VKAppMemory.allApps()["com.apple.TextEdit"]?.intValue == 1 | 2 << 1)
        apps.languageBinding(for: "com.apple.TextEdit").wrappedValue = 0
        check("mode keeps the code table", VKAppMemory.allApps()["com.apple.TextEdit"]?.intValue == 2 << 1)
        apps.forget("com.apple.TextEdit")
        check("forgotten app", apps.rememberedApps.isEmpty && VKAppMemory.allApps().isEmpty)

        //hotkey helper shared with the convert tool
        check("hotkey with no key and no modifier", HotKey.title(of: Int32(bitPattern: 0xFE0000FE)) == "Không")
        check("hotkey never set", HotKey.title(of: 0) == "Không")
        check("hotkey option flag", HotKey.with(.option, on: true, in: 0) == 0x200 && HotKey.with(.option, on: false, in: 0x200) == 0)

        testMacroFile()
        testMacroSync(defaults: defaults)

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

        let plist = try! PropertyListSerialization.data(fromPropertyList: [["shortcut": "omw", "phrase": "On my way!"], ["phrase": "no shortcut"]],
                                                        format: .xml, options: 0)
        check("macOS text replacements", MacroFile.read(plist) == [.init(text: "omw", content: "On my way!")])

        let written = MacroFile.text(of: expected)
        check("written file starts with the UniKey header", written.hasPrefix(MacroFile.header + "\n"))
        check("written file is read back", MacroFile.read(Data(written.utf8)) == expected)
        check("line breaks become spaces", MacroFile.text(of: [.init(text: "a", content: "x\ny")]).contains("\na:x y\n"))
    }

    //macro sync through a file in a synced folder
    static func testMacroSync(defaults: UserDefaults) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vikey-sync-tests-\(getpid())", isDirectory: true)
        let fileURL = folder.appendingPathComponent(MacroSync.fileName)
        try? FileManager.default.removeItem(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }

        func macros() -> [String: String] {
            Dictionary(VKMacroStore.allMacros().map { ($0.text, $0.content) }, uniquingKeysWith: { first, _ in first })
        }
        func fileTexts() -> Set<String> {
            Set(MacroFile.read((try? Data(contentsOf: fileURL)) ?? Data()).map(\.text))
        }
        //another Mac writes the file
        func writeFile(_ entries: [MacroFile.Entry], date: Date) {
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try! Data((entries.isEmpty ? "" : MacroFile.text(of: entries)).utf8).write(to: fileURL)
            try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
        }

        VKMacroStore.addMacros([VKMacro(text: "a", content: "this Mac")], keepCurrent: false)
        writeFile([.init(text: "a", content: "other Mac"), .init(text: "b", content: "other Mac")], date: Date(timeIntervalSinceNow: -100))
        let sync = MacroSync(defaults: defaults)
        sync.setFolder(folder)
        sync.setEnabled(true)
        check("turning sync on keeps both sides, this Mac wins", macros() == ["a": "this Mac", "b": "other Mac"])
        check("turning sync on writes the file", fileTexts() == ["a", "b"])

        writeFile([.init(text: "c", content: "changed")], date: Date(timeIntervalSinceNow: 100))
        sync.checkFile()
        check("a changed file replaces the macros", macros() == ["c": "changed"])

        VKMacroStore.setMacro("d", content: "new")
        sync.flushPendingWrite()
        check("a change of this Mac is written", fileTexts() == ["c", "d"])

        writeFile([.init(text: "e", content: "other Mac")], date: Date(timeIntervalSinceNow: 200))
        VKMacroStore.setMacro("f", content: "new")
        sync.flushPendingWrite()
        check("when both changed, both are kept", macros().keys.sorted() == ["c", "d", "e", "f"] && fileTexts() == ["c", "d", "e", "f"])

        writeFile([], date: Date(timeIntervalSinceNow: 300))
        sync.checkFile()
        check("an empty file does not remove the macros", macros().count == 4)

        sync.setEnabled(false)
        VKMacroStore.addMacros([], keepCurrent: false)
    }
}
