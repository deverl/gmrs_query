import Foundation
import Testing
@testable import GMRSRadioQuery

struct LicenseFileRepairTests {
    @Test func headerPipesInTheTitleFoldBackIntoOneField() throws {
        let chief = try repaired(
            "HD|5194381|0011731276||WSJY732|A|ZA|09/09/2025|09/09/2035||||||||||N||||||||||N||Jason|E|Taylor||CEO | JET MEDICAL RESPONSE||||||||09/09/2025|09/09/2025|||||||||||||||",
            kind: .header
        )
        #expect(chief.count == 59)
        #expect(chief[4] == "WSJY732")
        #expect(chief[5] == "A")
        #expect(chief[34] == "CEO / JET MEDICAL RESPONSE")
        #expect(chief[42] == "09/09/2025")

        let owner = try repaired(
            "HD|5106548|0011484742||WSHM478|A|ZA|03/15/2025|03/15/2035||||||||||N||||||||||N||Raymond|P|Cooper||||owner||||||||03/15/2025|03/15/2025|||||||||||||||",
            kind: .header
        )
        #expect(owner.count == 59)
        #expect(owner[4] == "WSHM478")
        #expect(owner[34] == "owner")
        #expect(owner[42] == "03/15/2025")
    }

    @Test func entityPipesKeepTheNameAddressAndFRN() throws {
        let seay = try repaired(
            "EN|5280832|||WSMI342|L|L03027358|Seay |Jr, Keith B|Keith|B|Seay||Jr||||2167 Hickory St|Mabank|TX|75156|||000|0038215604|I||||||",
            kind: .entity
        )
        #expect(seay.count == 30)
        #expect(seay[4] == "WSMI342")
        #expect(seay[7] == "Seay / Jr, Keith B")
        #expect(seay[8] == "Keith")
        #expect(seay[10] == "Seay")
        #expect(seay[11] == "Jr")
        #expect(seay[15] == "2167 Hickory St")
        #expect(seay[16] == "Mabank")
        #expect(seay[17] == "TX")
        #expect(seay[22] == "0038215604")

        let cooper = try repaired(
            "EN|5106548|||WSHM478|L|L02913113|Cooper ||, Raymond P|Raymond|P|Cooper|||||||54 Frenchton Rd|French Creek|WV|26218||Raymond P Cooper|||000|0036794170|I||||||",
            kind: .entity
        )
        #expect(cooper.count == 30)
        #expect(cooper[7] == "Cooper / , Raymond P")
        #expect(cooper[8] == "Raymond")
        #expect(cooper[10] == "Cooper")
        #expect(cooper[15] == "54 Frenchton Rd")
        #expect(cooper[17] == "WV")
        #expect(cooper[20] == "Raymond P Cooper")
        #expect(cooper[22] == "0036794170")

        let vazquez = try repaired(
            "EN|5199189|||WSKB634|L|L02971658|Vazquez, Christian J|Christian|J|Vazquez|||||3206 Florenze Way|Saint Cloud|FL|34772||||000|0037502531|I||||||",
            kind: .entity
        )
        #expect(vazquez.count == 30)
        #expect(vazquez[8] == "Christian")
        #expect(vazquez[10] == "Vazquez")
        #expect(vazquez[16] == "Saint Cloud")
        #expect(vazquez[17] == "FL")
        #expect(vazquez[22] == "0037502531")
    }

    @Test func downloadedFilesHaveOneColumnCountAfterRepair() throws {
        let directory = URL(fileURLWithPath: "/tmp/gmrs-radio-query", isDirectory: true)
        let hd = directory.appendingPathComponent("HD.dat")
        let en = directory.appendingPathComponent("EN.dat")
        guard FileManager.default.fileExists(atPath: hd.path),
              FileManager.default.fileExists(atPath: en.path)
        else {
            return
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmrs-repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let hdCopy = scratch.appendingPathComponent("HD.dat")
        let enCopy = scratch.appendingPathComponent("EN.dat")
        try FileManager.default.copyItem(at: hd, to: hdCopy)
        try FileManager.default.copyItem(at: en, to: enCopy)
        try LicenseFileRepair.normalize(hdCopy, kind: .header)
        try LicenseFileRepair.normalize(enCopy, kind: .entity)
        try expectColumnCount(59, in: hdCopy)
        try expectColumnCount(30, in: enCopy)
    }

    private func repaired(_ line: String, kind: LicenseFileRepair.Kind) throws -> [String] {
        let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return try LicenseFileRepair.repair(fields, kind: kind, line: 1)
    }

    private func expectColumnCount(_ expected: Int, in url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(maxSplits: Int.max, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        for line in lines {
            let count = line.split(separator: "|", omittingEmptySubsequences: false).count
            #expect(count == expected)
            if count != expected { return }
        }
    }
}
