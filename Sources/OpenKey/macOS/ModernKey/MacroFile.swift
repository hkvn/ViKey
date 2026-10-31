//
//  MacroFile.swift
//  ViKey
//
//  Macro files: UniKey (ukmacro.txt), EVKey (evkmacro.txt), OpenKey and ViKey text files,
//  and the macOS text replacements dragged out of System Settings.
//

import Foundation

enum MacroFile {
    struct Entry: Equatable {
        let text: String
        let content: String
    }

    /// first line of the text file, as UniKey expects
    static let header = ";Compatible OpenKey Macro Data file for UniKey*** version=1 ***"

    static func read(_ data: Data) -> [Entry] {
        readTextReplacements(data) ?? readText(decode(data))
    }

    /// text of a file made on Windows or on a Mac: UTF-8 or UTF-16, with or without a BOM
    static func decode(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(3))
        var text: String?
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            text = String(data: data.dropFirst(3), encoding: .utf8)
        } else if bytes.starts(with: [0xFF, 0xFE]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else if data.contains(0) {
            //UTF-16 without a BOM; ASCII in UTF-16 is also valid UTF-8 (with NUL bytes), so check this first
            let littleEndian = data.count >= 2 && data[data.startIndex + 1] == 0
            text = String(data: data, encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        return text ?? String(decoding: data, as: UTF8.self)
    }

    /// one macro per line, "text:content"; the first line is a header when it starts with ";"
    static func readText(_ string: String) -> [Entry] {
        var entries: [Entry] = []
        var isFirstLine = true
        string.enumerateLines { line, _ in
            defer { isFirstLine = false }
            if isFirstLine && line.hasPrefix(";") {
                return
            }
            guard let colon = line.firstIndex(of: ":") else { return }
            var text = String(line[..<colon])
            var content = String(line[line.index(after: colon)...])
            //a text can start with ":", such as ":)" in the line ":):☺", like the OpenKey reader
            while text.isEmpty && !content.isEmpty {
                guard let next = content.firstIndex(of: ":") else { break }
                text = ":" + content[..<next]
                content = String(content[content.index(after: next)...])
            }
            if !text.isEmpty {
                entries.append(Entry(text: text, content: content))
            }
        }
        return entries
    }

    /// System Settings → Keyboard → Text Replacements: selected items dragged to Finder make a plist
    /// with an array of {shortcut, phrase}. nil if the data is not such a plist
    static func readTextReplacements(_ data: Data) -> [Entry]? {
        guard let items = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            return nil
        }
        return items.compactMap { item in
            guard let text = item["shortcut"] as? String, let content = item["phrase"] as? String, !text.isEmpty else { return nil }
            return Entry(text: text, content: content)
        }
    }

    /// a line can not hold a line break: it becomes a space
    static func text(of entries: [Entry]) -> String {
        func oneLine(_ string: String) -> String {
            string.components(separatedBy: .newlines).joined(separator: " ")
        }
        return ([header] + entries.map { "\(oneLine($0.text)):\(oneLine($0.content))" }).joined(separator: "\n") + "\n"
    }
}
