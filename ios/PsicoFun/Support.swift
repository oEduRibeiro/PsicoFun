import UIKit

/// Vibração (háptico) usada nos dois modos.
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)

    static func play(_ kind: String) {
        switch kind {
        case "selection": selection.selectionChanged()
        case "success": notification.notificationOccurred(.success)
        case "error": notification.notificationOccurred(.error)
        case "warning": notification.notificationOccurred(.warning)
        default: light.impactOccurred()
        }
    }
}
