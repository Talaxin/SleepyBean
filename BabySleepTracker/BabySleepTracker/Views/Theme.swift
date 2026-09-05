import SwiftUI

enum AppTheme {
    static let sleepPurple = Color(red: 0.45, green: 0.35, blue: 0.78)
    static let sleepPurpleLight = Color(red: 0.55, green: 0.45, blue: 0.88)
    static let wakePeach = Color(red: 0.98, green: 0.72, blue: 0.55)
    static let wakeCoral = Color(red: 0.95, green: 0.55, blue: 0.45)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let softBackground = Color(.systemGroupedBackground)

    static let napGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.45, blue: 0.88), Color(red: 0.40, green: 0.30, blue: 0.72)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let wakeGradient = LinearGradient(
        colors: [Color(red: 0.98, green: 0.75, blue: 0.55), Color(red: 0.95, green: 0.55, blue: 0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
