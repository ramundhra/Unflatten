import Foundation

enum MathTextRole: Equatable, Sendable {
    case normal
    case subscriptText
    case superscriptText
    case fractionNumerator
    case fractionDenominator
}

struct MathTextSegment: Equatable, Sendable {
    var text: String
    let role: MathTextRole
}

/// A small, local LaTeX-style parser for the inline math features supported by
/// the image editor. It intentionally preserves unknown commands as literal
/// text instead of silently dropping user input.
enum MathTextParser {
    static func parse(_ source: String) -> [MathTextSegment] {
        var parser = Parser(characters: Array(source))
        return parser.parse(role: .normal, until: nil)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        mutating func parse(
            role: MathTextRole,
            until closingCharacter: Character?
        ) -> [MathTextSegment] {
            var segments: [MathTextSegment] = []

            while index < characters.count {
                let character = characters[index]
                if character == closingCharacter {
                    index += 1
                    break
                }

                switch character {
                case "\\":
                    index += 1
                    append(contentsOf: parseCommand(defaultRole: role), to: &segments)
                case "_":
                    index += 1
                    append(
                        contentsOf: parseArgument(role: .subscriptText),
                        to: &segments
                    )
                case "^":
                    index += 1
                    append(
                        contentsOf: parseArgument(role: .superscriptText),
                        to: &segments
                    )
                case "{":
                    index += 1
                    append(
                        contentsOf: parse(role: role, until: "}"),
                        to: &segments
                    )
                default:
                    index += 1
                    append(String(character), role: role, to: &segments)
                }
            }

            return segments
        }

        private mutating func parseArgument(
            role: MathTextRole
        ) -> [MathTextSegment] {
            guard index < characters.count else { return [] }

            if characters[index] == "{" {
                index += 1
                return parse(role: role, until: "}")
            }

            if characters[index] == "\\" {
                index += 1
                return parseCommand(defaultRole: role).map {
                    MathTextSegment(text: $0.text, role: role)
                }
            }

            let character = characters[index]
            index += 1
            return [MathTextSegment(text: String(character), role: role)]
        }

        private mutating func parseCommand(
            defaultRole: MathTextRole
        ) -> [MathTextSegment] {
            guard index < characters.count else {
                return [MathTextSegment(text: "\\", role: defaultRole)]
            }

            if !characters[index].isLetter {
                let escaped = characters[index]
                index += 1
                let literal: Character
                switch escaped {
                case "_", "^", "{", "}", "\\":
                    literal = escaped
                case " ", ",":
                    literal = " "
                default:
                    return [
                        MathTextSegment(
                            text: "\\" + String(escaped),
                            role: defaultRole
                        )
                    ]
                }
                return [MathTextSegment(text: String(literal), role: defaultRole)]
            }

            let command = readCommandName()
            switch command {
            case "frac":
                let numerator = parseArgument(role: .fractionNumerator)
                let denominator = parseArgument(role: .fractionDenominator)
                guard !numerator.isEmpty, !denominator.isEmpty else {
                    return [MathTextSegment(text: "\\frac", role: defaultRole)]
                        + numerator
                        + denominator
                }
                return numerator
                    + [MathTextSegment(text: "⁄", role: defaultRole)]
                    + denominator
            case "sqrt":
                return [MathTextSegment(text: "√", role: defaultRole)]
                    + parseArgument(role: defaultRole)
            case "text":
                return parseArgument(role: defaultRole)
            default:
                if let symbol = Self.symbols[command] {
                    return [MathTextSegment(text: symbol, role: defaultRole)]
                }
                return [
                    MathTextSegment(
                        text: "\\" + command,
                        role: defaultRole
                    )
                ]
            }
        }

        private mutating func readCommandName() -> String {
            let start = index
            while index < characters.count, characters[index].isLetter {
                index += 1
            }
            return String(characters[start..<index])
        }

        private func append(
            contentsOf newSegments: [MathTextSegment],
            to segments: inout [MathTextSegment]
        ) {
            for segment in newSegments {
                append(segment.text, role: segment.role, to: &segments)
            }
        }

        private func append(
            _ text: String,
            role: MathTextRole,
            to segments: inout [MathTextSegment]
        ) {
            guard !text.isEmpty else { return }
            if let lastIndex = segments.indices.last,
               segments[lastIndex].role == role {
                segments[lastIndex].text += text
            } else {
                segments.append(MathTextSegment(text: text, role: role))
            }
        }

        private static let symbols: [String: String] = [
            "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
            "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ",
            "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ",
            "phi": "φ", "psi": "ψ", "omega": "ω",
            "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ",
            "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ",
            "Omega": "Ω", "times": "×", "div": "÷", "pm": "±",
            "cdot": "·", "leq": "≤", "geq": "≥", "neq": "≠",
            "approx": "≈", "infty": "∞", "degree": "°", "partial": "∂",
            "sum": "∑", "prod": "∏", "int": "∫", "rightarrow": "→",
            "leftarrow": "←"
        ]
    }
}
