import Foundation
import Testing
@testable import GMRSRadioQuery

struct DatabaseUpdateTests {
    @Test func importScriptUsesPipeFilesAndDoesNotIndexYet() {
        let sql = DatabaseSchema.importScript(
            hd: "/tmp/gmrs-radio-query/HD.dat",
            en: "/tmp/gmrs-radio-query/EN.dat"
        )
        #expect(sql.contains("CREATE TABLE hd"))
        #expect(sql.contains("CREATE TABLE en"))
        #expect(!sql.contains("CREATE TABLE am"))
        #expect(sql.contains(".separator \"|\" \"\\n\""))
        #expect(sql.contains(".import /tmp/gmrs-radio-query/HD.dat hd"))
        #expect(sql.contains(".import /tmp/gmrs-radio-query/EN.dat en"))
        #expect(!sql.contains("CREATE INDEX"))
        #expect(!sql.contains("W7DNS"))
    }

    @Test func sqlStringDoublesQuotes() {
        #expect(DatabaseSchema.sqlString("/tmp/a'b\\c") == "'/tmp/a''b\\c'")
    }

    @Test func mysqlImportUsesLoadData() throws {
        let sql = DatabaseSchema.licenseSQL(
            database: "gmrs",
            hd: "/tmp/gmrs-radio-query/HD.dat",
            en: "/tmp/gmrs-radio-query/EN.dat"
        )
        #expect(sql.contains("CREATE DATABASE IF NOT EXISTS `gmrs`"))
        #expect(sql.contains("LOAD DATA LOCAL INFILE '/tmp/gmrs-radio-query/HD.dat'"))
        #expect(sql.contains("FIELDS TERMINATED BY '|'"))
        #expect(!sql.contains("en_state_name_index"))
        #expect(!sql.contains("CREATE TABLE am"))
        let indexed = DatabaseSchema.licenseSQL(
            database: "gmrs",
            hd: "/tmp/gmrs-radio-query/HD.dat",
            en: "/tmp/gmrs-radio-query/EN.dat",
            stateIndex: true
        )
        #expect(indexed.contains("CREATE INDEX en_state_name_index ON en (state, last_name, first_name)"))
        #expect(!DatabaseSchema.finishScript(importedAt: "2026-01-01T00:00:00Z").contains("en_state_name_index"))
        #expect(DatabaseSchema.finishScript(importedAt: "2026-01-01T00:00:00Z", stateIndex: true).contains("en_state_name_index"))
        #expect(!sql.contains("W7DNS"))
        #expect(throws: DatabaseUpdateError.self) {
            try DatabaseSchema.validatedName("fcc; DROP TABLE hd")
        }
    }

    @Test func postgresImportCopiesPipeFiles() {
        let sql = DatabaseSchema.postgresLicenseSQL(
            hd: "/tmp/a'b.dat",
            en: "/tmp/EN.dat"
        )
        #expect(sql.contains("\\copy hd FROM '/tmp/a''b.dat' WITH (FORMAT csv, DELIMITER '|', QUOTE E'\\x01', ESCAPE E'\\x01')"))
        #expect(!sql.contains("line_end"))
        #expect(sql.contains("CREATE INDEX en_call_sign_index"))
        #expect(!sql.contains("en_state_name_index"))
        let indexed = DatabaseSchema.postgresLicenseSQL(
            hd: "/tmp/a'b.dat",
            en: "/tmp/EN.dat",
            stateIndex: true
        )
        #expect(indexed.contains("CREATE INDEX en_state_name_index ON en (state, last_name, first_name)"))
        #expect(!sql.contains("CREATE TABLE am"))
    }

    @Test func pgPassEscapesColons() {
        var settings = ConnectionSettings.postgres
        settings.username = "fc:c"
        settings.password = "a\\b"
        let text = DatabaseUpdater.pgPass(settings: settings, databases: ["fcc"])
        #expect(text == "127.0.0.1:5432:fcc:fc\\:c:a\\\\b\n")
    }

    @Test func clientFileIsOwnerReadableOnly() throws {
        let url = URL(fileURLWithPath: "/tmp/ham-radio-query-cnf-test.cnf")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = ConnectionSettings.standard
        settings.password = "a\"b\\c"
        try DatabaseUpdater.writeClientFile(settings: settings, to: url)
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        #expect(mode.uint16Value == 0o600)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("password=\"a\\\"b\\\\c\""))
        #expect(text.contains("local-infile=1"))
    }

    @Test func columnCountsMatchTheFCCFiles() {
        #expect(DatabaseSchema.hdColumns.count == 59)
        #expect(DatabaseSchema.enColumns.count == 30)
    }

    @Test func missingAndUnreadableFilesNeedToBeCreated() {
        let missing = URL(fileURLWithPath: "/tmp/gmrs-radio-query-does-not-exist.sqlite")
        #expect(LicenseStore.freshness(at: missing) == .missing)

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("gmrs-radio-empty-\(UUID().uuidString).sqlite")
        FileManager.default.createFile(atPath: empty.path, contents: Data("not a database".utf8))
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(LicenseStore.freshness(at: empty) == .missing)
    }

    @Test func databaseOlderThanEightDaysIsStale() throws {
        let imported = try #require(LicenseStore.parse("2026-01-01T00:00:00Z"))
        let url = try Fixture.makeDatabase(importedAt: imported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let eightDays = imported.addingTimeInterval(LicenseStore.maximumAge)
        #expect(LicenseStore.freshness(at: url, now: eightDays) == .current(importedAt: imported))
        #expect(
            LicenseStore.freshness(at: url, now: eightDays.addingTimeInterval(1))
                == .stale(importedAt: imported)
        )
    }

    @Test func pipeImportCanBeSearched() async throws {
        let imported = try #require(LicenseStore.parse("2026-10-20T00:00:00Z"))
        let url = try Fixture.makeDatabase(importedAt: imported)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let database = LicenseDatabase(url: url)
        let emmett = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "",
            lastName: "",
            city: "emmett",
            state: "id",
            licenseStatuses: ["A"],
            applyTitleCase: true
        ))
        #expect(emmett.map(\.callSign) == ["WD6BQX", "KI7PSO"])

        let arthur = try #require(emmett.first)
        #expect(arthur.firstName == "Arthur")
        #expect(arthur.lastName == "Aronsen")
        #expect(arthur.streetAddress == "1501 Jordan Ln")
        #expect(arthur.city == "Emmett")
        #expect(arthur.state == "ID")
        #expect(arthur.zip == "83617")
        #expect(arthur.licenseStatus == "A")
        #expect(arthur.frn == "0002436145")

        let tony = emmett[1]
        #expect(tony.firstName == "Tony")
        #expect(tony.lastName == "Barningham")
        #expect(tony.streetAddress == "9734 Bill Burns Rd")
        #expect(tony.frn == "0026822262")

        let exact = try await database.search(LicenseQuery(
            callSign: "wd6bqx",
            firstName: "",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            applyTitleCase: true
        ))
        #expect(exact.map(\.callSign) == ["WD6BQX"])

        let byName = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "Jo_n",
            lastName: "",
            city: "",
            state: "",
            licenseStatuses: ["A"],
            applyTitleCase: false
        ))
        #expect(byName.map(\.callSign) == ["N0UND"])

        let byCity = try await database.search(LicenseQuery(
            callSign: "",
            firstName: "",
            lastName: "",
            city: "100%",
            state: "ID",
            licenseStatuses: ["A"],
            applyTitleCase: false
        ))
        #expect(byCity.map(\.callSign) == ["N0UND"])
    }
}

