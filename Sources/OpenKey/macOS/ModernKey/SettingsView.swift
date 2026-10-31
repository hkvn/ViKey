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
                    HotKeyEditor(status: model.switchKeyStatusBinding)
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
    @ObservedObject var sync = MacroSync.shared

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

            Section {
                OptionToggle(title: "Đồng bộ gõ tắt giữa các máy Mac",
                             help: sync.status.isEmpty ? nil : sync.status,
                             isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) }))
                LabeledContent("Thư mục") {
                    HStack {
                        Text(sync.folderDisplayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)
                        Button("Đổi…") { sync.chooseFolder() }
                    }
                }
            } header: {
                Text("Đồng bộ")
            } footer: {
                Text("Danh sách gõ tắt được lưu trong file \"\(MacroSync.fileName)\" ở thư mục này, mặc định trong iCloud Drive. "
                     + "Các máy Mac bật đồng bộ cùng một thư mục sẽ dùng chung danh sách.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

//MARK: - Ứng dụng
struct AppsSettingsView: View {
    @ObservedObject var apps: AppsModel
    @State private var confirmForgetAll = false
    @State private var search = ""
    private let codeTables = OpenKeyManager.getTableCodes() as? [String] ?? []

    private var shownApps: [AppEntry] {
        guard !search.isEmpty else { return apps.rememberedApps }
        return apps.rememberedApps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleId.localizedCaseInsensitiveContains(search) }
    }

    private func appRow(_ app: AppEntry) -> some View {
        HStack {
            AppLabel(app: app)
            Spacer()
            RowPicker(help: "Chế độ gõ", titles: [(1, "Tiếng Việt"), (0, "English")],
                      selection: apps.languageBinding(for: app.bundleId))
            if vRememberCode != 0 {
                RowPicker(help: "Bảng mã", titles: codeTables.enumerated().map { ($0.offset, $0.element) },
                          selection: apps.codeTableBinding(for: app.bundleId))
            }
            RemoveButton(help: "Quên ứng dụng này") { apps.forget(app.bundleId) }
        }
    }

    var body: some View {
        Form {
            Section {
                if apps.excludedApps.isEmpty {
                    Text("Chưa có ứng dụng nào.").foregroundColor(.secondary)
                }
                ForEach(apps.excludedApps) { app in
                    HStack {
                        AppLabel(app: app)
                        Spacer()
                        RemoveButton(help: "Bỏ khỏi danh sách") { apps.removeExcludedApp(app.bundleId) }
                    }
                }
                Button("Thêm ứng dụng…") { apps.addExcludedApps() }
            } header: {
                Text("Luôn dùng English")
            } footer: {
                Text("ViKey không gõ tiếng Việt trong các ứng dụng này, ví dụ Terminal, trò chơi, trình soạn code.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                if apps.rememberedApps.isEmpty {
                    Text("Chưa có ứng dụng nào.").foregroundColor(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        //labels hidden: in a form the title would be a label, and the field an empty box on the right
                        TextField("Tìm ứng dụng", text: $search, prompt: Text("Tìm ứng dụng"))
                            .textFieldStyle(.plain)
                            .labelsHidden()
                    }
                    //lazy: only the rows on screen are made, so hundreds of apps open fast.
                    //A ScrollView, not a List: a List inside the form does not scroll with the mouse wheel
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(shownApps.enumerated()), id: \.element.id) { index, app in
                                appRow(app)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(index % 2 == 1 ? Color.primary.opacity(0.04) : Color.clear)
                            }
                        }
                    }
                    //a new list for each search: it starts at the top, not at the place scrolled to before
                    .id(search)
                    .frame(height: 250)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    .opacity(apps.isLoading ? 0.4 : 1)
                    .overlay {
                        if apps.isLoading {
                            ProgressView().controlSize(.small)
                        } else if shownApps.isEmpty {
                            Text("Không tìm thấy ứng dụng nào.").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        let uninstalled = apps.uninstalledApps
                        if !uninstalled.isEmpty {
                            Button("Quên \(uninstalled.count) ứng dụng đã gỡ") { apps.forgetUninstalledApps() }
                                .help("Các ứng dụng không còn trên máy Mac này")
                        }
                        Spacer()
                        Text("\(apps.rememberedApps.count) ứng dụng")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Quên tất cả…") { confirmForgetAll = true }
                    }
                }
            } header: {
                Text("Ứng dụng đã ghi nhớ")
            } footer: {
                Text("Khi bật \"Chuyển chế độ thông minh\" (tab Bộ gõ), ViKey nhớ Tiếng Việt / English cho từng ứng dụng, và cả bảng mã nếu bật \"Tự ghi nhớ bảng mã theo ứng dụng\".")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        //the remembered apps scroll in their own list
        .frame(width: settingsTabWidth, height: 620)
        .alert("Quên tất cả ứng dụng?", isPresented: $confirmForgetAll) {
            Button("Quên tất cả", role: .destructive) { apps.forgetAll() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("ViKey sẽ ghi nhớ lại khi bạn dùng các ứng dụng.")
        }
    }
}

/// icon and name of an app
private struct AppLabel: View {
    let app: AppEntry

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "questionmark.app.dashed").frame(width: 20, height: 20).foregroundColor(.secondary)
            }
            Text(app.name).lineLimit(1)
        }
        .help(app.bundleId)
    }
}

/// pop-up as wide as its title, for the rows of a list; a Picker would fill the row
private struct RowPicker: View {
    let help: String
    let titles: [(tag: Int, title: String)]
    @Binding var selection: Int

    var body: some View {
        Menu {
            Picker(help, selection: $selection) {
                ForEach(titles, id: \.tag) { item in
                    Text(item.title).tag(item.tag)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(titles.first { $0.tag == selection }?.title ?? "")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(help)
    }
}

private struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
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
                LabeledContent("Gõ không được?") {
                    Button("Chẩn đoán…") { appDelegate?.onDiagnosticsSelected() }
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

//MARK: - Hotkey
/// modifier keys and a key of a hotkey, see HotKey
struct HotKeyEditor: View {
    @Binding var status: Int32

    var body: some View {
        HStack(spacing: 4) {
            flagToggle("⌃", .control, help: "Control")
            flagToggle("⌥", .option, help: "Option")
            flagToggle("⇧", .shift, help: "Shift")
            flagToggle("⌘", .command, help: "Command")
            Text("+").foregroundColor(.secondary)
            KeyRecorder(title: HotKey.title(of: status)) { keyCode, character in
                status = HotKey.with(keyCode: keyCode, character: character, in: status)
            }
        }
        .toggleStyle(.button)
    }

    private func flagToggle(_ symbol: String, _ flag: SwitchKeyFlag, help: String) -> some View {
        Toggle(symbol, isOn: Binding(get: { status & flag.rawValue != 0 },
                                     set: { status = HotKey.with(flag, on: $0, in: status) }))
            .help(help)
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
                onKey(HotKey.noKey, HotKey.noKey)
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
