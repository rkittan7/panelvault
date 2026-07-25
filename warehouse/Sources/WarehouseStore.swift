import Foundation
import Combine

/// Owns the movement log and part settings, persists them as JSON files in
/// Application Support, and serves derived stock state to the views.
///
/// Same persistence philosophy as PanelVault after its storage fix: plain
/// files, written atomically off the main thread, no UserDefaults blobs.
final class WarehouseStore: ObservableObject {
  @Published private(set) var movements: [StockMovement] = []
  @Published private(set) var settings: [String: PartSettings] = [:]

  /// Parts the user created because the catalog does not carry them —
  /// special relays, brackets, whatever the workshop actually stocks.
  /// Same shape as catalog parts so the rest of the app cannot tell them apart.
  @Published private(set) var customParts: [CatalogPart] = []

  private let queue = DispatchQueue(label: "warehouse.persistence", qos: .utility)

  init() {
    load()
  }

  // MARK: - Part lookup (catalog + custom)

  /// Single lookup the whole app uses, so custom parts appear everywhere the
  /// catalog ones do.
  func part(for id: String) -> CatalogPart? {
    Catalog.part(for: id) ?? customParts.first { $0.id == id }
  }

  var allParts: [CatalogPart] {
    Catalog.allParts + customParts
  }

  /// Every distinct part type, for suggestions when creating a custom part.
  var knownTypes: [String] {
    Array(Set(allParts.map(\.type))).sorted()
  }

  /// Creates and persists a custom part, returning it ready to use.
  @discardableResult
  func addCustomPart(
    manufacturer: String,
    type: String,
    model: String,
    rating: String,
    poles: String,
    notes: String
  ) -> CatalogPart {
    let part = CatalogPart(
      id: "custom-\(UUID().uuidString)",
      manufacturer: manufacturer.isEmpty ? "Generic" : manufacturer,
      type: type,
      model: model,
      rating: rating,
      poles: poles,
      curve: "",
      about: notes
    )
    customParts.append(part)
    persist(customParts, to: WarehouseStore.customPartsURL)
    return part
  }

  // MARK: - Derived state

  /// On-hand quantity per part id, replayed from the log.
  var onHand: [String: Int] {
    movements.reduce(into: [:]) { counts, movement in
      counts[movement.partID, default: 0] += movement.delta
    }
  }

  /// Every part that has stock, settings or history — the "active" warehouse.
  var entries: [StockEntry] {
    let counts = onHand
    let lastDates = movements.reduce(into: [String: Date]()) { dates, m in
      if dates[m.partID].map({ $0 < m.date }) ?? true { dates[m.partID] = m.date }
    }
    let activeIDs = Set(counts.keys).union(settings.keys)

    return activeIDs
      .compactMap { id -> StockEntry? in
        guard let part = part(for: id) else { return nil }
        return StockEntry(
          part: part,
          onHand: counts[id] ?? 0,
          settings: settings[id] ?? .none,
          lastMovement: lastDates[id]
        )
      }
      .sorted { $0.part.model.localizedCaseInsensitiveCompare($1.part.model) == .orderedAscending }
  }

  var lowStock: [StockEntry] {
    entries.filter(\.isLow)
  }

  var totalUnits: Int {
    onHand.values.reduce(0, +)
  }

  func entry(for partID: String) -> StockEntry? {
    entries.first { $0.id == partID }
  }

  func movements(for partID: String) -> [StockMovement] {
    movements.filter { $0.partID == partID }.sorted { $0.date > $1.date }
  }

  var recentMovements: [StockMovement] {
    movements.sorted { $0.date > $1.date }
  }

  // MARK: - Mutations

  func append(_ movement: StockMovement) {
    movements.append(movement)
    persistMovements()
  }

  func append(_ batch: [StockMovement]) {
    guard !batch.isEmpty else { return }
    movements.append(contentsOf: batch)
    persistMovements()
  }

  func updateSettings(for partID: String, _ update: PartSettings) {
    if update == .none {
      settings.removeValue(forKey: partID)
    } else {
      settings[partID] = update
    }
    persistSettings()
  }

  // MARK: - Persistence

  private static var directory: URL {
    let manager = FileManager.default
    let base = manager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.temporaryDirectory
    let folder = base.appendingPathComponent("PanelVaultWarehouse", isDirectory: true)
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private static var movementsURL: URL { directory.appendingPathComponent("movements.json") }
  private static var settingsURL: URL { directory.appendingPathComponent("partSettings.json") }
  private static var customPartsURL: URL { directory.appendingPathComponent("customParts.json") }

  private func load() {
    if let data = try? Data(contentsOf: WarehouseStore.movementsURL),
       let decoded = try? JSONDecoder.warehouse.decode([StockMovement].self, from: data) {
      movements = decoded
    }
    if let data = try? Data(contentsOf: WarehouseStore.settingsURL),
       let decoded = try? JSONDecoder.warehouse.decode([String: PartSettings].self, from: data) {
      settings = decoded
    }
    if let data = try? Data(contentsOf: WarehouseStore.customPartsURL),
       let decoded = try? JSONDecoder.warehouse.decode([CatalogPart].self, from: data) {
      customParts = decoded
    }
  }

  private func persistMovements() {
    persist(movements, to: WarehouseStore.movementsURL)
  }

  private func persistSettings() {
    persist(settings, to: WarehouseStore.settingsURL)
  }

  private func persist<T: Encodable>(_ value: T, to url: URL) {
    guard let data = try? JSONEncoder.warehouse.encode(value) else { return }
    queue.async {
      try? data.write(to: url, options: .atomic)
    }
  }
}

extension JSONEncoder {
  static var warehouse: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

extension JSONDecoder {
  static var warehouse: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
