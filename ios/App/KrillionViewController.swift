import UIKit
import WebKit

final class KrillionViewController: UIViewController, WKNavigationDelegate {
    private let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        let root = Bundle.main.resourceURL!.appendingPathComponent("www", isDirectory: true)
        configuration.setURLSchemeHandler(MirrorSchemeHandler(root: root), forURLScheme: "krillion")
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.07, blue: 0.10, alpha: 1.0)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        webView.load(URLRequest(url: URL(string: "krillion://local/index.html")!))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    override var prefersStatusBarHidden: Bool { true }
}
