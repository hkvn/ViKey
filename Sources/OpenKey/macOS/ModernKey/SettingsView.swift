//
//  SettingsView.swift
//  OpenKey
//
//  Tabs of the settings window, in the style of macOS System Settings.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Width of every tab, height follows the content
let settingsTabWidth: CGFloat = 540

/// Toggle with a second line of help text
private struct OptionToggle: View {
    let title: String
    var help: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            if let help = help {
                Text(help)
            }
        }
    }
}

//MARK: - Bộ gõ
struct TypingSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Chế độ gõ", selection: model.languageBinding) {
                    Text("Tiếng Việt").tag(1)
                    Text("English").tag(0)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker("Kiểu gõ", selection: model.inputTypeBinding) {
                    ForEach(Array(SettingsModel.inputTypes.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                Picker("Bảng mã", selection: model.codeTableBinding) {
                    ForEach(Array(OpenKeyManager.getTableCodes().enumerated()), id: \.offset) { index, name in
                        Text(name as? String ?? "").tag(index)
                    }
                }
            }

            Section("Phím tắt") {
                LabeledContent("Chuyển Tiếng Việt / English") {
                    HStack(spacing: 4) {
                        Toggle("⌃", isOn: model.switchKeyBinding(.control)).help("Control")
                        Toggle("⌥", isOn: model.switchKeyBinding(.option)).help("Option")
                        Toggle("⇧", isOn: model.switchKeyBinding(.shift)).help("Shift")
                        Toggle("⌘", isOn: model.switchKeyBinding(.command)).help("Command")
                        Text("+").foregroundColor(.secondary)
                        KeyRecorder(title: model.switchKeyTitle) { keyCode, character in
                            model.setSwitchKey(keyCode: keyCode, character: character)
                        }
                    }
                    .toggleStyle(.button)
                }
                OptionToggle(title: "Kêu beep khi chuyển", isOn: model.switchKeyBinding(.beep))
                OptionToggle(title: "Tạm tắt ViKey bằng phím ⌘", isOn: model.binding(.tempOffOpenKey))
            }

            Section("Theo từng ứng dụng") {
                OptionToggle(title: "Chuyển chế độ thông minh", help: "Nhớ Tiếng Việt / English cho từng ứng dụng",
                             isOn: model.binding(.smartSwitchKey))
                OptionToggle(title: "Tự ghi nhớ bảng mã theo ứng dụng", isOn: model.binding(.rememberCode))
                OptionToggle(title: "Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh", isOn: model.binding(.otherLanguage))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: settingsTabWidth)
    }
}

//MARK: - Chính tả
struct SpellingSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Chính tả") {
                OptionToggle(title: "Kiểm tra chính tả", isOn: model.binding(.checkSpelling))
                Group {
                    OptionToggle(title: "Tự khôi phục phím với từ sai", help: "Trả lại các phím đã gõ khi từ không phải tiếng Việt",
                                 isOn: model.binding(.restoreIfWrongSpelling))
                    OptionToggle(title: "Cho phép \"z w j f\" làm phụ âm", isOn: model.binding(.allowConsonantZFWJ))
                    OptionToggle(title: "Tạm tắt chính tả bằng phím ⌃", isOn: model.binding(.tempOffSpelling))
                }
                .disabled(!model[.checkSpelling])
            }

            Section("Cách gõ") {
                OptionToggle(title: "Đặt dấu oà, uý", help: "Thay vì òa, úy", isOn: model.binding(.modernOrthography))
                OptionToggle(title: "Viết hoa chữ cái đầu câu", isOn: model.binding(.upperCaseFirstChar))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: settingsTabWidth)
    }
}

//MARK: - Gõ tắt
struct MacroSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Gõ tắt") {
                OptionToggle(title: "Cho phép gõ tắt", isOn: model.binding(.useMacro))
                Group {
                    OptionToggle(title: "Gõ tắt cả khi tắt tiếng Việt", isOn: model.binding(.useMacroInEnglishMode))
                    OptionToggle(title: "Tự động viết hoa theo phím tắt", isOn: model.binding(.autoCapsMacro))
                }
                .disabled(!model[.useMacro])
                LabeledContent("Danh sách từ gõ tắt") {
                    Button("Bảng gõ tắt…") { model.openMacroTable() }
                }
            }

            Section("Gõ nhanh") {
                OptionToggle(title: "Gõ nhanh phụ âm đôi", help: "cc → ch, gg → gi, kk → kh, nn → ng, qq → qu, pp → ph, tt → th",
                             isOn: model.binding(.quickTelex))
                OptionToggle(title: "Gõ tắt phụ âm đầu", help: "f → ph, j → gi, w → qu", isOn: model.binding(.quickStartConsonant))
                OptionToggle(title: "Gõ tắt phụ âm cuối", help: "g → ng, h → nh, k → ch", isOn: model.binding(.quickEndConsonant))
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: settingsTabWidth)
    }
}

