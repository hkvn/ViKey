//
//  DiagnosticsWindow.swift
//  ViKey
//
//  What ViKey sees now (permission, event tap, typing app, input source,...) and the recent log,
//  to find out why typing does not work, and to copy into a bug report.
//

import AppKit
import SwiftUI

struct DiagnosticsRow: Identifiable, Equatable {
    let label: String
    let value: String
    var warning = false
    var id: String { label }
}

struct DiagnosticsSection: Identifiable, Equatable {
    let title: String
    let rows: [DiagnosticsRow]
    var id: String { title }
}

final class DiagnosticsModel: ObservableObject {
    @Published private(set) var sections: [DiagnosticsSection] = []
    @Published private(set) var log: [String] = []
    private var timer: Timer?

    /// names of other Vietnamese input methods: two input methods together type wrong letters
    private static let otherInputMethods = ["openkey", "evkey", "gotiengviet", "unikey", "xkey", "vnkey", "laban"]
    private static let inputTypes = ["Telex", "VNI", "Simple Telex 1", "Simple Telex 2"]

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    //assigned only when something changed: the window is not drawn again every second
    func refresh() {
        let newSections = Self.makeSections()
        if newSections != sections {
            sections = newSections
        }
        let newLog = VKLogger.recentEntries()
        if newLog != log {
            log = newLog
        }
    }

    var reportText: String {
        var lines = ["ViKey – thông tin chẩn đoán"]
        for section in sections {
            lines.append("")
            lines.append("## \(section.title)")
            lines += section.rows.map { "\($0.label): \($0.value)" }
        }
        lines.append("")
        lines.append("## Nhật ký")
        lines += log
        return lines.joined(separator: "\n")
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
    }

    func reportIssue() {
        copyReport()
        NSWorkspace.shared.open(URL(string: "https://github.com/hkvn/ViKey/issues/new")!)
    }

    //MARK: - Content

    private static func onOff(_ value: Int32) -> String {
        value != 0 ? "Bật" : "Tắt"
    }

    /// "Safari (com.apple.Safari)"
    private static func appTitle(_ bundleId: String) -> String {
        guard !bundleId.isEmpty else { return "?" }
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName
        return name.map { "\($0) (\(bundleId))" } ?? bundleId
    }

    private static func microseconds(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1f ms", value / 1000) : String(format: "%.0f µs", value)
    }

