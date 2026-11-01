import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let main = MainViewController()
        window.rootViewController = main
        window.makeKeyAndVisible()
        self.window = window
        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { main.handleDeepLink(url) }
        }
    }

    // klassentakt://auth?code=… (Rückkehr vom Login im Browser)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url,
              let main = window?.rootViewController as? MainViewController else { return }
        main.handleDeepLink(url)
    }
}

/// Szene für den externen Bildschirm (Beamer). Zeigt den Classroom Screen, sobald er offen ist.
final class BeamerSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = Beamer.shared.externalController
        window.isHidden = false
        self.window = window
        Beamer.shared.externalConnected(true)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Beamer.shared.externalConnected(false)
        window = nil
    }
}
