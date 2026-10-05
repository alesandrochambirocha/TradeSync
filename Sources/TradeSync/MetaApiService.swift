import Foundation

// MARK: - MetaApi cloud REST client (MetaTrader 5 / 4 bridge)
//
// Users create a free account at https://app.metaapi.cloud, connect their MT5
// account (broker login + investor password), and paste their API token +
// account ID into TradeSync's settings. We then pull the account's history
// deals over REST and reconstruct closed trades by position id.

enum MetaApiError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your MetaApi token and account ID in Settings first."
        case .badURL: return "Could not build the MetaApi request URL."
        case .http(let code, let body):
            switch code {
            case 401: return "MetaApi rejected the token (401). Double-check the API token."
            case 403: return "Access denied (403). The token may lack access to this account."
            case 404: return "Account not found (404). Double-check the account ID and region."
            default: return "MetaApi returned HTTP \(code). \(body.prefix(200))"
            }
        case .decoding(let msg): return "Could not parse the MetaApi response: \(msg)"
        case .network(let msg): return "Network error: \(msg)"
        }
    }
}

// MetaApi deal payload (subset of fields we need)
struct MetaApiDeal: Codable {
    let id: String
    let type: String              // DEAL_TYPE_BUY / DEAL_TYPE_SELL / DEAL_TYPE_BALANCE / ...
    let entryType: String?        // DEAL_ENTRY_IN / DEAL_ENTRY_OUT / DEAL_ENTRY_INOUT / DEAL_ENTRY_OUT_BY
    let symbol: String?
    let volume: Double?
    let price: Double?
    let profit: Double?
    let commission: Double?
    let swap: Double?
    let time: String              // ISO 8601
    let positionId: String?
    let orderId: String?
    let stopLoss: Double?
    let takeProfit: Double?
    let reason: String?           // DEAL_REASON_SL / DEAL_REASON_TP / DEAL_REASON_CLIENT / ...
}

// MetaApi history order payload (subset) — used to recover SL/TP set on the position.
struct MetaApiOrder: Codable {
    let id: String
    let type: String?
    let state: String?
    let positionId: String?
    let stopLoss: Double?
    let takeProfit: Double?
    let time: String?
}

struct MetaApiAccountInfo: Codable {
    let name: String?
    let login: String?
    let server: String?
    let state: String?
    let connectionStatus: String?
}

struct MetaApiService {
    let settings: MetaApiSettings

