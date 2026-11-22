import SwiftUI
import WebKit

struct Rule34CaptchaWebView: View {
    let html: String
    let onVerified: () -> Void

    var body: some View {
        #if os(macOS)
        CaptchaWebViewRepresentable(html: html, onVerified: onVerified)
        #else
        CaptchaWebViewRepresentable(html: html, onVerified: onVerified)
        #endif
    }
}

#if os(macOS)
private struct CaptchaWebViewRepresentable: NSViewRepresentable {
    let html: String
    let onVerified: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(html: html, onVerified: onVerified) }
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero); web.navigationDelegate = context.coordinator
        web.loadHTMLString(html, baseURL: URL(string: "https://rule34.xxx/")); return web
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let html: String; let onVerified: () -> Void; var first = true
        init(html: String, onVerified: @escaping () -> Void) { self.html = html; self.onVerified = onVerified }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !first else { first = false; return }
            webView.evaluateJavaScript("({text:document.body?.innerText||'',ua:navigator.userAgent})") { result, _ in
                guard let d = result as? [String:String], !(d["text"] ?? "").lowercased().contains("captcha") else { return }
                Rule34CaptchaCookieStore.sync(from: webView.configuration.websiteDataStore.httpCookieStore, userAgent: d["ua"]) { self.onVerified() }
            }
        }
    }
}
#else
private struct CaptchaWebViewRepresentable: UIViewRepresentable {
    let html: String
    let onVerified: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(html: html, onVerified: onVerified) }
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero); web.navigationDelegate = context.coordinator
        web.loadHTMLString(html, baseURL: URL(string: "https://rule34.xxx/")); return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let html: String; let onVerified: () -> Void; var first = true
        init(html: String, onVerified: @escaping () -> Void) { self.html = html; self.onVerified = onVerified }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !first else { first = false; return }
            webView.evaluateJavaScript("({text:document.body?.innerText||'',ua:navigator.userAgent})") { result, _ in
                guard let d = result as? [String:String], !(d["text"] ?? "").lowercased().contains("captcha") else { return }
                Rule34CaptchaCookieStore.sync(from: webView.configuration.websiteDataStore.httpCookieStore, userAgent: d["ua"]) { self.onVerified() }
            }
        }
    }
}
#endif

#if os(macOS)
struct Rule34WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView
        context.coordinator.load(url)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.load(url)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var currentURL: URL?

        func load(_ url: URL) {
            guard currentURL != url else { return }
            currentURL = url
            webView?.load(URLRequest(url: url))
        }
    }
}
#else
struct Rule34WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.webView = webView
        context.coordinator.load(url)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.load(url)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var currentURL: URL?

        func load(_ url: URL) {
            guard currentURL != url else { return }
            currentURL = url
            webView?.load(URLRequest(url: url))
        }
    }
}
#endif
