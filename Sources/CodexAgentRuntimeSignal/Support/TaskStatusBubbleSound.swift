import Foundation

enum TaskStatusBubbleSound: String, CaseIterable, Hashable {
    case off
    case glass = "Glass"
    case ping = "Ping"
    case pop = "Pop"
    case tink = "Tink"
    case hero = "Hero"
    case submarine = "Submarine"

    var soundName: String? {
        switch self {
        case .off:
            return nil
        case .glass, .ping, .pop, .tink, .hero, .submarine:
            return rawValue
        }
    }
}
