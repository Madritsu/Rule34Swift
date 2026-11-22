import SwiftUI
import WebKit

#if os(macOS)
struct Rule34AuthWebView: NSViewRepresentable {
    let startURL: URL
    let onAuthenticated: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthenticated: onAuthenticated)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        let onAuthenticated: (String?) -> Void
        private var handled = false

        init(onAuthenticated: @escaping (String?) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !handled else { return }
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                guard let self, let html = result as? String else { return }
                let normalized = html.lowercased()
                guard normalized.contains("logout") || normalized.contains("my profile") || normalized.contains("my account") else { return }
                let username = self.extractUsername(from: html)
                self.handled = true
                self.syncCookiesAndFinish(username: username)
            }
        }

        private func syncCookiesAndFinish(username: String?) {
            Task { @MainActor in
                if let webView {
                    let store = webView.configuration.websiteDataStore.httpCookieStore
                    let cookies = await withCheckedContinuation { continuation in
                        store.getAllCookies { continuation.resume(returning: $0) }
                    }
                    for cookie in cookies {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                }
                onAuthenticated(username)
            }
        }

        private func extractUsername(from html: String) -> String? {
            let patterns = [
                #"page=account&s=profile&uname=([^"'<>&\s]+)"#,
                #"page=account&s=profile&uname=([^"']+)"#
            ]
            for pattern in patterns {
                if let match = html.firstCapture(of: pattern), !match.isEmpty {
                    return match.decodingHTMLEntities()
                }
            }
            return nil
        }
    }
}
#else
struct Rule34AuthWebView: UIViewRepresentable {
    let startURL: URL
    let onAuthenticated: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthenticated: onAuthenticated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        let onAuthenticated: (String?) -> Void
        private var handled = false

        init(onAuthenticated: @escaping (String?) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !handled else { return }
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                guard let self, let html = result as? String else { return }
                let normalized = html.lowercased()
                guard normalized.contains("logout") || normalized.contains("my profile") || normalized.contains("my account") else { return }
                let username = self.extractUsername(from: html)
                self.handled = true
                self.syncCookiesAndFinish(username: username)
            }
        }

        private func syncCookiesAndFinish(username: String?) {
            Task { @MainActor in
                if let webView {
                    let store = webView.configuration.websiteDataStore.httpCookieStore
                    let cookies = await withCheckedContinuation { continuation in
                        store.getAllCookies { continuation.resume(returning: $0) }
                    }
                    for cookie in cookies {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                }
                onAuthenticated(username)
            }
        }

        private func extractUsername(from html: String) -> String? {
            let patterns = [
                #"page=account&s=profile&uname=([^"'<>&\s]+)"#,
                #"page=account&s=profile&uname=([^"']+)"#
            ]
            for pattern in patterns {
                if let match = html.firstCapture(of: pattern), !match.isEmpty {
                    return match.decodingHTMLEntities()
                }
            }
            return nil
        }
    }
}
#endif
