//
//  MacroWindow.swift
//  ViKey
//
//  Window with the list of macros (gõ tắt).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroItem: Identifiable, Hashable {
    let text: String
    let content: String
    var id: String { text }
}

final class MacroModel: ObservableObject {
    @Published private(set) var macros: [MacroItem] = []
    @Published var search = ""

    init() {
        reload()
    }

    func reload() {
        macros = VKMacroStore.allMacros()
            .map { MacroItem(text: $0.text, content: $0.content) }
            .sorted { $0.text.localizedStandardCompare($1.text) == .orderedAscending }
    }

    var shownMacros: [MacroItem] {
        guard !search.isEmpty else { return macros }
        return macros.filter { $0.text.localizedCaseInsensitiveContains(search) || $0.content.localizedCaseInsensitiveContains(search) }
    }

    func save(text: String, content: String) {
        VKMacroStore.setMacro(text, content: content)
        reload()
    }

    func delete(_ texts: Set<String>) {
        for text in texts {
            VKMacroStore.deleteMacro(text)
        }
        reload()
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.message = "Chọn file gõ tắt của UniKey (ukmacro.txt), EVKey (evkmacro.txt), OpenKey, ViKey, hoặc file Thay thế văn bản của macOS (.plist)"
        panel.allowedContentTypes = [.plainText, .propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            showMessage("Không đọc được file", "Hãy kiểm tra lại file đã chọn.")
            return
        }
        let entries = MacroFile.read(data)
        guard !entries.isEmpty else {
            showMessage("Không có từ gõ tắt nào", "File này không có dòng nào dạng \"từ gõ tắt:nội dung\".")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Nhập \(entries.count) từ gõ tắt"
        alert.informativeText = "Bạn có muốn giữ lại các từ gõ tắt hiện tại không? Khi giữ lại, từ đã có sẽ không bị thay đổi."
        alert.addButton(withTitle: "Giữ lại")
        alert.addButton(withTitle: "Thay thế")
        alert.addButton(withTitle: "Huỷ")
        let answer = alert.runModal()
        guard answer != .alertThirdButtonReturn else { return }
        let before = macros.count
        VKMacroStore.addMacros(entries.map { VKMacro(text: $0.text, content: $0.content) },
                               keepCurrent: answer == .alertFirstButtonReturn)
        reload()
        VKLogger.log("imported \(entries.count) macros from \(url.lastPathComponent), \(before) -> \(macros.count)", category: "macro")
    }

    func exportToFile() {
        let panel = NSSavePanel()
        panel.message = "File xuất ra dùng được với UniKey, EVKey, OpenKey và ViKey"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ViKeyMacro.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entries = macros.map { MacroFile.Entry(text: $0.text, content: $0.content) }
        do {
            try Data(MacroFile.text(of: entries).utf8).write(to: url, options: .atomic)
        } catch {
            showMessage("Không lưu được file", error.localizedDescription)
        }
    }

    private func showMessage(_ message: String, _ information: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.runModal()
    }
}

/// values filled each time the macro is typed, see fillMacroDynamicValues in Macro.h
private let dynamicValues: [(title: String, token: String)] = [
    ("Ngày (31/10/2026)", "{date}"),
    ("Giờ (14:05)", "{time}"),
    ("Thứ (Thứ Bảy)", "{weekday}"),
    ("Ngày trong tháng (31)", "{day}"),
    ("Tháng (10)", "{month}"),
    ("Năm (2026)", "{year}"),
    ("Nội dung clipboard", "{clipboard}"),
]

struct MacroView: View {
    @ObservedObject var model: MacroModel
    @State private var selection = Set<String>()
    @State private var text = ""
    @State private var content = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Tìm từ gõ tắt", text: $model.search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            Divider()

            Table(model.shownMacros, selection: $selection) {
                TableColumn("Từ gõ tắt", value: \.text)
                    .width(min: 80, ideal: 120, max: 240)
                TableColumn("Nội dung", value: \.content)
            }
            .onChange(of: selection) { selected in
                //edit the selected macro in the fields below
                if selected.count == 1, let item = model.macros.first(where: { selected.contains($0.text) }) {
                    text = item.text
                    content = item.content
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Từ gõ tắt", text: $text)
                    .frame(width: 130)
                TextField("Nội dung đầy đủ", text: $content)
                Menu {
                    Section("Điền khi gõ") {
                        ForEach(dynamicValues, id: \.token) { value in
                            Button("\(value.title)  \(value.token)") { content += value.token }
                        }
                    }
                } label: {
                    Image(systemName: "curlybraces")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Chèn giá trị tự động: ngày, giờ, clipboard,…")
                Button(VKMacroStore.hasMacro(text) ? "Sửa" : "Thêm") {
                    model.save(text: text, content: content)
                    text = ""
                    content = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty || content.isEmpty)
            }
            .padding(10)

            HStack {
                Button {
                    model.delete(selection)
                    selection = []
                    text = ""
                    content = ""
                } label: {
                    Image(systemName: "minus")
                }
                .help("Xoá các từ đã chọn")
                .disabled(selection.isEmpty)
                Spacer()
                Text("\(model.macros.count) từ gõ tắt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Menu("Nhập / Xuất") {
                    Button("Nhập từ file…") { model.importFromFile() }
                    Button("Xuất ra file…") { model.exportToFile() }
                }
                .fixedSize()
            }
            .padding([.horizontal, .bottom], 10)
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

@objc final class MacroWindowController: NSWindowController {
    private let model = MacroModel()

    @objc convenience init() {
        self.init(window: nil)
        let window = NSWindow(contentViewController: NSHostingController(rootView: MacroView(model: model)))
        window.title = "Gõ tắt"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    @objc func show() {
        model.reload()
        showInFront()
    }
}
