//
//  ConvertToolWindow.swift
//  ViKey
//
//  Window of the convert tool: converts the text in the clipboard between code tables.
//

import AppKit
import SwiftUI

final class ConvertToolModel: ObservableObject {
    /// the four case options can not be on together, so they are one choice here (0: keep the case)
    static let caseOptions: [(title: String, option: VKConvertOption?)] = [
        ("Giữ nguyên", nil),
        ("CHỮ HOA", .allCaps),
        ("chữ thường", .allLower),
        ("Viết hoa đầu câu", .capsFirstLetter),
        ("Viết Hoa Mỗi Từ", .capsEachWord),
    ]

    func option(_ option: VKConvertOption) -> Binding<Bool> {
        Binding(get: { VKConvertTool.option(option) }, set: {
            VKConvertTool.setOption(option, on: $0)
            self.objectWillChange.send()
        })
    }

    var caseOption: Binding<Int> {
        Binding(get: {
            Self.caseOptions.firstIndex { $0.option.map(VKConvertTool.option) ?? false } ?? 0
        }, set: { index in
            if let option = Self.caseOptions[index].option {
                VKConvertTool.setOption(option, on: true)
            } else {
                VKConvertTool.setOption(.allCaps, on: false) //turns all case options off
            }
            self.objectWillChange.send()
        })
    }

    var fromCode: Binding<Int> {
        Binding(get: { VKConvertTool.fromCode }, set: {
            VKConvertTool.fromCode = $0
            self.objectWillChange.send()
        })
    }

    var toCode: Binding<Int> {
        Binding(get: { VKConvertTool.toCode }, set: {
            VKConvertTool.toCode = $0
            self.objectWillChange.send()
        })
    }

    var hotKey: Binding<Int32> {
        Binding(get: { VKConvertTool.hotKey }, set: {
            VKConvertTool.hotKey = $0
            self.objectWillChange.send()
        })
    }

    func swapCodeTables() {
        let fromCode = VKConvertTool.fromCode
        VKConvertTool.fromCode = VKConvertTool.toCode
        VKConvertTool.toCode = fromCode
        objectWillChange.send()
    }

    func convert(window: NSWindow?) {
        if OpenKeyManager.quickConvert() {
            if VKConvertTool.option(.alertWhenCompleted) {
                OpenKeyManager.showMessage(window, message: "Chuyển mã thành công!", subMsg: "Kết quả đã được lưu trong clipboard.")
            }
        } else {
            OpenKeyManager.showMessage(window, message: "Không có dữ liệu trong clipboard!", subMsg: "Hãy sao chép một đoạn text để chuyển đổi!")
        }
    }
}

struct ConvertToolView: View {
    @ObservedObject var model: ConvertToolModel
    private let codeTables = OpenKeyManager.getTableCodes() as? [String] ?? []

    var body: some View {
        Form {
            Section("Bảng mã") {
                codeTablePicker("Từ bảng mã", selection: model.fromCode)
                codeTablePicker("Sang bảng mã", selection: model.toCode)
                HStack {
                    Spacer()
                    Button {
                        model.swapCodeTables()
                    } label: {
                        Label("Đổi chiều", systemImage: "arrow.up.arrow.down")
                    }
                }
            }

            Section("Tuỳ chọn") {
                Picker("Kiểu chữ", selection: model.caseOption) {
                    ForEach(ConvertToolModel.caseOptions.indices, id: \.self) { index in
                        Text(ConvertToolModel.caseOptions[index].title).tag(index)
                    }
                }
                Toggle("Bỏ dấu", isOn: model.option(.removeMark))
                Toggle("Thông báo khi chuyển xong", isOn: model.option(.alertWhenCompleted))
            }

            Section("Phím tắt chuyển mã nhanh") {
                LabeledContent("Phím tắt") {
                    HotKeyEditor(status: model.hotKey)
                }
            }

            Section {
                HStack {
                    Text("Chép văn bản (⌘C), bấm Chuyển mã, rồi dán (⌘V).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Chuyển mã") {
                        model.convert(window: NSApp.keyWindow)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: 480)
    }

    private func codeTablePicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(codeTables.indices, id: \.self) { index in
                Text(codeTables[index]).tag(index)
            }
        }
    }
}

@objc final class ConvertToolWindowController: NSWindowController {
    private let model = ConvertToolModel()

    @objc convenience init() {
        self.init(window: nil)
        let controller = NSHostingController(rootView: ConvertToolView(model: model))
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = "Công cụ chuyển mã"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    @objc func show() {
        model.objectWillChange.send()
        showInFront()
    }
}
