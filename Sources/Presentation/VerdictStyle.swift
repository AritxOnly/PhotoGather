import SwiftUI

extension Verdict {
    var icon: String {
        switch self {
        case .fresh: return "plus.circle"
        case .duplicate: return "square.on.square"
        case .review: return "rectangle.on.rectangle.angled"
        case .screenshot: return "viewfinder"
        case .failed: return "exclamationmark.triangle"
        case .imported: return "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .fresh, .imported: return .green
        case .duplicate: return .secondary
        case .review: return .orange
        case .screenshot: return .indigo
        case .failed: return .red
        }
    }
}