    private static func makeSections() -> [DiagnosticsSection] {
        let status = VKEngineStatus.current()
        let info = Bundle.main.infoDictionary
        let codeTables = OpenKeyManager.getTableCodes() as? [String] ?? []
        let codeTable = codeTables.indices.contains(Int(vCodeTable)) ? codeTables[Int(vCodeTable)] : "\(vCodeTable)"
        let inputType = inputTypes.indices.contains(Int(vInputType)) ? inputTypes[Int(vInputType)] : "\(vInputType)"

        let app = DiagnosticsSection(title: "ViKey", rows: [
            DiagnosticsRow(label: "Phiên bản", value: "\(info?["CFBundleShortVersionString"] as? String ?? "?") (build \(info?["CFBundleVersion"] as? String ?? "?"))"),
            DiagnosticsRow(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
        ])

        let trusted = AXIsProcessTrusted()
        let secureInput = appDelegate?.secureInputStatus()
        let tap: String
        if !status.tapRunning {
            tap = "Chưa chạy"
        } else {
            tap = status.tapEnabled ? "Đang chạy" : "Bị macOS tắt"
        }
        let state = DiagnosticsSection(title: "Trạng thái", rows: [
            DiagnosticsRow(label: "Quyền Trợ năng (Accessibility)", value: trusted ? "Đã cấp" : "Chưa cấp", warning: !trusted),
            DiagnosticsRow(label: "Bắt phím", value: tap, warning: !status.tapRunning || !status.tapEnabled),
            DiagnosticsRow(label: "Secure Input", value: secureInput.map { "Bật, \($0)" } ?? "Tắt", warning: secureInput != nil),
            DiagnosticsRow(label: "Chế độ gõ", value: vLanguage != 0 ? "Tiếng Việt" : "English"),
            DiagnosticsRow(label: "Kiểu gõ", value: inputType),
            DiagnosticsRow(label: "Bảng mã", value: codeTable),
        ])

        let detectMethods = ["ứng dụng phía trước", "bảng nổi trên ứng dụng (Trợ năng)", "cửa sổ Spotlight"]
        let detectMethod = detectMethods.indices.contains(status.detectMethod) ? detectMethods[status.detectMethod] : "?"
        var appRows = [
            DiagnosticsRow(label: "Ứng dụng phía trước", value: appTitle(status.frontApp)),
            DiagnosticsRow(label: "Ứng dụng nhận phím", value: appTitle(status.typingApp)),
            DiagnosticsRow(label: "Cách nhận biết", value: detectMethod + (status.accessibilityAnswered ? "" : ", Trợ năng không trả lời"),
                           warning: !status.accessibilityAnswered),
            DiagnosticsRow(label: "Luôn dùng English", value: status.typingAppExcluded ? "Có" : "Không"),
        ]
        if vUseSmartSwitchKey != 0 {
            let remembered = VKAppMemory.status(forApp: status.typingApp)
            let value = (remembered >= 0 ? remembered : nil).map { memory -> String in
                let table = codeTables.indices.contains(memory >> 1) ? codeTables[memory >> 1] : "\(memory >> 1)"
                return (memory & 1 != 0 ? "Tiếng Việt" : "English") + ", " + table
            }
            appRows.append(DiagnosticsRow(label: "Chế độ đã nhớ", value: value ?? "Chưa nhớ"))
        }
        let apps = DiagnosticsSection(title: "Ứng dụng", rows: appRows)

        let others = NSWorkspace.shared.runningApplications.filter { running in
            guard running.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            let name = "\(running.bundleIdentifier ?? "") \(running.localizedName ?? "")".lowercased()
            return otherInputMethods.contains { name.contains($0) }
        }.compactMap { $0.localizedName }
        let otherLanguageOff = !status.englishInputSource && vOtherLanguage != 0
        let keyboard = DiagnosticsSection(title: "Bàn phím", rows: [
            DiagnosticsRow(label: "Nguồn nhập", value: status.inputSource + (otherLanguageOff ? " (không phải tiếng Anh: ViKey tạm tắt)" : ""),
                           warning: otherLanguageOff),
            DiagnosticsRow(label: "Bộ gõ khác đang chạy", value: others.isEmpty ? "Không có" : others.joined(separator: ", "),
                           warning: !others.isEmpty),
        ])

        let performance = DiagnosticsSection(title: "Hiệu năng", rows: [
            DiagnosticsRow(label: "Phím và cú bấm chuột đã xử lý", value: "\(status.eventCount)"),
            DiagnosticsRow(label: "Thời gian xử lý", value: "trung bình \(microseconds(status.averageEventMicroseconds)), "
                           + "lâu nhất \(microseconds(status.maxEventMicroseconds))"),
            DiagnosticsRow(label: "Nhận biết ứng dụng (lần cuối)", value: microseconds(status.detectMicroseconds)),
            DiagnosticsRow(label: "Số lần macOS tắt bắt phím", value: "\(status.tapRestartCount)", warning: status.tapRestartCount > 0),
        ])

        let settings = DiagnosticsSection(title: "Cài đặt", rows: [
            DiagnosticsRow(label: "Kiểm tra chính tả", value: onOff(vCheckSpelling)),
            DiagnosticsRow(label: "Chuyển chế độ thông minh", value: onOff(vUseSmartSwitchKey)),
            DiagnosticsRow(label: "Nhớ bảng mã theo ứng dụng", value: onOff(vRememberCode)),
            DiagnosticsRow(label: "Tắt khi bộ gõ hệ thống không phải tiếng Anh", value: onOff(vOtherLanguage)),
            DiagnosticsRow(label: "Gõ tắt", value: onOff(vUseMacro) + ", \(VKMacroStore.count()) từ"
                           + (MacroSync.shared.isEnabled ? ", đồng bộ" : "")),
            DiagnosticsRow(label: "Ứng dụng luôn dùng English", value: "\(VKExcludedApps.bundleIds.count)"),
            DiagnosticsRow(label: "Sửa lỗi gợi ý / Chromium", value: "\(onOff(vFixRecommendBrowser)) / \(onOff(vFixChromiumBrowser))"),
            DiagnosticsRow(label: "Gửi từng phím", value: onOff(vSendKeyStepByStep)),
            DiagnosticsRow(label: "Tương thích layout khác", value: onOff(vPerformLayoutCompat)),
        ])

        return [app, state, apps, keyboard, performance, settings]
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(model.sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            LabeledContent(row.label) {
                                HStack(spacing: 4) {
                                    if row.warning {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                    }
                                    Text(row.value)
                                        .foregroundColor(row.warning ? .primary : .secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                Section("Nhật ký") {
                    ScrollView {
                        Text(model.log.isEmpty ? "Chưa có" : model.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 180)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button(copied ? "Đã sao chép" : "Sao chép báo cáo") {
                    model.copyReport()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                Button("Báo lỗi trên GitHub…") { model.reportIssue() }
                    .help("Sao chép báo cáo rồi mở trang báo lỗi: hãy dán báo cáo vào đó")
                Spacer()
                Text("Không có nội dung bạn gõ")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 500)
    }
}

@objc final class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    private let model = DiagnosticsModel()

    @objc convenience init() {
        self.init(window: nil)
        let window = NSWindow(contentViewController: NSHostingController(rootView: DiagnosticsView(model: model)))
        window.title = "Chẩn đoán"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window
    }

    @objc func show() {
        model.start()
        showInFront()
    }

    //refresh only while the window is open
    func windowWillClose(_ notification: Notification) {
        model.stop()
    }
}
