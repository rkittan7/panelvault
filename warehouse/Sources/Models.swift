import Foundation

/// One stock event. The warehouse is an append-only log of these; quantities
/// are always derived by replaying the log, never stored as a mutable number.
///
/// This shape is deliberate for the planned company sync: independent devices
/// can each append movements offline, and a backend can merge two logs by id
/// with no conflict resolution beyond de-duplication. A bare "quantity: 37"
/// column cannot merge like that.
struct StockMovement: Identifiable, Codable, Equatable {
  enum Kind: String, Codable {
    /// Goods in — from a scanned delivery note or manual entry.
    case receive
    /// Goods out — consumed by a board build.
    case consume
    /// Manual correction after a physical count. Quantity may be negative.
    case adjust
  }

  let id: UUID
  /// PanelVault catalog component id — the shared key between the two apps.
  let partID: String
  let kind: Kind
  /// Positive for receive/consume; adjust carries a signed delta.
  let quantity: Int
  let date: Date
  /// Delivery note number, board number, or a free note.
  var reference: String
  /// Which device wrote this — merge metadata for the future backend.
  let deviceID: String

  init(partID: String, kind: Kind, quantity: Int, reference: String = "") {
    self.id = UUID()
    self.partID = partID
    self.kind = kind
    self.quantity = quantity
    self.date = Date()
    self.reference = reference
    self.deviceID = StockMovement.currentDeviceID
  }

  /// Effect of this movement on the on-hand count.
  var delta: Int {
    switch kind {
    case .receive: return quantity
    case .consume: return -quantity
    case .adjust: return quantity
    }
  }

  static let currentDeviceID: String = {
    let key = "warehouse.deviceID"
    if let existing = UserDefaults.standard.string(forKey: key) { return existing }
    let fresh = UUID().uuidString
    UserDefaults.standard.set(fresh, forKey: key)
    return fresh
  }()
}

/// Per-part settings the user maintains, separate from the movement log.
struct PartSettings: Codable, Equatable {
  /// Alert when on-hand drops to or below this. Nil means no alert.
  var minimumLevel: Int?
  /// Free text: "Shelf B3", "Drawer 12".
  var location: String

  static let none = PartSettings(minimumLevel: nil, location: "")
}

/// A catalog part joined with its live stock state, ready for display.
struct StockEntry: Identifiable {
  let part: CatalogPart
  let onHand: Int
  let settings: PartSettings
  let lastMovement: Date?

  var id: String { part.id }

  var isLow: Bool {
    guard let minimum = settings.minimumLevel else { return false }
    return onHand <= minimum
  }
}
