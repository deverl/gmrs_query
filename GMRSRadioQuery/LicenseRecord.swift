import Foundation

struct LicenseRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let callSign: String
    let firstName: String
    let lastName: String
    let streetAddress: String
    let city: String
    let state: String
    let zip: String
    let licenseStatus: String
    let frn: String

    var licenseStatusName: String { LicenseStatus.title(for: licenseStatus) }

    init(
        id: UUID = UUID(),
        callSign: String,
        firstName: String,
        lastName: String,
        streetAddress: String,
        city: String,
        state: String,
        zip: String,
        licenseStatus: String,
        frn: String
    ) {
        self.id = id
        self.callSign = callSign
        self.firstName = firstName
        self.lastName = lastName
        self.streetAddress = streetAddress
        self.city = city
        self.state = state
        self.zip = zip
        self.licenseStatus = licenseStatus
        self.frn = frn
    }

    /// Case-insensitive match against every value shown in the table, plus the
    /// spelled-out license status and operator class.
    func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return true }
        let fields = [
            callSign, firstName, lastName, streetAddress, city, state, zip,
            licenseStatus, LicenseStatus.title(for: licenseStatus),
            frn,
        ]
        return fields.contains { $0.lowercased().contains(needle) }
    }

    var columns: [String] {
        [
            callSign, firstName, lastName, streetAddress, city, state, zip,
            licenseStatusName, frn,
        ]
    }

    var tabSeparated: String {
        columns.joined(separator: "\t")
    }

    static let csvHeader = [
        "Call Sign", "First Name", "Last Name", "Street Address", "City", "State",
        "ZIP", "License Status", "FRN",
    ]

    static func csv(_ records: [LicenseRecord]) -> String {
        let lines = [csvHeader.map(csvField).joined(separator: ",")]
            + records.map { $0.columns.map(csvField).joined(separator: ",") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static let samples: [LicenseRecord] = [
            LicenseRecord(
                callSign: "WQBQ753", firstName: "Ada", lastName: "Sample",
                streetAddress: "1 Main St", city: "Emmett", state: "ID", zip: "83617",
                licenseStatus: "A", frn: "0000000001"
            ),
            LicenseRecord(
                callSign: "WSKW345", firstName: "Noah", lastName: "Example",
                streetAddress: "1501 Jordan Ln", city: "Emmett", state: "ID", zip: "83617",
                licenseStatus: "A", frn: "0000000002"
            ),
            LicenseRecord(
                callSign: "KAE9526", firstName: "Ada", lastName: "Sample",
                streetAddress: "1 Main St", city: "Emmett", state: "ID", zip: "83617",
                licenseStatus: "E", frn: "0000000001"
            ),
    ]
}
