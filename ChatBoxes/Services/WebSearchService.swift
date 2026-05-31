import Foundation
import WebKit

@MainActor
final class WebSearchService {
    static let shared = WebSearchService()

    func searchSummary(query: String, settings: AppSettings) async -> (summary: String, results: [WebSearchResultItem]) {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return ("", []) }

        let engine = WebSearchEngineOption(rawValue: settings.webSearchEngine.lowercased()) ?? .bing
        let limit = min(15, max(3, settings.webSearchResultLimit))
        let excludeSites = excludedSites(from: settings.webSearchExcludeSites)
        print("[WebSearch] query=\(keyword)")
        print("[WebSearch] engine=\(engine.rawValue)")

        if engine == .tavily {
            let results = await searchWithTavily(
                query: keyword,
                language: settings.webSearchLang,
                apiKey: settings.tavilyAPIKey,
                limit: limit,
                excludeSites: excludeSites
            )
            let lines = results.map { result in
                let snippet = result.snippet.isEmpty ? "无摘要" : result.snippet
                return "- \(result.title)：\(snippet)（来源：\(result.url)）"
            }
            if lines.isEmpty {
                return ("", [])
            }
            return (lines.joined(separator: "\n"), results)
        }

        guard let url = engine.searchURL(for: keyword, language: settings.webSearchLang) else {
            print("[WebSearch] url=<invalid>")
            return ("", [])
        }
        print("[WebSearch] url=\(url.absoluteString)")

        let loader = SearchPageLoader(url: url, extractorScript: engine.extractorScript)
        let payload = await loader.loadAndExtract()
        print("[WebSearch] payload=\(payload ?? "<nil>")")
        let results = parseResults(from: payload)
            .filter { result in
                !excludeSites.contains(where: { site in
                    result.url.localizedCaseInsensitiveContains(site)
                })
            }
            .prefix(limit)

        let searchResults = results.map { result in
            WebSearchResultItem(title: result.title, snippet: result.snippet, url: result.url)
        }
        print("[WebSearch] parsed result count=\(searchResults.count)")

        let lines = searchResults.map { result in
            let snippet = result.snippet.isEmpty ? "无摘要" : result.snippet
            return "- \(result.title)：\(snippet)（来源：\(result.url)）"
        }

        if lines.isEmpty {
            return ("", [])
        }
        return (lines.joined(separator: "\n"), searchResults)
    }

    private func parseResults(from payload: String?) -> [WebSearchResult] {
        guard let payload,
              let data = payload.data(using: .utf8),
              let results = try? JSONDecoder().decode([WebSearchResult].self, from: data) else {
            return []
        }
        return results.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func excludedSites(from rawValue: String) -> [String] {
        rawValue
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func searchWithTavily(
        query: String,
        language: String,
        apiKey: String,
        limit: Int,
        excludeSites: [String]
    ) async -> [WebSearchResultItem] {
        let normalizedKey = normalizeAPIKey(apiKey)
        guard !normalizedKey.isEmpty else {
            print("[WebSearch] tavily api key missing")
            return []
        }

        guard let url = URL(string: "https://api.tavily.com/search") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var payload: [String: Any] = [
            "api_key": normalizedKey,
            "query": query,
            "search_depth": "advanced",
            "max_results": limit,
            "include_answer": false,
            "include_raw_content": false
        ]
        if !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["topic"] = "general"
        }
        if !excludeSites.isEmpty {
            payload["exclude_domains"] = excludeSites
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[WebSearch] tavily invalid response")
                return []
            }
            guard 200..<300 ~= http.statusCode else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[WebSearch] tavily status=\(http.statusCode) body=\(body)")
                return []
            }
            let decoded = try JSONDecoder().decode(TavilySearchResponse.self, from: data)
            let results = decoded.results
                .filter { item in
                    !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !item.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .prefix(limit)
                .map { item in
                    WebSearchResultItem(
                        title: item.title,
                        snippet: item.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        url: item.url
                    )
                }
            print("[WebSearch] tavily parsed result count=\(results.count)")
            return Array(results)
        } catch {
            print("[WebSearch] tavily request failed error=\(error.localizedDescription)")
            return []
        }
    }
}

private struct WebSearchResult: Codable {
    let title: String
    let snippet: String
    let url: String
}

