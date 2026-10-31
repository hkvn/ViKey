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
        model.setSwitchKey(keyCode: SettingsModel.noKey, character: SettingsModel.noKey)
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

        defaults.removePersistentDomain(forName: suiteName)
        print("settings: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
