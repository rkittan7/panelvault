// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import Foundation
import Combine

/// Owns the movement log and part settings, persists them as JSON files in
/// Application Support, and serves derived stock state to the views.
///
/// Same persistence philosophy as PanelVault after its storage fix: plain
/// files, written atomically off the main thread, no UserDefaults blobs.
@MainActor
final class WarehouseStore: ObservableObject {
  /// Shared instance. PanelVault's catalog shows on-hand stock from
  /// sheets that an @EnvironmentObject does not reliably reach.
  static let shared = WarehouseStore()

  @Published private(set) var movements: [StockMovement] = [] {
    didSet { onHandCache = nil }
  }

  /// Invalidated by the `movements` observer above. See `onHand`.
  private var onHandCache: [String: Int]?
  @Published private(set) var settings: [String: PartSettings] = [:]

  /// Parts the user created because the catalog does not carry them —
  /// special relays, brackets, whatever the workshop actually stocks.
  /// Same shape as catalog parts so the rest of the app cannot tell them apart.
  @Published private(set) var customParts: [CatalogPart] = []
  @Published private(set) var barcodeMappings: [BarcodeMapping] = []
  @Published private(set) var account: WarehouseCloudAccount?
  @Published private(set) var syncPhase: WarehouseSyncPhase = .signedOut

  private let queue = DispatchQueue(label: "warehouse.persistence", qos: .utility)
  private let cloud = WarehouseCloudClient()
  private var syncMetadata = WarehouseSyncMetadata()

