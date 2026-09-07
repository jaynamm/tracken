import Foundation

/// All rates are USD per million tokens. Missing prices are never treated as free.
nonisolated struct TokenPrice: Codable, Equatable, Sendable {
    let input: Double
    let cachedInput: Double?
    let cacheWrite: Double?
    let output: Double
    var cacheWrite1h: Double? = nil
    var longContext: ContextPrice? = nil

    struct ContextPrice: Codable, Equatable, Sendable {
        let input: Double
        let cachedInput: Double?
        let cacheWrite: Double?
        let output: Double
    }

    func cost(input: Int, cached: Int, write: Int, write1h: Int = 0,
              output: Int, contextTokens: Int = 0) -> Double? {
        let long = contextTokens > 272_000 ? longContext : nil
        let inputRate = long?.input ?? self.input
        let outputRate = long?.output ?? self.output
        let readRate = long == nil ? cachedInput : long?.cachedInput
        let writeRate = long == nil ? cacheWrite : long?.cacheWrite
        guard cached == 0 || readRate != nil,
              write == 0 || writeRate != nil,
              write1h == 0 || cacheWrite1h != nil else { return nil }
        return (Double(input) * inputRate + Double(cached) * (readRate ?? 0)
                + Double(write) * (writeRate ?? 0) + Double(write1h) * (cacheWrite1h ?? 0)
                + Double(output) * outputRate) / 1_000_000
    }

    var isValid: Bool {
        let values = [input, cachedInput, cacheWrite, output, cacheWrite1h,
                      longContext?.input, longContext?.cachedInput, longContext?.cacheWrite, longContext?.output]
        return values.compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 10_000 }
    }
}

nonisolated struct PricingSnapshot: Codable, Equatable, Sendable {
    let providerID: String
    var checkedAt: Date
    var isBundled: Bool
    let rates: [String: TokenPrice]
    var etag: String?
    var lastModified: String?

    func rate(for model: String) -> TokenPrice? {
        let model = model.lowercased()
        if let exact = rates[model] { return exact }
        // Only dated snapshots inherit a base price, never arbitrary suffixes
        // such as '-pro', '-fast', or a new model family.
        for key in rates.keys.sorted(by: { $0.count > $1.count }) where model.hasPrefix(key + "-") {
            let suffix = String(model.dropFirst(key.count + 1))
            if suffix.range(of: #"^(\d{8}|\d{4}-\d{2}-\d{2})$"#, options: .regularExpression) != nil {
                return rates[key]
            }
        }
        return nil
    }

    static func bundled(for provider: AIProvider) -> PricingSnapshot {
        let text = provider == .codex ? PricingDefaults.openAI : PricingDefaults.claude
        return PricingSnapshot(providerID: provider.rawValue,
                               checkedAt: Date(timeIntervalSince1970: 1_788_739_200),
                               isBundled: true,
                               rates: (try? OfficialPricingParser.parse(text, provider: provider)) ?? [:])
    }
}

nonisolated enum PricingError: Error, LocalizedError {
    case invalidDocument
    case downloadFailed
    var errorDescription: String? {
        switch self {
        case .invalidDocument: "The official price table could not be validated. Keeping the previous prices."
        case .downloadFailed: "Could not download the official price table. Keeping the previous prices."
        }
    }
}

/// Strictly reads the standard text-token table, excluding Batch/Fast/tool tables.
nonisolated enum OfficialPricingParser {
    static func parse(_ text: String, provider: AIProvider) throws -> [String: TokenPrice] {
        let heading = provider == .codex ? "### Standard pricing data" : "## Model pricing"
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else {
            throw PricingError.invalidDocument
        }
        let expected = provider == .codex
            ? ["Model", "Short context input", "Short context cached input", "Short context cache writes", "Short context output", "Long context input", "Long context cached input", "Long context cache writes", "Long context output"]
            : ["Model", "Base input tokens", "5m cache writes", "1h cache writes", "Cache hits and refreshes", "Output tokens"]
        var foundHeader = false
        var rates: [String: TokenPrice] = [:]
        for line in lines.dropFirst(start + 1) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { break }
            guard line.hasPrefix("|") else {
                if !rates.isEmpty { break }
                continue
            }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if !foundHeader {
                guard cells.map({ $0.lowercased() }) == expected.map({ $0.lowercased() }) else {
                    throw PricingError.invalidDocument
                }
                foundHeader = true
                continue
            }
            if cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { continue }
            guard cells.count == expected.count else { throw PricingError.invalidDocument }
            let key: String
            let price: TokenPrice
            if provider == .codex {
                key = cells[0].components(separatedBy: " (")[0].lowercased()
                let values = try cells.dropFirst().map { try amount($0, claude: false) }
                guard let input = values[0], let output = values[3] else { throw PricingError.invalidDocument }
                var long: TokenPrice.ContextPrice?
                if values[4...].contains(where: { $0 != nil }) {
                    guard let longInput = values[4], let longOutput = values[7] else { throw PricingError.invalidDocument }
                    long = .init(input: longInput, cachedInput: values[5], cacheWrite: values[6], output: longOutput)
                }
                price = TokenPrice(input: input, cachedInput: values[1], cacheWrite: values[2], output: output, longContext: long)
            } else {
                let name = cells[0].components(separatedBy: " (")[0].lowercased()
                guard name.range(of: #"^claude [a-z]+ [0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else {
                    throw PricingError.invalidDocument
                }
                key = name.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: ".", with: "-")
                let values = try cells.dropFirst().map { try amount($0, claude: true) }
                guard let input = values[0], let output = values[4], values.allSatisfy({ $0 != nil }) else {
                    throw PricingError.invalidDocument
                }
                price = TokenPrice(input: input, cachedInput: values[3], cacheWrite: values[1], output: output, cacheWrite1h: values[2])
            }
            guard key.range(of: #"^[a-z0-9][a-z0-9.-]+$"#, options: .regularExpression) != nil,
                  price.isValid, rates[key] == nil else { throw PricingError.invalidDocument }
            rates[key] = price
        }
        guard !rates.isEmpty else { throw PricingError.invalidDocument }
        return rates
    }

    private static func amount(_ cell: String, claude: Bool) throws -> Double? {
        if cell == "-" { return nil }
        let pattern = claude ? #"^\$([0-9]+(?:\.[0-9]+)?) / MTok(?:[0-9]+)?$"# : #"^\$([0-9]+(?:\.[0-9]+)?)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: cell, range: NSRange(cell.startIndex..., in: cell)),
              let range = Range(match.range(at: 1), in: cell), let value = Double(cell[range]),
              value.isFinite, value >= 0, value <= 10_000 else { throw PricingError.invalidDocument }
        return value
    }
}

