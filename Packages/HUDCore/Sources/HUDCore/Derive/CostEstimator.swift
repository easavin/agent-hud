import Foundation

/// API-equivalent cost of a usage record. On a subscription nothing is billed per token,
/// so treat the result as "what this would cost on the API".
public enum CostEstimator {
    /// USD per million tokens.
    public struct Price: Sendable {
        public var input: Double
        public var output: Double
        /// Cache reads are 0.1× input unless a model overrides it.
        public var cacheRead: Double?
    }

    /// First-party API list prices, matched by substring of the model id. Most specific first.
    public static let prices: [(match: String, price: Price)] = [
        ("fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("mythos-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("fable", Price(input: 10, output: 50)),
        ("mythos", Price(input: 10, output: 50)),
        ("opus", Price(input: 5, output: 25)),
        ("sonnet-5", Price(input: 2, output: 10)),
        ("sonnet", Price(input: 3, output: 15)),
        ("haiku", Price(input: 1, output: 5)),
    ]

    public static func price(for model: String) -> Price {
        prices.first { model.contains($0.match) }?.price ?? Price(input: 5, output: 25)
    }

    public static func cost(of usage: TokenUsage, model: String) -> Double {
        let price = price(for: model)
        let write5m = Double(usage.cacheCreation - usage.cacheCreation1h) * price.input * 1.25
        let write1h = Double(usage.cacheCreation1h) * price.input * 2
        let read = Double(usage.cacheRead) * (price.cacheRead ?? price.input * 0.1)
        return (Double(usage.input) * price.input + Double(usage.output) * price.output + write5m + write1h + read) / 1_000_000
    }

    /// "claude-fable-5-1" → "fable-5.1", "claude-haiku-4-5-20251001" → "haiku-4.5".
    public static func shortName(_ model: String) -> String {
        var parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        parts.removeAll { $0.count == 8 && Int($0) != nil }
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family : "\(family)-\(version)"
    }
}
