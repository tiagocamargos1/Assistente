import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        let bridgeVC = CAPBridgeViewController()
        window?.rootViewController = bridgeVC
        window?.makeKeyAndVisible()
        showLoadingOverlay(on: bridgeVC)

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    // Evita o ecrã em branco enquanto o site remoto (server.url) carrega.
    private func showLoadingOverlay(on bridgeVC: CAPBridgeViewController) {
        guard let window = window else { return }
        let overlay = UIView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor(red: 0.043, green: 0.071, blue: 0.157, alpha: 1)
        overlay.accessibilityViewIsModal = true

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        let label = UILabel()
        label.text = "A carregar…"
        label.textColor = UIColor(white: 1, alpha: 0.75)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isAccessibilityElement = true

        overlay.addSubview(spinner)
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -12),
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14)
        ])
        window.addSubview(overlay)

        let started = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
            let webView = bridgeVC.webView
            let loaded = webView != nil && webView?.isLoading == false && webView?.url != nil
                && webView?.url?.absoluteString != "about:blank"
            if loaded || Date().timeIntervalSince(started) > 30 {
                t.invalidate()
                UIView.animate(withDuration: 0.25, animations: { overlay.alpha = 0 }) { _ in
                    overlay.removeFromSuperview()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
