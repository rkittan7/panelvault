// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

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

  let id: String
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
    self.id = UUID().uuidString
    self.partID = partID
    self.kind = kind
    self.quantity = quantity
    self.date = Date()
    self.reference = reference
    self.deviceID = StockMovement.currentDeviceID
  }

  init(
    id: String,
    partID: String,
    kind: Kind,
    quantity: Int,
    date: Date,
    reference: String,
    deviceID: String
  ) {
    self.id = id
    self.partID = partID
    self.kind = kind
    self.quantity = quantity
    self.date = date
    self.reference = reference
    self.deviceID = deviceID
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

/// One confirmed delivery note: the paperwork a batch of receipts came from.
///
/// The movements are still the stock — this is the evidence behind them. It
/// records what the camera actually read, including the lines the worker chose
/// not to receive, so the boss can later answer "why is there stock for this?"
/// with the original document rather than a number.
///
/// Immutable once confirmed, for the same reason movements are: a mistake is
/// corrected by a new adjustment, never by rewriting what was signed off.
struct DeliveryBatch: Identifiable, Codable, Equatable {
  enum Source: String, Codable {
    /// Read from a photographed delivery note.
    case scan
    /// Typed in by hand.
    case manual
    /// Produced by an opening stocktake rather than a delivery.
    case stocktake
  }

  /// One line as it was read and as the worker left it on the review screen.
  struct Line: Identifiable, Codable, Equatable {
    var id: String
    /// Exactly what OCR produced — never cleaned up.
    var rawText: String
    var quantity: Int
    /// Nil when nothing in the catalog matched; kept anyway as evidence.
    var partID: String?
    var included: Bool
    /// The movement this line created, when it was included.
    var movementID: String?
  }

  let id: String
  var noteNumber: String
  var supplier: String
  var source: Source
  var scannedAt: Date
  var confirmedAt: Date
  var pageCount: Int
  var lines: [Line]
  var movementIDs: [String]
  let deviceID: String

  init(
    id: String = UUID().uuidString,
    noteNumber: String,
    supplier: String,
    source: Source,
    scannedAt: Date,
    confirmedAt: Date = Date(),
    pageCount: Int,
    lines: [Line],
    movementIDs: [String],
    deviceID: String = StockMovement.currentDeviceID
  ) {
    self.id = id
    self.noteNumber = noteNumber
    self.supplier = supplier
    self.source = source
    self.scannedAt = scannedAt
    self.confirmedAt = confirmedAt
    self.pageCount = pageCount
    self.lines = lines
    self.movementIDs = movementIDs
    self.deviceID = deviceID
  }

  var receivedUnits: Int {
    lines.filter(\.included).reduce(0) { $0 + $1.quantity }
  }

  var title: String {
    let parts = [noteNumber.isEmpty ? "" : "Note \(noteNumber)", supplier].filter { !$0.isEmpty }
    return parts.isEmpty ? "Delivery" : parts.joined(separator: " · ")
  }
}

/// A manufacturer barcode taught once and reused by every future stocktake.
/// The code identifies the box SKU; packageQuantity says how many physical
/// units one scan contributes to the count.
struct BarcodeMapping: Identifiable, Codable, Equatable {
  var id: String { code }
  let code: String
  let symbology: String
  let partID: String
  let packageQuantity: Int
  let boxLabel: String
  let updatedAt: String
  let updatedByDeviceID: String
}