//MARK: - Hệ thống
struct SystemSettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmDefaultConfig = false

    var body: some View {
        Form {
            Section("Khởi động") {
                OptionToggle(title: "Khởi động cùng macOS", isOn: model.binding(.runOnStartup))
                OptionToggle(title: "Mở cài đặt khi khởi động", isOn: model.binding(.showUIOnStartup))
                OptionToggle(title: "Kiểm tra bản mới khi khởi động", isOn: model.binding(.checkUpdateOnStartup))
            }

            Section("Giao diện") {
                OptionToggle(title: "Biểu tượng đơn sắc trên thanh menu", isOn: model.binding(.grayIcon))
                OptionToggle(title: "Hiện biểu tượng trên thanh Dock", isOn: model.binding(.showIconOnDock))
            }

            Section("Tương thích") {
                OptionToggle(title: "Sửa lỗi gợi ý", help: "Trình duyệt, Excel,…", isOn: model.binding(.fixRecommendBrowser))
                OptionToggle(title: "Sửa lỗi trên Chromium (beta)", isOn: model.binding(.fixChromiumBrowser))
                    .disabled(!model[.fixRecommendBrowser])
                OptionToggle(title: "Gửi từng phím", help: "Bật nếu gõ bị lỗi trong một số ứng dụng", isOn: model.binding(.sendKeyStepByStep))
                OptionToggle(title: "Tương thích Telex trên layout khác", help: "Dvorak, Colemak,…", isOn: model.binding(.performLayoutCompat))
            }

            Section {
                HStack {
                    Button("Khôi phục mặc định…") { confirmDefaultConfig = true }
                    Spacer()
                    Button("Thoát ViKey") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: settingsTabWidth)
        .alert("Khôi phục cấu hình mặc định?", isPresented: $confirmDefaultConfig) {
            Button("Khôi phục", role: .destructive) { model.loadDefaultConfig() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Mọi tuỳ chọn sẽ trở về giá trị ban đầu.")
        }
    }
}

//MARK: - Giới thiệu
struct AboutSettingsView: View {
    @State private var checkingUpdate = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "Phiên bản \(short) (build \(build)) · \(OpenKeyManager.getBuildDate() ?? "")"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("ViKey").font(.title).bold()
                    Text("Bộ gõ Tiếng Việt nguồn mở cho macOS").foregroundColor(.secondary)
                    Text(version).font(.caption).foregroundColor(.secondary)
                    Button(checkingUpdate ? "Đang kiểm tra…" : "Kiểm tra bản mới…") {
                        checkingUpdate = true
                        OpenKeyManager.checkNewVersion(NSApp.keyWindow) {
                            checkingUpdate = false
                        }
                    }
                    .disabled(checkingUpdate)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Mã nguồn") {
                    Link("github.com/hkvn/ViKey", destination: URL(string: "https://github.com/hkvn/ViKey")!)
                }
                LabeledContent("Bản phát hành") {
                    Link("Các phiên bản", destination: URL(string: "https://github.com/hkvn/ViKey/releases")!)
                }
            }

            Section {
                LabeledContent("OpenKey") {
                    Link("github.com/tuyenvm/OpenKey", destination: URL(string: "https://github.com/tuyenvm/OpenKey")!)
                }
                LabeledContent("Tác giả OpenKey") {
                    Link("Mai Vũ Tuyên", destination: URL(string: "mailto:maivutuyen.91@gmail.com")!)
                }
            } header: {
                Text("Dựa trên OpenKey")
            } footer: {
                Text("ViKey phát triển tiếp từ OpenKey, theo giấy phép GPL-3.0.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsTabWidth)
    }
}

//MARK: - Key recorder
/// Button which records the next key press. Delete clears the key (modifier keys only), Escape cancels.
struct KeyRecorder: View {
    let title: String
    let onKey: (_ keyCode: UInt16, _ character: UInt16) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Nhấn một phím…" : title) {
            recording ? stop() : start()
        }
        .frame(minWidth: 70)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                break
            case kVK_Delete, kVK_ForwardDelete:
                onKey(SettingsModel.noKey, SettingsModel.noKey)
            case kVK_Space:
                onKey(UInt16(kVK_Space), UInt16(kVK_Space))
            default:
                let character = event.charactersIgnoringModifiers?.lowercased().utf8.first ?? 0
                onKey(event.keyCode, UInt16(character))
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
    }
}