  init() {
    account = WarehouseAccountKeychain.load()
    load()
    syncPhase = account == nil ? .signedOut : .idle
    if account != nil { triggerSync() }
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
    if let onHandCache { return onHandCache }
    let counts = movements.reduce(into: [String: Int]()) { counts, movement in
      counts[movement.partID, default: 0] += movement.delta
    }
    onHandCache = counts
    return counts
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

  var pendingMovementCount: Int {
    movements.lazy.filter { !self.syncMetadata.syncedMovementIDs.contains($0.id) }.count
  }

  func barcodeMapping(for rawCode: String) -> BarcodeMapping? {
    let code = WarehouseStore.normalizedBarcode(rawCode)
    return barcodeMappings.first { $0.code == code }
  }

  // MARK: - Mutations

  func append(_ movement: StockMovement) {
    movements.append(movement)
    persistMovements()
    triggerSync()
  }

  func append(_ batch: [StockMovement]) {
    guard !batch.isEmpty else { return }
    movements.append(contentsOf: batch)
    persistMovements()
    triggerSync()
  }

  func updateSettings(for partID: String, _ update: PartSettings) {
    if update == .none {
      settings.removeValue(forKey: partID)
    } else {
      settings[partID] = update
    }
    persistSettings()
  }

  func upsertBarcodeMapping(
    code rawCode: String,
    symbology: String,
    partID: String,
    packageQuantity: Int,
    boxLabel: String
  ) {
    let code = WarehouseStore.normalizedBarcode(rawCode)
    guard !code.isEmpty, part(for: partID) != nil else { return }
    let mapping = BarcodeMapping(
      code: code,
      symbology: symbology,
      partID: partID,
      packageQuantity: max(1, packageQuantity),
      boxLabel: boxLabel.trimmingCharacters(in: .whitespacesAndNewlines),
      updatedAt: ISO8601DateFormatter.warehouse.string(from: Date()),
      updatedByDeviceID: StockMovement.currentDeviceID
    )
    if let index = barcodeMappings.firstIndex(where: { $0.code == code }) {
      barcodeMappings[index] = mapping
    } else {
      barcodeMappings.append(mapping)
    }
    persistBarcodeMappings()
    triggerSync()
  }

  // MARK: - PanelVault Cloud

  func signIn(baseURL: String, companyCode: String, name: String, password: String) async throws {
    let signedIn = try await cloud.login(
      baseURL: baseURL,
      companyCode: companyCode,
      name: name,
      password: password
    )
    if !syncMetadata.companyCode.isEmpty,
       syncMetadata.companyCode != signedIn.companyCode,
       !movements.isEmpty {
      throw WarehouseCloudError.companyConflict(syncMetadata.companyCode)
    }
    if syncMetadata.companyCode != signedIn.companyCode {
      syncMetadata = WarehouseSyncMetadata(companyCode: signedIn.companyCode)
      persistSyncMetadata()
    }
    account = signedIn
    WarehouseAccountKeychain.save(signedIn)
    syncPhase = .idle
    await sync()
  }

  func signOut() {
    account = nil
    WarehouseAccountKeychain.save(nil)
    syncPhase = .signedOut
  }

  func sync() async {
    guard let account else {
      syncPhase = .signedOut
      return
    }
    guard syncPhase != .syncing else { return }
    syncPhase = .syncing

    do {
      if !customParts.isEmpty {
        let response = try await cloud.uploadCustomParts(customParts, account: account)
        mergeCustomParts(response.customParts)
      }
      if !barcodeMappings.isEmpty {
        let response = try await cloud.uploadBarcodeMappings(barcodeMappings, account: account)
        mergeBarcodeMappings(response.barcodeMappings)
      }

      while true {
        let pending = movements
          .filter { !syncMetadata.syncedMovementIDs.contains($0.id) }
          .prefix(500)
        guard !pending.isEmpty else { break }
        let response = try await cloud.upload(Array(pending), account: account)
        syncMetadata.syncedMovementIDs.formUnion(response.acceptedIDs)
        syncMetadata.syncedMovementIDs.formUnion(response.duplicateIDs)
        persistSyncMetadata()
      }

      var shouldContinue = true
      while shouldContinue {
        let response = try await cloud.download(after: syncMetadata.lastSequence, account: account)
        mergeCustomParts(response.customParts)
        mergeBarcodeMappings(response.barcodeMappings)
        mergeRemoteMovements(response.movements)
        if response.hasMore {
          syncMetadata.lastSequence = response.movements.compactMap(\.sequence).max()
            ?? syncMetadata.lastSequence
        } else {
          syncMetadata.lastSequence = response.latestSequence
          shouldContinue = false
        }
        persistSyncMetadata()
      }
      syncPhase = .idle
    } catch {
      syncPhase = .failed(error.localizedDescription)
    }
  }

  private func triggerSync() {
    guard account != nil else { return }
    Task { [weak self] in
      await self?.sync()
    }
  }

  private func mergeRemoteMovements(_ remote: [CloudMovement]) {
    let existing = Set(movements.map(\.id))
    let additions = remote.compactMap { item -> StockMovement? in
      syncMetadata.syncedMovementIDs.insert(item.id)
      guard !existing.contains(item.id) else { return nil }
      return item.localMovement
    }
    if !additions.isEmpty {
      movements.append(contentsOf: additions)
      persistMovements()
    }
  }

  private func mergeCustomParts(_ remote: [CatalogPart]) {
    let existing = Set(customParts.map(\.id))
    let additions = remote.filter { !existing.contains($0.id) }
    guard !additions.isEmpty else { return }
    customParts.append(contentsOf: additions)
    persist(customParts, to: WarehouseStore.customPartsURL)
  }

  private func mergeBarcodeMappings(_ remote: [BarcodeMapping]) {
    var changed = false
    for incoming in remote {
      if let index = barcodeMappings.firstIndex(where: { $0.code == incoming.code }) {
        guard barcodeMappings[index].updatedAt < incoming.updatedAt else { continue }
        barcodeMappings[index] = incoming
      } else {
        barcodeMappings.append(incoming)
      }
      changed = true
    }
    if changed { persistBarcodeMappings() }
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
  private static var syncMetadataURL: URL { directory.appendingPathComponent("cloudSync.json") }
  private static var barcodeMappingsURL: URL { directory.appendingPathComponent("barcodeMappings.json") }

  private static func normalizedBarcode(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
  }

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
    if let data = try? Data(contentsOf: WarehouseStore.syncMetadataURL),
       let decoded = try? JSONDecoder.warehouse.decode(WarehouseSyncMetadata.self, from: data) {
      syncMetadata = decoded
    }
    if let data = try? Data(contentsOf: WarehouseStore.barcodeMappingsURL),
       let decoded = try? JSONDecoder.warehouse.decode([BarcodeMapping].self, from: data) {
      barcodeMappings = decoded
    }
  }

  private func persistMovements() {
    persist(movements, to: WarehouseStore.movementsURL)
  }

  private func persistSettings() {
    persist(settings, to: WarehouseStore.settingsURL)
  }

  private func persistSyncMetadata() {
    persist(syncMetadata, to: WarehouseStore.syncMetadataURL)
  }

  private func persistBarcodeMappings() {
    persist(barcodeMappings, to: WarehouseStore.barcodeMappingsURL)
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