private struct TavilySearchResponse: Codable {
    let results: [TavilySearchResult]
}

private struct TavilySearchResult: Codable {
    let title: String
    let url: String
    let content: String?
}

private extension WebSearchEngineOption {
    func searchURL(for query: String, language: String) -> URL? {
        var components = URLComponents()
        switch self {
        case .bing:
            components.scheme = "https"
            components.host = "www.bing.com"
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "setlang", value: normalizedBingLanguage(language))
            ]
        case .google:
            components.scheme = "https"
            components.host = "www.google.com"
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "hl", value: normalizedGoogleLanguage(language))
            ]
        case .baidu:
            components.scheme = "https"
            components.host = "www.baidu.com"
            components.path = "/s"
            components.queryItems = [
                URLQueryItem(name: "wd", value: query)
            ]
        case .duckduckgo:
            components.scheme = "https"
            components.host = "html.duckduckgo.com"
            components.path = "/html/"
            components.queryItems = [
                URLQueryItem(name: "q", value: query)
            ]
        case .tavily:
            return nil
        }
        return components.url
    }

    var extractorScript: String {
        switch self {
        case .bing:
            return """
            (() => {
              const items = Array.from(document.querySelectorAll('li.b_algo')).slice(0, 8);
              return JSON.stringify(items.map(item => {
                const link = item.querySelector('h2 a');
                const snippet = item.querySelector('.b_caption p, .b_lineclamp3, .b_paractl');
                return {
                  title: (link?.innerText || '').trim(),
                  snippet: (snippet?.innerText || '').trim(),
                  url: link?.href || ''
                };
              }).filter(item => item.title && item.url));
            })();
            """
        case .google:
            return """
            (() => {
              const items = Array.from(document.querySelectorAll('div.g')).slice(0, 8);
              return JSON.stringify(items.map(item => {
                const link = item.querySelector('a[href]');
                const title = item.querySelector('h3');
                const snippet = item.querySelector('.VwiC3b, .yXK7lf, .s3v9rd');
                return {
                  title: (title?.innerText || '').trim(),
                  snippet: (snippet?.innerText || '').trim(),
                  url: link?.href || ''
                };
              }).filter(item => item.title && item.url));
            })();
            """
        case .baidu:
            return """
            (() => {
              const items = Array.from(document.querySelectorAll('.result, .c-container')).slice(0, 8);
              return JSON.stringify(items.map(item => {
                const link = item.querySelector('h3 a, a');
                const snippet = item.querySelector('.c-abstract, .content-right_8Zs40, .c-span-last');
                return {
                  title: (link?.innerText || '').trim(),
                  snippet: (snippet?.innerText || '').trim(),
                  url: link?.href || ''
                };
              }).filter(item => item.title && item.url));
            })();
            """
        case .duckduckgo:
            return """
            (() => {
              const items = Array.from(document.querySelectorAll('.result')).slice(0, 8);
              return JSON.stringify(items.map(item => {
                const link = item.querySelector('.result__title a, a.result__a');
                const snippet = item.querySelector('.result__snippet');
                return {
                  title: (link?.innerText || '').trim(),
                  snippet: (snippet?.innerText || '').trim(),
                  url: link?.href || ''
                };
              }).filter(item => item.title && item.url));
            })();
            """
        case .tavily:
            return ""
        }
    }

    private func normalizedBingLanguage(_ value: String) -> String {
        value.isEmpty ? "zh-Hans" : value
    }

    private func normalizedGoogleLanguage(_ value: String) -> String {
        if value.isEmpty { return "zh-CN" }
        return value
    }
}

@MainActor
private final class SearchPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let request: URLRequest
    private let extractorScript: String
    private var continuation: CheckedContinuation<String?, Never>?
    private var hasCompleted = false

    init(url: URL, extractorScript: String) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.extractorScript = extractorScript
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        self.request = request
        super.init()
        webView.navigationDelegate = self
        webView.isHidden = true
    }

    func loadAndExtract() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.load(request)

            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extractResults()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    private func extractResults() {
        webView.evaluateJavaScript(extractorScript) { [weak self] result, _ in
            self?.finish(with: result as? String)
        }
    }

    private func finish(with result: String?) {
        guard !hasCompleted else { return }
        hasCompleted = true
        continuation?.resume(returning: result)
        continuation = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
    }
}
