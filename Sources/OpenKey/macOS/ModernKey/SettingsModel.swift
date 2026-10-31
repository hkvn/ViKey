//
//  SettingsModel.swift
//  OpenKey
//
//  Settings shown in the settings window. Values are saved in NSUserDefaults
//  with the same keys as before and applied to the engine at once.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A yes/no option, saved in NSUserDefaults under its raw value.
enum Option: String, CaseIterable {
    //typing
    case checkSpelling = "Spelling"
    case restoreIfWrongSpelling = "RestoreIfInvalidWord"
    case allowConsonantZFWJ = "vAllowConsonantZFWJ"
    case tempOffSpelling = "vTempOffSpelling"
    case modernOrthography = "ModernOrthography"
    case upperCaseFirstChar = "UpperCaseFirstChar"
    case tempOffOpenKey = "vTempOffOpenKey"
    case smartSwitchKey = "UseSmartSwitchKey"
    case rememberCode = "vRememberCode"
    case otherLanguage = "vOtherLanguage"
    //macro
    case useMacro = "UseMacro"
    case useMacroInEnglishMode = "UseMacroInEnglishMode"
    case autoCapsMacro = "vAutoCapsMacro"
    case quickTelex = "QuickTelex"
    case quickStartConsonant = "vQuickStartConsonant"
    case quickEndConsonant = "vQuickEndConsonant"
    //system
    case runOnStartup = "RunOnStartup"
    case showUIOnStartup = "ShowUIOnStartup"
    case checkUpdateOnStartup = "DontCheckUpdate"
    case grayIcon = "GrayIcon"
    case showIconOnDock = "vShowIconOnDock"
    case fixRecommendBrowser = "FixRecommendBrowser"
    case fixChromiumBrowser = "vFixChromiumBrowser"
    case sendKeyStepByStep = "SendKeyStepByStep"
    case performLayoutCompat = "vPerformLayoutCompat"

    /// saved as 1 when the option is off
    var isInverted: Bool { self == .checkUpdateOnStartup }

    /// apply the new value to the engine and the app
    func apply(_ on: Bool) {
        let value: Int32 = on ? 1 : 0
        switch self {
        case .checkSpelling:
            vCheckSpelling = value
            OnSpellCheckingChanged()
        case .restoreIfWrongSpelling: vRestoreIfWrongSpelling = value
        case .allowConsonantZFWJ: vAllowConsonantZFWJ = value
        case .tempOffSpelling: vTempOffSpelling = value
        case .modernOrthography: vUseModernOrthography = value
        case .upperCaseFirstChar: vUpperCaseFirstChar = value
        case .tempOffOpenKey: vTempOffOpenKey = value
        case .smartSwitchKey: vUseSmartSwitchKey = value
        case .rememberCode: vRememberCode = value
        case .otherLanguage: vOtherLanguage = value
        case .useMacro: vUseMacro = value
        case .useMacroInEnglishMode: vUseMacroInEnglishMode = value
        case .autoCapsMacro: vAutoCapsMacro = value
        case .quickTelex: vQuickTelex = value
        case .quickStartConsonant: vQuickStartConsonant = value
        case .quickEndConsonant: vQuickEndConsonant = value
        case .runOnStartup: appDelegate?.setRunOnStartup(on)
        case .showUIOnStartup, .checkUpdateOnStartup: break
        case .grayIcon: appDelegate?.setGrayIcon(on)
        case .showIconOnDock:
            vShowIconOnDock = value
            appDelegate?.showIcon(onDock: on)
        case .fixRecommendBrowser: vFixRecommendBrowser = value
        case .fixChromiumBrowser: vFixChromiumBrowser = value
        case .sendKeyStepByStep: vSendKeyStepByStep = value
        case .performLayoutCompat: vPerformLayoutCompat = value
        }
    }
}

/// Bits of a hotkey (vSwitchKeyStatus, convertToolHotKey), see Engine.h
enum SwitchKeyFlag: Int32 {
    case control = 0x100
    case option = 0x200
    case command = 0x400
    case shift = 0x800
    case beep = 0x8000
}

/// A hotkey value: low byte key code, high byte character of the key (for display), middle bits SwitchKeyFlag
enum HotKey {
    /// key code saved when the hotkey uses modifier keys only
    static let noKey: UInt16 = 0xFE

    static func with(_ flag: SwitchKeyFlag, on: Bool, in status: Int32) -> Int32 {
        on ? status | flag.rawValue : status & ~flag.rawValue
    }

