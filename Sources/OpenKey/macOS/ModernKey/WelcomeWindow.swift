//
//  WelcomeWindow.swift
//  ViKey
//
//  First launch: explains the Accessibility permission and waits for it,
//  then ViKey starts without a restart.
//

import AppKit
import ApplicationServices
import SwiftUI

final class PermissionWatcher: ObservableObject {
    @Published private(set) var granted = AXIsProcessTrusted()
    var onGranted: (() -> Void)?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        guard !granted, AXIsProcessTrusted() else { return }
        granted = true
        stop()
        onGranted?()
    }
}

struct WelcomeView: View {
    @ObservedObject var watcher: PermissionWatcher

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Chào mừng bạn đến với ViKey")
                .font(.title2)
                .bold()
            Text("ViKey cần quyền Trợ năng (Accessibility) để nhận các phím bạn gõ và đổi thành chữ có dấu. ViKey không lưu và không gửi đi những gì bạn gõ.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Bấm \"Cấp quyền…\", rồi bấm \"Mở Cài đặt hệ thống\" (Open System Settings).")
                step(2, "Bật ViKey trong danh sách Trợ năng (Accessibility).")
                step(3, "Quay lại đây: ViKey sẽ tự chạy, không cần mở lại.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            if watcher.granted {
                Label("Đã có quyền. ViKey đang khởi động…", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Đang chờ bạn cấp quyền…").foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Thoát") { NSApp.terminate(nil) }
                Spacer()
                Button("Mở cài đặt Trợ năng") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Cấp quyền…") {
                    //adds ViKey to the list and shows the macOS dialog
                    MJAccessibilityOpenPanel()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(watcher.granted)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@objc final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let watcher = PermissionWatcher()
    private let onGranted: () -> Void
    private var finished = false

    @objc init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        super.init(window: nil)
        let controller = NSHostingController(rootView: WelcomeView(watcher: watcher))
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = "ViKey"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        watcher.onGranted = { [weak self] in
            //let the user see that the permission is granted, then start
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self?.finish()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc func show() {
        watcher.start()
        showInFront()
    }

    private func finish() {
        finished = true
        window?.close()
        onGranted()
    }

    func windowWillClose(_ notification: Notification) {
        watcher.stop()
        //closed without the permission: ViKey can not work
        if !finished {
            NSApp.terminate(nil)
        }
    }
}
