import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.rootViewController = RootContainerViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

enum Theme {
    /// Mesma cor de fundo do app web (--bg), para não piscar branco/preto ao abrir.
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x0F / 255, green: 0x11 / 255, blue: 0x14 / 255, alpha: 1)
            : UIColor(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xF2 / 255, alpha: 1)
    }
}
