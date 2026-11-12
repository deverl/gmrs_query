import Foundation

/// A few GMRS rows contain a `|` inside a name or title. That character is also
/// the column separator, so the row arrives with more fields than the table.
/// Those pieces are joined with " / " so the row has the expected number of columns.
enum LicenseFileRepair {
    enum Kind {
        case header
        case entity
    }

    static func normalize(_ url: URL, kind: Kind) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(maxSplits: Int.max, omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }

        let expected = kind == .header ? 59 : 30
        var changed = false
        for index in lines.indices {
            let cleaned = lines[index].hasSuffix("\r") ? String(lines[index].dropLast()) : lines[index]
            let fields = cleaned.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count != expected else {
                if cleaned != lines[index] {
                    lines[index] = cleaned
                    changed = true
                }
                continue
            }
            let repaired = try repair(fields, kind: kind, line: index + 1)
            lines[index] = repaired.joined(separator: "|")
            changed = true
        }
        guard changed else { return }

        var output = lines.joined(separator: "\n")
        output.append("\n")
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).repairing")
        try output.write(to: temporary, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    static func repair(_ fields: [String], kind: Kind, line: Int) throws -> [String] {
        switch kind {
        case .header:
            try repairHeader(fields, line: line)
        case .entity:
            try repairEntity(fields, line: line)
        }
    }

    private static func repairHeader(_ fields: [String], line: Int) throws -> [String] {
        if fields.count == 59 { return fields }
        let prefixCount = 34
        let suffixCount = 17
        guard fields.count > prefixCount + suffixCount,
              fields.first == "HD",
              fields.count > 6,
              fields[6] == "ZA"
        else {
            throw unreadable(line)
        }
        let prefix = Array(fields.prefix(prefixCount))
        let suffix = Array(fields.suffix(suffixCount))
        guard isDateOrEmpty(suffix[0]), isDateOrEmpty(suffix[1]) else {
            throw unreadable(line)
        }
        let middle = Array(fields.dropFirst(prefixCount).dropLast(suffixCount))
        let extra = middle.count - 8
        guard extra > 0, middle.count >= extra + 1 else { throw unreadable(line) }
        let title = fold(Array(middle.prefix(extra + 1)))
        let rest = Array(middle.dropFirst(extra + 1))
        guard rest.count == 7 else { throw unreadable(line) }
        let rebuilt = prefix + [title] + rest + suffix
        guard rebuilt.count == 59 else { throw unreadable(line) }
        return rebuilt
    }

    private static func repairEntity(_ fields: [String], line: Int) throws -> [String] {
        if fields.count == 30 { return fields }
        guard fields.count > 30,
              fields.first == "EN",
              let frn = fields.suffix(8).first,
              frn.range(of: #"^\d{10}$"#, options: .regularExpression) != nil
        else {
            throw unreadable(line)
        }
        let prefix = Array(fields.prefix(7))
        let suffix = Array(fields.suffix(8))
        let middle = Array(fields.dropFirst(7).dropLast(8))
        guard let stateIndex = lastStateIndex(in: middle), stateIndex >= 2 else {
            throw unreadable(line)
        }
        let streetIndex = stateIndex - 2
        var before = Array(middle.prefix(streetIndex))
        let address = Array(middle[streetIndex...stateIndex + 1])
        var after = Array(middle.suffix(from: stateIndex + 2))
        guard before.count >= 8 else { throw unreadable(line) }

        var extra = before.count - 8
        var name = [before[0]]
        var rest = Array(before.dropFirst())
        while extra > 0, let next = rest.first {
            let previous = name[name.count - 1]
            let continues = previous.hasSuffix(" ") || previous.isEmpty
                || next.hasPrefix(" ") || next.hasPrefix(",") || next.isEmpty
            if !continues { break }
            name.append(rest.removeFirst())
            extra -= 1
        }
        while extra > 0, rest.count - 1 >= 7, let empty = rest.firstIndex(of: "") {
            rest.remove(at: empty)
            extra -= 1
        }
        guard extra == 0, rest.count == 7 else { throw unreadable(line) }

        if after.count > 3 {
            if let sgin = after.last, !sgin.isEmpty, sgin.allSatisfy(\.isNumber) {
                let text = after.dropLast().filter { !$0.isEmpty }
                guard text.count <= 1 else { throw unreadable(line) }
                after = ["", text.first ?? "", sgin]
            } else {
                while after.count > 3, let empty = after.firstIndex(of: "") {
                    after.remove(at: empty)
                }
            }
        }
        while after.count < 3 {
            after.append("")
        }
        guard after.count == 3 else { throw unreadable(line) }

        let rebuilt = prefix + [fold(name)] + rest + address + after + suffix
        guard rebuilt.count == 30,
              rebuilt[17].range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil,
              rebuilt[22].range(of: #"^\d{10}$"#, options: .regularExpression) != nil
        else {
            throw unreadable(line)
        }
        return rebuilt
    }

    private static func lastStateIndex(in middle: [String]) -> Int? {
        guard middle.count >= 2 else { return nil }
        var found: Int?
        for index in 0..<(middle.count - 1) {
            if middle[index].range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil,
               middle[index + 1].range(of: #"^\d{5}(?:\d{4})?$"#, options: .regularExpression) != nil {
                found = index
            }
        }
        return found
    }

    private static func fold(_ pieces: [String]) -> String {
        pieces
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    private static func isDateOrEmpty(_ value: String) -> Bool {
        value.isEmpty || value.range(of: #"^\d{2}/\d{2}/\d{4}$"#, options: .regularExpression) != nil
    }

    private static func unreadable(_ line: Int) -> DatabaseUpdateError {
        .failed(
            "The GMRS license file has a row that could not be read (line \(line)).",
            databaseReplaced: false
        )
    }
}
