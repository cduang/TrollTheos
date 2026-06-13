import UIKit

/// 基础语法高亮规则
enum SyntaxHighlighter {
    struct Rule {
        let pattern: String
        let color: UIColor
        let options: NSRegularExpression.Options
    }

    static func highlight(_ text: String, language: SyntaxLanguage) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.label
            ]
        )

        let rules = rules(for: language)
        let nsText = text as NSString

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                attributed.addAttribute(.foregroundColor, value: rule.color, range: match.range)
            }
        }

        return attributed
    }

    private static func rules(for language: SyntaxLanguage) -> [Rule] {
        let comment = Rule(pattern: "//.*$|/\\*.*?\\*/", color: .systemGreen, options: [.anchorsMatchLines, .dotMatchesLineSeparators])
        let string = Rule(pattern: "\"(?:\\\\.|[^\"])*\"|'(?:\\\\.|[^'])*'", color: .systemOrange, options: [])
        let preprocessor = Rule(pattern: "#\\w+", color: .systemPurple, options: [])
        let keyword = Rule(pattern: "\\b(substrate|hook|class|new|return|if|else|for|while|static|void|int|BOOL|NSString|NSArray|NSDictionary)\\b", color: .systemBlue, options: [])

        switch language {
        case .logos:
            let logosHook = Rule(pattern: "%\\w+", color: .systemPink, options: [])
            return [comment, string, preprocessor, keyword, logosHook]
        case .makefile:
            let target = Rule(pattern: "^[\\w/.-]+(?=\\s*:)", color: .systemTeal, options: [.anchorsMatchLines])
            let variable = Rule(pattern: "\\$\\([\\w]+\\)|\\$\\{[\\w]+\\}", color: .systemIndigo, options: [])
            return [comment, target, variable]
        case .plain:
            return [comment, string]
        }
    }
}
