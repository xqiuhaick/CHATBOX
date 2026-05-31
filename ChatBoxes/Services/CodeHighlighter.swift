import AppKit
import Foundation

enum CodeHighlighter {
    static func highlight(code: String, language: String) -> AttributedString {
        let ns = NSMutableAttributedString(string: code, attributes: baseAttributes)
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let looksLikeMarkup =
            ["html", "htm", "svg", "xml", "xhtml"].contains(normalizedLanguage) ||
            code.localizedCaseInsensitiveContains("<svg") ||
            code.contains("</") ||
            code.contains("/>")

        if looksLikeMarkup {
            applyMarkupHighlighting(to: ns)
        } else {
            applyComments(to: ns, language: normalizedLanguage)
            apply(pattern: #"\"([^\"\\]|\\.)*\"|'([^'\\]|\\.)*'"#, color: .systemGreen, to: ns)
            applyKeywords(for: normalizedLanguage, to: ns)
            apply(pattern: #"\b([0-9]+(\.[0-9]+)?)\b"#, color: .systemOrange, to: ns)
            apply(pattern: #"\b([A-Z][A-Za-z0-9_]+)(?=\()|\b([A-Z][A-Za-z0-9_]+)(?=\s*\{)"#, color: .systemTeal, to: ns)
        }

        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(code)
    }

    private static var baseAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
    }

    private static func applyMarkupHighlighting(to ns: NSMutableAttributedString) {
        apply(pattern: #"<!--[\s\S]*?-->"#, color: .secondaryLabelColor, to: ns)
        apply(pattern: #"</?[A-Za-z][A-Za-z0-9:-]*"#, color: .systemBlue, to: ns)
        apply(pattern: #"/?>"#, color: .systemBlue, to: ns)
        apply(pattern: #"\s[A-Za-z_:][-A-Za-z0-9_:.]*(?=\=)"#, color: .systemPurple, to: ns)
        apply(pattern: #"(?<=\=)\"[^\"]*\"|(?<=\=)'[^']*'"#, color: .systemGreen, to: ns)
    }

    private static func applyComments(to ns: NSMutableAttributedString, language: String) {
        switch language {
        case "python", "ruby", "bash", "sh", "yaml", "yml", "dockerfile", "toml":
            apply(pattern: #"(?m)#.*$"#, color: .secondaryLabelColor, to: ns)
        case "sql":
            apply(pattern: #"(?m)--.*$"#, color: .secondaryLabelColor, to: ns)
        default:
            apply(pattern: #"(?m)//.*$"#, color: .secondaryLabelColor, to: ns)
        }
        apply(pattern: #"(?s)/\*.*?\*/"#, color: .secondaryLabelColor, to: ns)
    }

    private static func applyKeywords(for language: String, to ns: NSMutableAttributedString) {
        switch language {
        case "swift":
            apply(pattern: #"\b(actor|associatedtype|async|await|break|case|catch|class|continue|default|defer|deinit|do|else|enum|extension|fallthrough|false|fileprivate|final|for|func|guard|if|import|in|init|inout|internal|is|let|macro|mutating|nil|nonisolated|open|operator|override|package|precedencegroup|private|protocol|public|repeat|rethrows|return|self|some|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\b"#, color: .systemPurple, to: ns)
        case "python", "py":
            apply(pattern: #"\b(and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#, color: .systemPurple, to: ns)
        case "sql":
            apply(pattern: #"\b(select|from|where|join|left|right|inner|outer|on|group|order|by|limit|offset|insert|update|delete|create|drop|alter|table|index|view|values|into|set|having|distinct|union|all|and|or|not|null|primary|key|foreign|references|as|exists|case|when|then|else|end)\b"#, color: .systemPurple, to: ns)
        case "json":
            apply(pattern: #"\b(true|false|null)\b"#, color: .systemPurple, to: ns)
        case "bash", "sh", "zsh":
            apply(pattern: #"\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|export|local|in)\b"#, color: .systemPurple, to: ns)
        case "rust", "rs":
            apply(pattern: #"\b(as|async|await|break|const|continue|crate|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while)\b"#, color: .systemPurple, to: ns)
        case "go", "golang":
            apply(pattern: #"\b(break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b"#, color: .systemPurple, to: ns)
        default:
            apply(pattern: #"\b(function|return|if|else|for|while|class|struct|enum|protocol|import|export|async|await|try|catch|throw|public|private|internal|final|true|false|null|nil|new|def|lambda|from|package|interface|type|case|switch|guard|where|in|let|var|const|static|void|fun|func|match|mut|impl|trait|use|pub|self|super|extends|implements|yield|break|continue)\b"#, color: .systemPurple, to: ns)
        }
    }

    private static func apply(pattern: String, color: NSColor, to attributed: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let range = NSRange(location: 0, length: attributed.string.utf16.count)
        for match in regex.matches(in: attributed.string, range: range) {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