actor PricingCatalog {
    static let shared = PricingCatalog()
    nonisolated static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/tracken/Pricing", isDirectory: true)
    nonisolated static func source(for provider: AIProvider) -> URL {
        URL(string: provider == .codex ? "https://developers.openai.com/api/docs/pricing.md"
            : "https://platform.claude.com/docs/en/about-claude/pricing")!
    }

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let directory: URL
    private let fetch: Fetch
    private var snapshots: [AIProvider: PricingSnapshot]
    private var errors: [AIProvider: String] = [:]
    private var lastAttempt: [AIProvider: Date] = [:]
    private var refreshing: Set<AIProvider> = []

    init(directory: URL = PricingCatalog.defaultDirectory, fetch: Fetch? = nil) {
        self.directory = directory
        self.fetch = fetch ?? { request in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw PricingError.downloadFailed }
            return (data, response)
        }
        var loaded: [AIProvider: PricingSnapshot] = [:]
        for provider in AIProvider.allCases {
            let url = directory.appendingPathComponent(provider.rawValue + ".json")
            if let data = try? Data(contentsOf: url),
               let snapshot = try? JSONDecoder().decode(PricingSnapshot.self, from: data),
               snapshot.providerID == provider.rawValue, !snapshot.isBundled,
               snapshot.checkedAt.timeIntervalSince1970.isFinite,
               snapshot.checkedAt.timeIntervalSince1970 > 0,
               snapshot.checkedAt <= Date().addingTimeInterval(60),
               !snapshot.rates.isEmpty, snapshot.rates.values.allSatisfy(\.isValid) {
                loaded[provider] = snapshot
            } else {
                loaded[provider] = .bundled(for: provider)
            }
        }
        snapshots = loaded
    }

    func snapshot(for provider: AIProvider) -> PricingSnapshot { snapshots[provider]! }
    func error(for provider: AIProvider) -> String? { errors[provider] }

    @discardableResult
    func refresh(_ provider: AIProvider, force: Bool = false, now: Date = Date()) async -> Bool {
        guard !refreshing.contains(provider) else { return false }
        let previous = snapshots[provider]!
        if !force {
            if let attempted = lastAttempt[provider], now.timeIntervalSince(attempted) < 3_600 { return false }
            if !previous.isBundled && now.timeIntervalSince(previous.checkedAt) < 86_400 { return false }
        }
        refreshing.insert(provider)
        lastAttempt[provider] = now
        defer { refreshing.remove(provider) }
        do {
            let url = Self.source(for: provider)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("text/markdown", forHTTPHeaderField: "Accept")
            request.setValue("tracken/1.0", forHTTPHeaderField: "User-Agent")
            if let etag = previous.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = previous.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
            let (data, response) = try await fetch(request)
            guard response.url?.host == url.host, response.url?.scheme == "https" else { throw PricingError.downloadFailed }
            var next: PricingSnapshot
            if response.statusCode == 304 && !previous.isBundled {
                next = previous
                next.checkedAt = now
            } else {
                guard response.statusCode == 200, data.count <= 2_000_000,
                      let text = String(data: data, encoding: .utf8) else { throw PricingError.downloadFailed }
                let rates = try OfficialPricingParser.parse(text, provider: provider)
                next = PricingSnapshot(providerID: provider.rawValue, checkedAt: now, isBundled: false,
                                       rates: rates, etag: response.value(forHTTPHeaderField: "ETag"),
                                       lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: directory.appendingPathComponent(provider.rawValue + ".json"), options: .atomic)
            snapshots[provider] = next
            errors[provider] = nil
            return next.rates != previous.rates
        } catch {
            errors[provider] = (error as? LocalizedError)?.errorDescription
                ?? "Price update failed. Using the last saved prices."
            return false
        }
    }
}
