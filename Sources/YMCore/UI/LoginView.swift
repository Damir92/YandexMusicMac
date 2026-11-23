import SwiftUI
import AppKit
import WebKit

/// Native macOS authentication screen with automatic OAuth token interception
/// and explicit WebKit process teardown upon login completion.
public struct LoginView: View {
    @UIState private var authService = AuthService.shared
    @UIState private var manualInput: String = ""
    @UIState private var showOAuthSheet: Bool = false

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                // Header & Logo with soft accent glow
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(YMTheme.accent.opacity(YMTheme.isLight ? 0.16 : 0.22))
                            .frame(width: 88, height: 88)
                            .blur(radius: 16)

                        if let appIcon = NSApp?.applicationIconImage {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 78, height: 78)
                        } else {
                            Circle()
                                .fill(YMTheme.surface)
                                .frame(width: 68, height: 68)
                                .overlay(
                                    Circle()
                                        .strokeBorder(YMTheme.border, lineWidth: 1)
                                )
                                .shadow(color: YMTheme.shadowColor, radius: 12, y: 4)

                            Image(systemName: "music.note.house.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(YMTheme.accent)
                        }
                    }

                    Text("flow~")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(YMTheme.fg)

                    Text("Нативный клиент Яндекс Музыки для macOS")
                        .font(.subheadline)
                        .foregroundStyle(YMTheme.fg60)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .background(YMWindowDragHandle())

                // Error display banner
                if let error = authService.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(YMTheme.heartRed)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(YMTheme.heartRed)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .frame(maxWidth: 440, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(YMTheme.heartRed.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(YMTheme.heartRed.opacity(0.25), lineWidth: 1)
                            )
                    )
                }

                VStack(spacing: 16) {
                    // MARK: - Способ 1: Автоматический вход через окно OAuth
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Способ 1. Быстрый вход через Яндекс ID")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(YMTheme.fg)

                        VStack(spacing: 10) {
                            Button {
                                authService.errorMessage = nil
                                showOAuthSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.badge.key.fill")
                                    Text("Войти через окно OAuth")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 36))
                            .disabled(authService.isAuthenticating)

                            Button {
                                authService.openOAuthInBrowser()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "safari")
                                    Text("Открыть страницу авторизации в браузере")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(YMGlassPillButtonStyle(primary: false, height: 32))
                            .disabled(authService.isAuthenticating)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(YMTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(YMTheme.border, lineWidth: 1)
                            )
                            .shadow(color: YMTheme.shadowColor, radius: 8, y: 2)
                    )

                    // MARK: - Способ 2: Ручной ввод токена или ссылки
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Способ 2. Ввод токена или ссылки редиректа")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(YMTheme.fg)

                        Text("Вставьте OAuth-токен (y0_...) или скопируйте адресную строку из браузера после входа")
                            .font(.caption)
                            .foregroundStyle(YMTheme.fg60)

                        HStack(spacing: 8) {
                            TextField("Токен или URL редиректа", text: $manualInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundStyle(YMTheme.fg)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(YMTheme.surfaceComponent)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(YMTheme.border, lineWidth: 1)
                                        )
                                )
                                .disabled(authService.isAuthenticating)

                            Button {
                                if let clipboard = NSPasteboard.general.string(forType: .string) {
                                    let extracted = AuthService.extractToken(from: clipboard)
                                    manualInput = extracted.isEmpty
                                        ? clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                                        : extracted
                                }
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .buttonStyle(YMGlassPillButtonStyle(primary: false, height: 34))
                            .help("Вставить из буфера обмена")
                            .disabled(authService.isAuthenticating)
                        }

                        Button {
                            let tokenToSubmit = manualInput
                            Task {
                                await authService.submitManualToken(tokenToSubmit)
                                if authService.isAuthenticated {
                                    manualInput = ""
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Подтвердить и войти")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 36))
                        .opacity(manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1.0)
                        .disabled(manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authService.isAuthenticating)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(YMTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(YMTheme.border, lineWidth: 1)
                            )
                            .shadow(color: YMTheme.shadowColor, radius: 8, y: 2)
                    )
                }
                .frame(maxWidth: 440)

                if authService.isAuthenticating {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Проверка сессии через api.music.yandex.net...")
                            .font(.caption)
                            .foregroundStyle(YMTheme.fg60)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .ymScreenBackground()
        .frame(minWidth: 420, minHeight: 360)
        .sheet(isPresented: $showOAuthSheet) {
            OAuthSheetView(isPresented: $showOAuthSheet) { token in
                showOAuthSheet = false
                Task {
                    await authService.submitManualToken(token)
                }
            }
        }
    }
}

// MARK: - Ephemeral OAuth Sheet with Automatic Process Release

private struct OAuthSheetView: View {
    @Binding var isPresented: Bool
    let onTokenReceived: (String) -> Void
    @UIState private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Авторизация Яндекс ID")
                    .font(.headline)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                }

                Spacer()

                Button("Закрыть") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let url = URL(string: "\(AuthService.oauthURLString)&force_confirm=yes") {
                OAuthInterceptionWebView(url: url, isLoading: $isLoading, onTokenExtracted: onTokenReceived)
                    .frame(minWidth: 480, minHeight: 560)
            }
        }
        .frame(width: 520, height: 620)
    }
}

private struct OAuthInterceptionWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let onTokenExtracted: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Используем nonPersistent() хранилище: нулевой след на диске и гарантированная выгрузка процесса WebContent
        config.websiteDataStore = .nonPersistent()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.startObserving(webView: webView)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
        nsView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {}
        nsView.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: OAuthInterceptionWebView
        private weak var webView: WKWebView?
        private var urlObservation: NSKeyValueObservation?
        private var hasExtractedToken = false

        init(parent: OAuthInterceptionWebView) {
            self.parent = parent
        }

        func startObserving(webView: WKWebView) {
            self.webView = webView
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.hasExtractedToken, let urlString = self.webView?.url?.absoluteString else { return }
                    self.interceptIfNeeded(urlString, webView: self.webView)
                }
            }
        }

        func stopObserving() {
            urlObservation?.invalidate()
            urlObservation = nil
            webView = nil
        }

        private func interceptIfNeeded(_ urlString: String, webView: WKWebView?) {
            guard !hasExtractedToken else { return }
            if urlString.contains("access_token=") {
                let token = AuthService.extractToken(from: urlString)
                if !token.isEmpty {
                    hasExtractedToken = true
                    stopObserving()
                    webView?.stopLoading()
                    webView?.loadHTMLString("", baseURL: nil)
                    parent.isLoading = false
                    parent.onTokenExtracted(token)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            if let urlString = webView.url?.absoluteString {
                interceptIfNeeded(urlString, webView: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if let urlString = navigationAction.request.url?.absoluteString {
                if urlString.contains("access_token=") {
                    let token = AuthService.extractToken(from: urlString)
                    if !token.isEmpty {
                        hasExtractedToken = true
                        stopObserving()
                        // Отменяем переход на тяжелый сайт music.yandex.ru — нам нужен только токен из URL!
                        decisionHandler(.cancel)
                        webView.loadHTMLString("", baseURL: nil)
                        parent.isLoading = false
                        parent.onTokenExtracted(token)
                        return
                    }
                }
            }
            decisionHandler(.allow)
        }
    }
}
