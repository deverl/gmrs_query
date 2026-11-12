import Foundation

/// FCC ULS license status codes from the HD file.
enum LicenseStatus: String, CaseIterable, Identifiable, Sendable {
    case active = "A"
    case canceled = "C"
    case expired = "E"
    case pendingLegal = "L"
    case parentCanceled = "P"
    case terminated = "T"
    case termPending = "X"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "Active"
        case .canceled: "Canceled"
        case .expired: "Expired"
        case .pendingLegal: "Pending Legal Status"
        case .parentCanceled: "Parent Station Canceled"
        case .terminated: "Terminated"
        case .termPending: "Term Pending"
        }
    }

    static func title(for code: String) -> String {
        LicenseStatus(rawValue: code)?.title ?? code
    }
}