    static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        isoParser.date(from: s) ?? isoParserNoFraction.date(from: s)
    }

    private var clientHost: String {
        "https://mt-client-api-v1.\(settings.region).agiliumtrade.ai"
    }
    private var provisioningHost: String {
        "https://mt-provisioning-api-v1.agiliumtrade.agiliumtrade.ai"
    }

    private func request(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(settings.token, forHTTPHeaderField: "auth-token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 30
        return req
    }

    private func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request(url: url))
            guard let http = response as? HTTPURLResponse else {
                throw MetaApiError.network("No HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw MetaApiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let e as MetaApiError {
            throw e
        } catch {
            throw MetaApiError.network(error.localizedDescription)
        }
    }

    // MARK: API calls

    /// Verify the token/account pair by fetching account metadata.
    func testConnection() async throws -> MetaApiAccountInfo {
        guard settings.isConfigured else { throw MetaApiError.notConfigured }
        guard let url = URL(string: "\(provisioningHost)/users/current/accounts/\(settings.accountId)") else {
            throw MetaApiError.badURL
        }
        let data = try await get(url)
        do {
            return try JSONDecoder().decode(MetaApiAccountInfo.self, from: data)
        } catch {
            throw MetaApiError.decoding(error.localizedDescription)
        }
    }

    /// Fetch history deals in [start, end].
    func fetchDeals(from start: Date, to end: Date) async throws -> [MetaApiDeal] {
        guard settings.isConfigured else { throw MetaApiError.notConfigured }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startStr = iso.string(from: start)
        let endStr = iso.string(from: end)
        guard let url = URL(string:
            "\(clientHost)/users/current/accounts/\(settings.accountId)/history-deals/time/\(startStr)/\(endStr)")
        else { throw MetaApiError.badURL }
        let data = try await get(url)
        do {
            return try JSONDecoder().decode([MetaApiDeal].self, from: data)
        } catch {
            throw MetaApiError.decoding(error.localizedDescription)
        }
    }

    /// Fetch history orders in [start, end].
    func fetchOrders(from start: Date, to end: Date) async throws -> [MetaApiOrder] {
        guard settings.isConfigured else { throw MetaApiError.notConfigured }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let url = URL(string:
            "\(clientHost)/users/current/accounts/\(settings.accountId)/history-orders/time/\(iso.string(from: start))/\(iso.string(from: end))")
        else { throw MetaApiError.badURL }
        let data = try await get(url)
        do {
            return try JSONDecoder().decode([MetaApiOrder].self, from: data)
        } catch {
            throw MetaApiError.decoding(error.localizedDescription)
        }
    }

    /// Full sync: pull deals (plus orders for SL/TP) and reconstruct closed trades.
    func fetchTrades(from start: Date, to end: Date, accountLabel: String) async throws -> [Trade] {
        let deals = try await fetchDeals(from: start, to: end)
        // Orders are only a fallback source for SL/TP; a failure there shouldn't block the sync.
        let orders = (try? await fetchOrders(from: start, to: end)) ?? []
        return Self.buildTrades(from: deals, orders: orders, accountLabel: accountLabel)
    }

    // MARK: Deal -> Trade reconstruction

    /// Groups MT5 deals by position id. Entry deals (DEAL_ENTRY_IN) open the
    /// position; OUT / INOUT / OUT_BY deals close it. Prices are volume-weighted.
    static func buildTrades(from deals: [MetaApiDeal], orders: [MetaApiOrder] = [], accountLabel: String) -> [Trade] {
        let ordersByPosition = Dictionary(grouping: orders.filter { $0.positionId != nil }, by: { $0.positionId! })
        let tradeDeals = deals.filter {
            ($0.type == "DEAL_TYPE_BUY" || $0.type == "DEAL_TYPE_SELL")
            && $0.symbol != nil && $0.positionId != nil
        }
        let grouped = Dictionary(grouping: tradeDeals, by: { $0.positionId! })
        var trades: [Trade] = []

        for (positionId, group) in grouped {
            let sorted = group.sorted {
                (parseDate($0.time) ?? .distantPast) < (parseDate($1.time) ?? .distantPast)
            }
            let entries = sorted.filter { $0.entryType == "DEAL_ENTRY_IN" }
            let exits = sorted.filter {
                ["DEAL_ENTRY_OUT", "DEAL_ENTRY_INOUT", "DEAL_ENTRY_OUT_BY"].contains($0.entryType ?? "")
            }
            // Only import closed positions
            guard let firstEntry = entries.first, let lastExit = exits.last else { continue }
            guard let entryTime = parseDate(firstEntry.time),
                  let exitTime = parseDate(lastExit.time) else { continue }

            func weightedPrice(_ ds: [MetaApiDeal]) -> Double {
                let totalVol = ds.reduce(0.0) { $0 + ($1.volume ?? 0) }
                guard totalVol > 0 else { return ds.first?.price ?? 0 }
                return ds.reduce(0.0) { $0 + ($1.price ?? 0) * ($1.volume ?? 0) } / totalVol
            }

            let direction: TradeDirection = firstEntry.type == "DEAL_TYPE_BUY" ? .long : .short
            let volume = entries.reduce(0.0) { $0 + ($1.volume ?? 0) }
            let profit = sorted.reduce(0.0) { $0 + ($1.profit ?? 0) }
            let commission = sorted.reduce(0.0) { $0 + ($1.commission ?? 0) }
            let swap = sorted.reduce(0.0) { $0 + ($1.swap ?? 0) }
            let symbol = firstEntry.symbol ?? "?"

            trades.append(Trade(
                symbol: symbol,
                assetClass: classify(symbol: symbol),
                direction: direction,
                entryTime: entryTime,
                exitTime: exitTime,
                entryPrice: weightedPrice(entries),
                exitPrice: weightedPrice(exits),
                volume: volume,
                grossPnL: profit,
                commission: commission,
                swap: swap,
                stopLoss: resolveLevel(entries: entries, exits: exits, orders: ordersByPosition[positionId] ?? [],
                                       field: \.stopLoss, orderField: \.stopLoss, reason: "DEAL_REASON_SL"),
                takeProfit: resolveLevel(entries: entries, exits: exits, orders: ordersByPosition[positionId] ?? [],
                                         field: \.takeProfit, orderField: \.takeProfit, reason: "DEAL_REASON_TP"),
                source: .metatrader,
                accountLabel: accountLabel,
                externalId: "mt5-\(positionId)"
            ))
        }
        return trades.sorted { $0.exitTime < $1.exitTime }
    }

    /// SL/TP for a position: explicit value on the deals, else on the position's
    /// orders, else — if the position was closed by that level — the exit price.
    private static func resolveLevel(entries: [MetaApiDeal], exits: [MetaApiDeal], orders: [MetaApiOrder],
                                     field: KeyPath<MetaApiDeal, Double?>, orderField: KeyPath<MetaApiOrder, Double?>,
                                     reason: String) -> Double? {
        func positive(_ v: Double?) -> Double? { v.flatMap { $0 > 0 ? $0 : nil } }
        if let v = entries.compactMap({ positive($0[keyPath: field]) }).first { return v }
        if let v = exits.compactMap({ positive($0[keyPath: field]) }).first { return v }
        if let v = orders.compactMap({ positive($0[keyPath: orderField]) }).first { return v }
        if let hit = exits.last(where: { $0.reason == reason }) { return positive(hit.price) }
        return nil
    }

    static func classify(symbol: String) -> AssetClass {
        let s = symbol.uppercased()
        let forexPairs = ["EUR", "GBP", "USD", "JPY", "AUD", "NZD", "CAD", "CHF"]
        if s.count == 6, forexPairs.contains(String(s.prefix(3))) { return .forex }
        if s.hasPrefix("XAU") || s.hasPrefix("XAG") { return .forex }
        if s.contains("BTC") || s.contains("ETH") { return .crypto }
        if Contracts.pointValue(for: s) != nil { return .futures }
        return .other
    }
}
