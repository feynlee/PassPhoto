import Foundation
import Observation
import StoreKit
import os

/// Tip jar (adapted from BillSplit), backed by StoreKit 2 consumables at $0.99, $1.99 and $2.99. Tips must be in-app purchases,
/// which have fixed prices, so a custom amount is the $0.99 tip bought several times over (StoreKit
/// allows a quantity of 1...10). When the products can't be loaded the tip UI stays hidden.
@Observable
final class TipStore {
    static let productIDs = [
        "liziyue.PassPhoto.tip.small",
        "liziyue.PassPhoto.tip.medium",
        "liziyue.PassPhoto.tip.large",
    ]
    /// StoreKit's limit on a consumable's purchase quantity.
    static let quantityRange = 1...10

    /// A tip that can be bought: a product and how many of it.
    struct Option: Identifiable, Equatable {
        let id: String
        let price: Decimal
        let priceFormat: Decimal.FormatStyle.Currency
        fileprivate let product: Product?

        func displayPrice(quantity: Int = 1) -> String {
            (price * Decimal(quantity)).formatted(priceFormat)
        }

        static func == (lhs: Option, rhs: Option) -> Bool { lhs.id == rhs.id && lhs.price == rhs.price }
    }

    private(set) var options: [Option] = []
    private(set) var totalTipped: Decimal
    /// Increases after each successful tip, to trigger the thank-you.
    private(set) var tipCount = 0
    /// The option being bought right now, and its quantity.
    private(set) var purchasing: (id: String, quantity: Int)?

    @ObservationIgnored private let defaults: UserDefaults
    /// Finds a tip's price when the options haven't loaded yet; nil when the App Store can't be reached.
    @ObservationIgnored private let priceLookup: (String) async -> Decimal?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "liziyue.PassPhoto", category: "TipStore")
    private static let totalKey = "tips.total"
    private static let styleKey = "tips.celebrationStyle"

    /// The celebration tippers see when they save a photo; `.off` turns it off. Balloons unless they pick
    /// another.
    var celebrationStyle: CelebrationStyle {
        didSet { defaults.set(celebrationStyle.rawValue, forKey: Self.styleKey) }
    }

    init(defaults: UserDefaults = .standard, priceLookup: @escaping (String) async -> Decimal? = TipStore.storePrice) {
        self.defaults = defaults
        self.priceLookup = priceLookup
        totalTipped = Decimal(string: defaults.string(forKey: Self.totalKey) ?? "") ?? 0
        celebrationStyle = defaults.string(forKey: Self.styleKey).flatMap(CelebrationStyle.init(rawValue:)) ?? .balloons
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var hasTipped: Bool { totalTipped > 0 }
    var isPurchasing: Bool { purchasing != nil }

    /// The smallest tip; custom amounts are multiples of it.
    var smallest: Option? { options.first }

    var formattedTotal: String {
        guard let format = options.first?.priceFormat else { return totalTipped.formatted() }
        return totalTipped.formatted(format)
    }

    func loadProducts() async {
        guard options.isEmpty else { return }
        #if DEBUG
        // `-demoTips` shows the tip jar with sample prices when StoreKit isn't configured (e.g. a
        // simulator build installed outside Xcode). Purchases are simulated.
        if UserDefaults.standard.bool(forKey: "demoTips") {
            let format = Decimal.FormatStyle.Currency(code: "USD")
            options = ["0.99", "1.99", "2.99"].enumerated().map { index, price in
                Option(id: Self.productIDs[index], price: Decimal(string: price)!, priceFormat: format, product: nil)
            }
            return
        }
        #endif
        do {
            options = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
                .map { Option(id: $0.id, price: $0.price, priceFormat: $0.priceFormatStyle, product: $0) }
        } catch {
            logger.error("Could not load tip products: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase(_ option: Option, quantity: Int = 1) async {
        guard !isPurchasing else { return }
        let quantity = min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
        purchasing = (option.id, quantity)
        defer { purchasing = nil }

        guard let product = option.product else {
            #if DEBUG
            try? await Task.sleep(for: .seconds(1))
            record(option.price, quantity: quantity)
            #endif
            return
        }
        do {
            if case .success(let verification) = try await product.purchase(options: [.quantity(quantity)]) {
                await handle(verification)
            }
        } catch {
            logger.error("Tip purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        if transaction.revocationDate == nil {
            // A tip can arrive before the prices have loaded, e.g. an interrupted purchase delivered at
            // launch. If its price can't be found, leave the transaction unfinished: StoreKit delivers
            // it again on the next launch, so the tip still counts.
            guard await recordTip(productID: transaction.productID, quantity: transaction.purchasedQuantity) else {
                logger.error("Tip price unavailable; will retry \(transaction.productID, privacy: .public) later")
                return
            }
        }
        await transaction.finish()
    }

    /// Adds a completed tip to the total. Returns false when its price can't be determined.
    func recordTip(productID: String, quantity: Int) async -> Bool {
        let price: Decimal? = if let option = options.first(where: { $0.id == productID }) {
            option.price
        } else {
            await priceLookup(productID)
        }
        guard let price else { return false }
        record(price, quantity: quantity)
        return true
    }

    private static func storePrice(for productID: String) async -> Decimal? {
        try? await Product.products(for: [productID]).first?.price
    }

    private func record(_ price: Decimal, quantity: Int) {
        totalTipped += price * Decimal(quantity)
        tipCount += 1
        defaults.set("\(totalTipped)", forKey: Self.totalKey)
    }
}