enum Fixture {
    static func makeDatabase(importedAt: Date) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gmrs-radio-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let hd = directory.appendingPathComponent("HD.dat")
        let en = directory.appendingPathComponent("EN.dat")
        try Data(hdText.utf8).write(to: hd)
        try Data(enText.utf8).write(to: en)

        let database = directory.appendingPathComponent("licenses.sqlite")
        try DatabaseUpdater.buildDatabase(hd: hd, en: en, to: database, importedAt: importedAt)
        return database
    }

    private static func row(_ values: [Int: String], columns: Int) -> String {
        var fields = Array(repeating: "", count: columns)
        for (index, value) in values where index < columns {
            fields[index] = value
        }
        return fields.joined(separator: "|")
    }

    private static var hdText: String {
        [
            row([0: "HD", 1: "1", 4: "WD6BQX", 5: "A"], columns: 59),
            row([0: "HD", 1: "2", 4: "KI7PSO", 5: "A"], columns: 59),
            row([0: "HD", 1: "3", 4: "N0UND", 5: "A"], columns: 59),
            row([0: "HD", 1: "4", 4: "N0OTHER", 5: "A"], columns: 59),
        ].joined(separator: "\n") + "\n"
    }

    private static var enText: String {
        [
            row([
                0: "EN", 1: "1", 4: "WD6BQX", 8: "ARTHUR", 10: "ARONSEN",
                15: "1501 JORDAN LN", 16: "EMMETT", 17: "ID", 18: "83617", 22: "0002436145",
            ], columns: 30),
            row([
                0: "EN", 1: "2", 4: "KI7PSO", 8: "TONY", 10: "BARNINGHAM",
                15: "9734 BILL BURNS RD", 16: "EMMETT", 17: "ID", 18: "83617", 22: "0026822262",
            ], columns: 30),
            row([
                0: "EN", 1: "3", 4: "N0UND", 8: "JO_N", 10: "SMITH",
                16: "100%TOWN", 17: "ID",
            ], columns: 30),
            row([
                0: "EN", 1: "4", 4: "N0OTHER", 8: "JOHN", 10: "SMITH",
                16: "1000TOWN", 17: "ID",
            ], columns: 30),
        ].joined(separator: "\n") + "\n"
    }
}