    static func with(keyCode: UInt16, character: UInt16, in status: Int32) -> Int32 {
        var value = UInt32(bitPattern: status)
        value &= 0x00FFFF00
        value |= UInt32(keyCode & 0xFF)
        value |= UInt32(character & 0xFF) << 24
        return Int32(bitPattern: value)
    }

    static func title(of status: Int32) -> String {
        let character = UInt16((UInt32(bitPattern: status) >> 24) & 0xFF)
        if character == noKey || character == 0 {
            return "Không"
        }
        if character == UInt16(kVK_Space) {
            return "Space"
        }
        guard let scalar = UnicodeScalar(character) else { return "?" }
        return String(Character(scalar)).uppercased()
    }
}

final class SettingsModel: ObservableObject {
    static let inputTypes = ["Telex", "VNI", "Simple Telex 1", "Simple Telex 2"]

    @Published private var options: [Option: Bool] = [:]
    @Published private(set) var language = 1
    @Published private(set) var inputType = 0
    @Published private(set) var codeTable = 0
    @Published private(set) var switchKeyStatus: Int32 = 0

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    /// tests pass their own defaults, so they do not touch the user's settings
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
        //the menu bar can change settings too
        observer = NotificationCenter.default.addObserver(forName: SettingsWindowController.settingsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// read all values again, without applying them
    func reload() {
        var values: [Option: Bool] = [:]
        for option in Option.allCases {
            let saved = defaults.integer(forKey: option.rawValue) != 0
            values[option] = option.isInverted ? !saved : saved
        }
        options = values
        language = defaults.integer(forKey: "InputMethod")
        inputType = defaults.integer(forKey: "InputType")
        codeTable = defaults.integer(forKey: "CodeTable")
        switchKeyStatus = vSwitchKeyStatus
    }

    subscript(option: Option) -> Bool {
        options[option] ?? false
    }

    func binding(_ option: Option) -> Binding<Bool> {
        Binding(get: { self[option] }, set: { self.set(option, $0) })
    }

    private func set(_ option: Option, _ on: Bool) {
        guard self[option] != on else { return }
        options[option] = on
        defaults.set(on != option.isInverted ? 1 : 0, forKey: option.rawValue)
        option.apply(on)
    }

    //MARK: input method, input type, code table
    var languageBinding: Binding<Int> {
        Binding(get: { self.language }, set: { value in
            guard value != self.language else { return }
            appDelegate?.onInputMethodSelected() //toggles the input method
        })
    }

    var inputTypeBinding: Binding<Int> {
        Binding(get: { self.inputType }, set: { value in
            guard value != self.inputType else { return }
            appDelegate?.onInputTypeSelectedIndex(Int32(value))
        })
    }

    var codeTableBinding: Binding<Int> {
        Binding(get: { self.codeTable }, set: { value in
            guard value != self.codeTable else { return }
            appDelegate?.onCodeTableChanged(Int32(value))
        })
    }

    //MARK: hotkey to switch Vietnamese / English
    func switchKeyBinding(_ flag: SwitchKeyFlag) -> Binding<Bool> {
        Binding(get: { self.switchKeyStatus & flag.rawValue != 0 }, set: { on in
            self.saveSwitchKeyStatus(HotKey.with(flag, on: on, in: self.switchKeyStatus))
        })
    }

    var switchKeyStatusBinding: Binding<Int32> {
        Binding(get: { self.switchKeyStatus }, set: { self.saveSwitchKeyStatus($0) })
    }

    func setSwitchKey(keyCode: UInt16, character: UInt16) {
        saveSwitchKeyStatus(HotKey.with(keyCode: keyCode, character: character, in: switchKeyStatus))
    }

    var switchKeyTitle: String {
        HotKey.title(of: switchKeyStatus)
    }

    private func saveSwitchKeyStatus(_ status: Int32) {
        vSwitchKeyStatus = status
        switchKeyStatus = status
        defaults.set(Int(status), forKey: "SwitchKeyStatus")
    }

    //MARK: actions
    func openMacroTable() {
        appDelegate?.onMacroSelected()
    }

    func loadDefaultConfig() {
        appDelegate?.loadDefaultConfig()
        defaults.set(0, forKey: Option.showUIOnStartup.rawValue)
        defaults.set(1, forKey: Option.runOnStartup.rawValue)
        reload()
    }
}
