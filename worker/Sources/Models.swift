// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import UIKit

struct ContractorCompany: Identifiable, Equatable {
  let id: String
  let name: String
  let role: String
  let projectCount: String
  let color: Color

  var persistenceSignature: String {
    "\(id)|\(name)|\(role)|\(projectCount)|\(color.archiveHex)"
  }

  static let samples: [ContractorCompany] = []
}

struct CustomerContact: Identifiable, Equatable {
  let id: String
  var name: String
  var role: String
  var phone: String

  init(id: String = "customer-contact-\(UUID().uuidString)", name: String = "", role: String = "", phone: String = "") {
    self.id = id
    self.name = name
    self.role = role
    self.phone = phone
  }

  var persistenceSignature: String {
    "\(id)|\(name)|\(role)|\(phone)"
  }
}

struct CustomerItem: Identifiable, Equatable {
  let id: String
  var name: String
  var kind: String
  var contactName: String
  var phone: String
  var note: String
  var contacts: [CustomerContact]
  var colorHex: UInt32

  init(id: String = "customer-\(UUID().uuidString)", name: String, kind: String = "Company", contactName: String = "", phone: String = "", note: String = "", contacts: [CustomerContact] = [], colorHex: UInt32 = 0x5E78FF) {
    self.id = id
    self.name = name
    self.kind = kind
    self.contactName = contactName
    self.phone = phone
    self.note = note
    self.contacts = contacts
    self.colorHex = colorHex
  }

  var color: Color { Color(hex: colorHex) }

  var profileSummary: String {
    let contactsSummary = contacts.isEmpty ? nil : "\(contacts.count) contact\(contacts.count == 1 ? "" : "s")"
    return [kind, contactName.isEmpty ? nil : contactName, phone.isEmpty ? nil : phone, contactsSummary, note.isEmpty ? nil : note]
      .compactMap { $0 }
      .joined(separator: " • ")
  }

  var persistenceSignature: String {
    "\(id)|\(name)|\(kind)|\(contactName)|\(phone)|\(note)|\(contacts.map(\.persistenceSignature).joined(separator: ";"))|\(colorHex)"
  }
}

struct RecentVisit: Identifiable, Equatable {
  enum Kind: String {
    case project
    case board
  }

  let kind: Kind
  let itemID: String

  init(kind: Kind, id: String) {
    self.kind = kind
    self.itemID = id
  }

  var identifier: String {
    "\(kind.rawValue)-\(itemID)"
  }
}

extension RecentVisit {
  var id: String { identifier }
}

struct RecentBoardSelection: Identifiable {
  let id: String
}

struct SchemeAttachment: Identifiable, Equatable {
  enum Kind: Equatable {
    case pdf
    case photo
  }

  let id: String
  let kind: Kind
  var name: String
  var url: URL?

  /// Filename in the image store rather than the image itself, so a scheme can
  /// be listed without decoding its drawing.
  var imageToken: String?

  var image: UIImage? {
    get { ImageStore.shared.image(for: imageToken) }
    set { imageToken = ImageStore.shared.store(newValue) }
  }

  var thumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: imageToken)
  }

  static func == (lhs: SchemeAttachment, rhs: SchemeAttachment) -> Bool {
    lhs.id == rhs.id &&
      lhs.kind == rhs.kind &&
      lhs.name == rhs.name &&
      lhs.url == rhs.url &&
      lhs.imageToken == rhs.imageToken
  }

  init(id: String = "scheme-\(UUID().uuidString)", kind: Kind, name: String, image: UIImage?, url: URL? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.url = url
    self.imageToken = ImageStore.shared.store(image)
  }

  init(id: String = "scheme-\(UUID().uuidString)", kind: Kind, name: String, imageToken: String?, url: URL? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.url = url
    self.imageToken = imageToken
  }

  var persistenceSignature: String {
    [
      id,
      kind == .pdf ? "pdf" : "photo",
      name,
      url?.absoluteString ?? "",
      ImageStore.shared.signature(for: imageToken)
    ].joined(separator: "|")
  }
}

struct ManufacturerItem: Identifiable {
  let id: String
  var name: String
  var colorHex: UInt32

  /// Brand logo, stored on disk like every other image in the archive.
  var imageToken: String? = nil

  var image: UIImage? {
    get { ImageStore.shared.image(for: imageToken) }
    set { imageToken = ImageStore.shared.store(newValue) }
  }

  var thumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: imageToken)
  }

  init(id: String = "manufacturer-\(UUID().uuidString)", name: String, colorHex: UInt32 = 0x5E78FF, image: UIImage? = nil) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.imageToken = ImageStore.shared.store(image)
  }

  init(id: String = "manufacturer-\(UUID().uuidString)", name: String, colorHex: UInt32 = 0x5E78FF, imageToken: String?) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.imageToken = imageToken
  }

  var color: Color {
    Color(hex: colorHex)
  }

  var initials: String {
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap(\.first)
    return letters.isEmpty ? String(name.prefix(2)).uppercased() : String(letters).uppercased()
  }

  var persistenceSignature: String {
    let imageSignature = ImageStore.shared.signature(for: imageToken)
    return "\(id)|\(name)|\(colorHex)|\(imageSignature)"
  }

  static let defaults = [
    ManufacturerItem(id: "rittal", name: "Rittal", colorHex: 0x5E78FF),
    ManufacturerItem(id: "abb", name: "ABB", colorHex: 0xFF3B30),
    ManufacturerItem(id: "yakir", name: "Yakir", colorHex: 0x35E177),
    ManufacturerItem(id: "tamhash", name: "Tamhash", colorHex: 0xFF9F0A),
    ManufacturerItem(id: "hager", name: "HAGER", colorHex: 0x64D2FF),
    ManufacturerItem(id: "delta", name: "Delta", colorHex: 0x0A84FF),
    ManufacturerItem(id: "schneider", name: "Schneider", colorHex: 0x35E177),
    ManufacturerItem(id: "siemens", name: "Siemens", colorHex: 0x18D4E8),
    ManufacturerItem(id: "eaton", name: "Eaton", colorHex: 0x5E78FF),
    ManufacturerItem(id: "legrand", name: "Legrand", colorHex: 0xD85CFF),
    ManufacturerItem(id: "mean-well", name: "Mean Well", colorHex: 0xFFD60A),
    ManufacturerItem(id: "phoenix", name: "Phoenix", colorHex: 0xFF9F0A),
    ManufacturerItem(id: "danfoss", name: "Danfoss", colorHex: 0xE2231A),
    ManufacturerItem(id: "socomec", name: "Socomec", colorHex: 0x00A0DF),
    ManufacturerItem(id: "generic", name: "Generic", colorHex: 0xAEB4BC)
  ]
}

struct PanelStat: Identifiable {
  let id: String
  let title: String
  let value: String
  let symbol: String
  let color: Color

  static let samples = [
    PanelStat(id: "projects", title: "Projects", value: "214", symbol: "folder.fill", color: Color(hex: 0x7FAE9A)),
    PanelStat(id: "photos", title: "Photos", value: "8426", symbol: "photo.fill", color: Color(hex: 0x7FA6C9)),
    PanelStat(id: "companies", title: "Companies", value: "19", symbol: "building.2.fill", color: Color(hex: 0xAEB4BC)),
    PanelStat(id: "customers", title: "Customers", value: "67", symbol: "person.2.fill", color: Color(hex: 0xA895C8))
  ]
}

struct BoardType: Identifiable {
  let id: String
  let name: String
  let subtitle: String
  let symbol: String
  let color: Color
  var emoji: String? = nil
  var localName: String? = nil
  var overview: String? = nil
  var typicalUses: [String] = []
  var typicalComponents: [String] = []
  var designChecks: [String] = []
  var notes: [String] = []

  static let fallback = BoardType(
    id: "board",
    name: "Board",
    subtitle: "Distribution board",
    symbol: "rectangle.3.group.fill",
    color: Color(hex: 0x5E78FF),
    overview: "A general low-voltage electrical assembly used to distribute, protect, control, meter or switch electrical circuits.",
    typicalUses: ["General project documentation", "Custom boards that do not fit a standard category"],
    typicalComponents: ["Main isolator or breaker", "MCBs/MCCBs", "Busbars", "Terminals", "N and PE bars"],
    designChecks: ["Rated current", "Short-circuit rating", "IP rating", "Cable entries", "Clear labeling"]
  )

  static let samples = [
    BoardType(id: "main-lv", name: "Main LV Board", subtitle: "Main low-voltage intake", symbol: "bolt.fill", color: Color(hex: 0x0A84FF), localName: "לוח ראשי", overview: "The main low-voltage switchboard for a building, floor group, factory area or service. It receives the main supply and distributes power downstream to sub boards, mechanical loads and specialist panels.", typicalUses: ["Commercial and industrial main supply", "Building incoming service", "Factory main distribution"], typicalComponents: ["Main ACB/MCCB or switch disconnector", "Metering and CTs", "Busbars", "Surge protection", "Outgoing MCCBs"], designChecks: ["Incoming supply and service size", "Icu/Ics short-circuit rating", "Form of separation", "Ventilation and heat rise", "Clear source and outgoing labels"], notes: ["Often called לוח ראשי in Israel.", "Commonly documented against IEC 61439 low-voltage assembly concepts."]),
    BoardType(id: "mdb", name: "MDB", subtitle: "Main Distribution", symbol: "bolt.square.fill", color: Color(hex: 0x5E78FF), localName: "לוח חלוקה ראשי", overview: "A main distribution board that splits a major feeder into multiple outgoing feeders. It may be the main LV board or a major distribution board below the main intake.", typicalUses: ["Office towers", "Malls", "Hospitals", "Large public buildings"], typicalComponents: ["Main MCCB/ACB", "Outgoing MCCBs", "Busbar system", "Power meter", "SPD"], designChecks: ["Load diversity", "Phase balance", "Cable termination space", "Future spare ways", "Selective protection coordination"]),
    BoardType(id: "sub-distribution", name: "Sub Distribution", subtitle: "Sub boards", symbol: "point.3.connected.trianglepath.dotted", color: Color(hex: 0x18D4E8), localName: "לוח משנה", overview: "A downstream distribution board fed from a main board or MDB. It supplies a zone, floor, tenant, machine area or service room.", typicalUses: ["Floor boards", "Tenant boards", "Mechanical-room sub boards", "Area distribution"], typicalComponents: ["Incoming isolator/MCCB", "MCBs/RCBOs", "RCD/RCCB protection", "N and PE bars", "DIN rails"], designChecks: ["Feeder rating", "Voltage drop", "Fault loop/short-circuit level", "RCD requirements", "Circuit labeling"]),
    BoardType(id: "mcc", name: "MCC", subtitle: "Motor Control Center", symbol: "gearshape.fill", color: Color(hex: 0x35E177), localName: "לוח מנועים / MCC", overview: "A board dedicated to motor feeders and motor control. It centralizes motor protection, switching, control and automation interfaces.", typicalUses: ["Pumps", "Fans", "Conveyors", "Industrial machines", "HVAC plant"], typicalComponents: ["MCCBs/MCBs", "Contactors", "Overload relays", "VFDs or soft starters", "Control transformers", "PLC/IO terminals"], designChecks: ["Motor kW and starting method", "AC-3 contactor rating", "Overload setting range", "Control voltage", "Ventilation for drives"]),
    BoardType(id: "cabinet-collection", name: "Cabinet Collection", subtitle: "Multi-cabinet assembly", symbol: "rectangle.3.group.bubble.left.fill", color: Color(hex: 0x8EA2FF), localName: "מערך ארונות", overview: "A cabinet collection is a board record used when one electrical board is physically built from several connected cabinets or bays. It keeps the cabinets grouped under one board number while still allowing build progress and photos to be tracked together.", typicalUses: ["Multi-cabinet MDBs", "Large MCC lineups", "Sectioned distribution boards", "Panel rows with shared busbars"], typicalComponents: ["Shared busbar system", "Inter-cabinet wiring", "Main breaker section", "Outgoing feeder sections", "N and PE bars"], designChecks: ["Cabinet order", "Busbar continuity", "Inter-cabinet links", "Transport split points", "Consistent labels across cabinets"]),
    BoardType(id: "ats", name: "ATS", subtitle: "Automatic Transfer Switch", symbol: "arrow.left.arrow.right", color: Color(hex: 0x8B4DFF), localName: "לוח החלפה / ATS", overview: "A transfer board that switches loads between normal utility supply and an alternate source such as generator or UPS. It may be automatic or manual depending on project needs.", typicalUses: ["Generator-backed buildings", "Critical loads", "Fire/safety services", "Data and telecom rooms"], typicalComponents: ["Motorized changeover switch or contactors", "Controller", "Source voltage sensing", "Mechanical/electrical interlocking", "Bypass or manual mode"], designChecks: ["Source interlocking", "Neutral switching method", "Generator start signal", "Transfer delay settings", "Load priority"]),
    BoardType(id: "metering", name: "Metering Board", subtitle: "Meters and CTs", symbol: "gauge.with.dots.needle.67percent", color: Color(hex: 0x64D2FF), localName: "לוח מונים", overview: "A board or section used for energy metering, tenant metering, CT wiring and monitoring equipment.", typicalUses: ["Tenant billing", "Energy monitoring", "Utility/customer metering sections"], typicalComponents: ["Energy meters", "CTs", "Test blocks", "Voltage fuses", "Communication modules"], designChecks: ["CT ratio and class", "Sealable compartments", "Meter access", "Phase order", "Communication wiring"]),
    BoardType(id: "capacitor", name: "Capacitor Bank", subtitle: "Power factor correction", symbol: "waveform.path.ecg.rectangle.fill", color: Color(hex: 0xFFD60A), localName: "לוח קבלים", overview: "A power-factor correction board that switches capacitor stages to improve power factor and reduce reactive energy penalties.", typicalUses: ["Factories", "Large commercial buildings", "Motor-heavy installations"], typicalComponents: ["PFC controller", "Capacitor contactors", "Capacitor stages", "HRC fuses/MCCBs", "Detuned reactors when needed"], designChecks: ["kVAr sizing", "Harmonic environment", "Ventilation", "Discharge resistors", "Stage protection"]),
    BoardType(id: "control", name: "Control Board", subtitle: "Controls and automation", symbol: "switch.2", color: Color(hex: 0xD85CFF), localName: "לוח פיקוד", overview: "A control panel focused on command, indication, automation and interlocking rather than heavy power distribution.", typicalUses: ["Machine control", "Pump control", "HVAC control", "Process automation"], typicalComponents: ["PLC or controller", "Relays", "Timers", "Power supplies", "Terminals", "Selector switches and lamps"], designChecks: ["Control voltage", "Input/output list", "Fail-safe logic", "Cable numbering", "Door controls and indicators"]),
    BoardType(id: "lighting", name: "Lighting", subtitle: "Lighting boards", symbol: "lightbulb.fill", color: Color(hex: 0xFFD60A), localName: "לוח תאורה", overview: "A distribution board dedicated to lighting circuits, lighting control and sometimes emergency lighting groups.", typicalUses: ["Office floors", "Public areas", "Exterior lighting", "Emergency lighting circuits"], typicalComponents: ["MCBs/RCBOs", "Contactors", "Astronomical clock or timer", "Lighting controllers", "RCD protection"], designChecks: ["Circuit grouping", "Emergency/normal separation", "Control schedule", "RCD selectivity", "Clear room/area labels"]),
    BoardType(id: "power", name: "Power", subtitle: "Power boards", symbol: "powerplug.fill", color: Color(hex: 0xFF4E5F), localName: "לוח כח", overview: "A board feeding socket circuits, small power, dedicated equipment outlets and general power loads.", typicalUses: ["Workstations", "Kitchen equipment", "Workshop outlets", "Mechanical service outlets"], typicalComponents: ["MCBs/RCBOs", "RCDs", "Socket circuit terminals", "Main isolator", "N and PE bars"], designChecks: ["Load per circuit", "RCD protection", "Dedicated equipment circuits", "Socket labeling", "Spare capacity"]),
    BoardType(id: "apartment", name: "Apartment", subtitle: "Residential boards", symbol: "house.fill", color: Color(hex: 0x35C7D7), localName: "לוח דירתי", overview: "A residential distribution board serving an apartment or small dwelling, usually with final circuits for lighting, sockets, HVAC and appliances.", typicalUses: ["Apartments", "Small homes", "Residential units"], typicalComponents: ["Main switch", "RCD/RCCB", "MCBs/RCBOs", "Surge protection", "N and PE bars"], designChecks: ["Circuit count", "RCD arrangement", "Main rating", "Future spaces", "Clear room/appliance labels"]),
    BoardType(id: "generator", name: "Generator Board", subtitle: "Generator distribution", symbol: "fuelpump.fill", color: Color(hex: 0xFF9F0A), localName: "לוח גנרטור", overview: "A board associated with generator output, protection, synchronization or distribution to emergency/backup loads.", typicalUses: ["Backup supply", "Emergency power rooms", "Generator packages"], typicalComponents: ["Generator MCCB/ACB", "Controller terminals", "Meters", "Protection relays", "Outgoing breakers"], designChecks: ["Generator rating", "Earthing/neutral method", "ATS interface", "Short-circuit contribution", "Load shedding"]),
    BoardType(id: "ups", name: "UPS Board", subtitle: "Critical power", symbol: "battery.100percent.bolt", color: Color(hex: 0x34C759), localName: "לוח UPS", overview: "A board feeding or distributing uninterruptible power supply circuits for critical equipment.", typicalUses: ["Server rooms", "Security systems", "Medical/critical equipment", "Control systems"], typicalComponents: ["UPS input/output breakers", "Maintenance bypass", "Critical load MCBs", "Meters", "Warning labels"], designChecks: ["Bypass arrangement", "Load criticality", "Neutral continuity", "Battery room/interface", "Segregation from normal power"]),
    BoardType(id: "pv", name: "PV Solar", subtitle: "Solar AC/DC board", symbol: "sun.max.fill", color: Color(hex: 0xFFCC00), localName: "לוח סולארי", overview: "A photovoltaic board for inverter AC output, DC string combining, protection or solar system isolation.", typicalUses: ["Rooftop PV", "Commercial solar systems", "Inverter rooms"], typicalComponents: ["DC isolators", "String fuses", "SPD DC/AC", "AC breakers", "Inverter feeders"], designChecks: ["DC voltage rating", "Polarity", "SPD type", "Inverter AC rating", "Warning labels and isolation"]),
    BoardType(id: "ev", name: "EV Charging", subtitle: "Charging infrastructure", symbol: "ev.charger.fill", color: Color(hex: 0x00C7BE), localName: "לוח טעינה לרכב חשמלי", overview: "A board dedicated to electric vehicle charging circuits and load management equipment.", typicalUses: ["Parking lots", "Residential charging rooms", "Commercial EV chargers"], typicalComponents: ["MCCBs/MCBs", "RCD type A/B or RDC-DD coordination", "Meters", "Load management controller", "Surge protection"], designChecks: ["Charger rating", "Diversity/load management", "RCD type", "Cable route length", "Metering and access"]),
    BoardType(id: "temporary-site", name: "Site Temporary", subtitle: "Construction site power", symbol: "hammer.fill", color: Color(hex: 0xAEB4BC), localName: "לוח זמני לאתר", overview: "A temporary distribution board for construction sites or temporary works, often ruggedized and protected for outdoor/site conditions.", typicalUses: ["Construction sites", "Temporary events", "Site cabins", "Temporary tools"], typicalComponents: ["Main breaker/RCD", "Socket outlets", "Outgoing MCBs", "Enclosure with high IP rating", "Earthing terminals"], designChecks: ["Outdoor/IP protection", "RCD protection", "Mechanical protection", "Temporary earthing", "Inspection labeling"]),
    BoardType(id: "fire-pump", name: "Fire Pump", subtitle: "Life-safety motor board", symbol: "flame.fill", color: Color(hex: 0xFF453A), localName: "לוח משאבות כיבוי", overview: "A specialized control and power board for fire pumps and related life-safety equipment.", typicalUses: ["Fire pump rooms", "Sprinkler systems", "Emergency water systems"], typicalComponents: ["Main isolator/breaker", "Pump contactors or soft starter", "Controller", "Alarms", "Pressure switch terminals"], designChecks: ["Life-safety supply requirements", "Alarm outputs", "Manual/auto operation", "Motor starting current", "Clear emergency labeling"]),
    BoardType(id: "hvac", name: "HVAC", subtitle: "Mechanical services", symbol: "fan.fill", color: Color(hex: 0x5AC8FA), localName: "לוח מיזוג / אוורור", overview: "A board serving chillers, AHUs, fans, dampers and mechanical ventilation/control loads.", typicalUses: ["Air handling units", "Ventilation fans", "Chillers", "Mechanical plant rooms"], typicalComponents: ["MCCBs/MCBs", "Contactors", "VFDs", "Overloads", "Control relays", "BMS terminals"], designChecks: ["Motor and drive heat", "BMS interface", "Local/remote control", "Maintenance isolators", "Fault indication"]),
    BoardType(id: "elv-bms", name: "ELV / BMS", subtitle: "Low-current systems", symbol: "network", color: Color(hex: 0xAF52DE), localName: "לוח תקשורת / בקרה", overview: "A low-current or building-management panel for control, communications and monitoring equipment. It is usually separate from power distribution.", typicalUses: ["BMS panels", "Security interfaces", "Communication cabinets", "Monitoring systems"], typicalComponents: ["Power supplies", "Network switches", "Controllers", "Relays", "Terminal blocks"], designChecks: ["Separation from power circuits", "24VDC load sizing", "Network labeling", "Backup supply", "Cable management"]),
    BoardType(id: "pcc", name: "PCC", subtitle: "Power control center", symbol: "slider.horizontal.3", color: Color(hex: 0x30D158), localName: "לוח כח ראשי / PCC", overview: "A power control center is a heavy-duty low-voltage assembly used for main feeders, large loads and plant-level power distribution. It often sits close to transformers, generators or major mechanical loads.", typicalUses: ["Industrial plant rooms", "Large mechanical services", "Transformer outgoing distribution"], typicalComponents: ["ACBs/MCCBs", "Busbar system", "Metering", "Protection relays", "Outgoing feeders"], designChecks: ["Short-circuit level", "Form of separation", "Thermal rise", "Access and maintenance clearance", "Feeder selectivity"]),
    BoardType(id: "synchronizing", name: "Synchronizing", subtitle: "Generator sync board", symbol: "arrow.triangle.2.circlepath", color: Color(hex: 0x64D2FF), localName: "לוח סנכרון", overview: "A synchronizing board controls and protects parallel operation of generators or generator-to-grid arrangements. It monitors voltage, frequency, phase angle and load sharing before closing breakers.", typicalUses: ["Multiple generator sets", "Generator-grid parallel operation", "Critical facilities"], typicalComponents: ["Sync controller", "ACB/MCCB control", "Protection relays", "Meters", "Load sharing modules"], designChecks: ["Phase sequence", "Voltage and frequency windows", "Breaker interlocks", "Load sharing setup", "Protection coordination"]),
    BoardType(id: "bypass", name: "Bypass Board", subtitle: "Maintenance bypass", symbol: "arrow.uturn.right.circle.fill", color: Color(hex: 0xFF9F0A), localName: "לוח מעקף", overview: "A bypass board allows critical loads to remain supplied while UPS, ATS or other equipment is isolated for service. It must make the switching path clear and hard to operate incorrectly.", typicalUses: ["UPS maintenance", "ATS maintenance", "Critical service isolation"], typicalComponents: ["Bypass switch", "Interlocked isolators", "Indication lamps", "Warning labels", "Meters"], designChecks: ["Mechanical/electrical interlocks", "Clear operating sequence", "Neutral arrangement", "Load transfer path", "Warning labels"]),
    BoardType(id: "transformer", name: "Transformer Board", subtitle: "Transformer feeder", symbol: "square.stack.3d.up.fill", color: Color(hex: 0xBF5AF2), localName: "לוח שנאי", overview: "A transformer board handles incoming or outgoing protection and distribution around a transformer. It may include LV main protection, metering and temperature/alarm interfaces.", typicalUses: ["Transformer rooms", "Industrial substations", "Building LV rooms"], typicalComponents: ["Main ACB/MCCB", "Meters", "Protection relay inputs", "Temperature alarm terminals", "Busbars"], designChecks: ["Transformer kVA", "Inrush and protection settings", "Earthing system", "Ventilation", "Cable termination space"]),
    BoardType(id: "pump", name: "Pump Board", subtitle: "Water and process pumps", symbol: "drop.fill", color: Color(hex: 0x0A84FF), localName: "לוח משאבות", overview: "A pump board controls one or more water, sewage or process pumps. It may include direct-on-line starters, star-delta, soft starters or drives depending on pump size.", typicalUses: ["Booster pumps", "Sewage pumps", "Process pumps", "Irrigation systems"], typicalComponents: ["Contactors", "Overload relays", "VFDs or soft starters", "Float/pressure inputs", "Run/fault indication"], designChecks: ["Pump kW", "Duty/standby logic", "Sensor inputs", "Manual/auto control", "Alarm output"]),
    BoardType(id: "elevator", name: "Elevator", subtitle: "Lift supply board", symbol: "arrow.up.arrow.down.square.fill", color: Color(hex: 0x5E78FF), localName: "לוח מעלית", overview: "An elevator board supplies lift controllers and associated services. It often needs clear isolation, dedicated feeds and coordination with emergency or generator-backed supply.", typicalUses: ["Passenger lifts", "Service lifts", "Lift machine rooms"], typicalComponents: ["Main isolator/MCCB", "Auxiliary MCBs", "SPD", "Meters", "Emergency supply interface"], designChecks: ["Dedicated supply", "Rescue/emergency power", "Isolation access", "Labeling", "Manufacturer requirements"]),
    BoardType(id: "outdoor-lighting", name: "Outdoor Lighting", subtitle: "Street and facade lighting", symbol: "lightbulb.2.fill", color: Color(hex: 0xFFD60A), localName: "לוח תאורת חוץ", overview: "An outdoor lighting board feeds street, parking, facade or landscape lighting. It usually combines protection with automatic schedules and weather-ready enclosure choices.", typicalUses: ["Parking lots", "Street lighting", "Facade lighting", "Landscape lighting"], typicalComponents: ["MCBs/RCBOs", "Contactors", "Astronomical clock", "SPD", "Photocell inputs"], designChecks: ["IP rating", "Earthing", "Cable lengths", "Control schedule", "Surge exposure"]),
    BoardType(id: "pdu", name: "PDU", subtitle: "Data center distribution", symbol: "server.rack", color: Color(hex: 0x32D74B), localName: "לוח PDU", overview: "A power distribution unit board distributes critical power to server racks, telecom equipment or data cabinets. It often emphasizes metering, redundancy and clean circuit identification.", typicalUses: ["Server rooms", "Data centers", "Telecom spaces"], typicalComponents: ["Input MCCB", "Metering", "Branch MCBs", "RCD/RCM where required", "Monitoring modules"], designChecks: ["A/B feed separation", "Load monitoring", "Circuit labeling", "Neutral loading", "Thermal management"]),
    BoardType(id: "harmonic-filter", name: "Harmonic Filter", subtitle: "Power quality", symbol: "waveform.path", color: Color(hex: 0xFF375F), localName: "לוח סינון הרמוניות", overview: "A harmonic filter board reduces harmonic distortion caused by drives, UPS systems and non-linear loads. It may be passive or active depending on the installation.", typicalUses: ["Drive-heavy plants", "UPS rooms", "Large commercial buildings", "Power quality correction"], typicalComponents: ["Active filter module", "Detuned reactors", "Capacitors", "MCCB/fuses", "Controller"], designChecks: ["Measured THD", "Load profile", "Ventilation", "Protection sizing", "Power quality target"]),
    BoardType(id: "fire-alarm", name: "Fire Alarm", subtitle: "Life-safety controls", symbol: "bell.and.waves.left.and.right.fill", color: Color(hex: 0xFF453A), localName: "לוח גילוי אש", overview: "A fire alarm or life-safety interface panel organizes control power, relays and monitored circuits around fire detection and emergency systems. It should remain clearly separated from ordinary power distribution.", typicalUses: ["Fire alarm interfaces", "Smoke control interfaces", "Emergency command panels"], typicalComponents: ["Power supplies", "Relays", "Monitoring modules", "Terminal blocks", "Battery/interface wiring"], designChecks: ["Life-safety labeling", "Circuit supervision", "Backup supply", "Cable separation", "Alarm/fault outputs"]),
    BoardType(id: "earthing", name: "Earthing", subtitle: "Grounding and bonding", symbol: "point.bottomleft.forward.to.point.topright.scurvepath", color: Color(hex: 0x8E8E93), localName: "לוח הארקה", overview: "An earthing or bonding board centralizes grounding bars, test links and bonding connections for an installation. It is often simple physically but very important for safety and documentation.", typicalUses: ["Main earthing terminals", "Lightning protection bonds", "Telecom bonding", "Industrial equipotential bonding"], typicalComponents: ["Copper earth bar", "Test links", "Labels", "Bonding terminals", "Surge protection bonds"], designChecks: ["Conductor sizes", "Continuity", "Labeling", "Test accessibility", "Separation from live parts"])
  ]
}

struct ProjectItem: Identifiable {
  let id: String
  let name: String
  let customer: String
  let detail: String
  let status: String
  var color: Color
  var dueDate: Date? = nil
  var schemeAttachments: [SchemeAttachment] = []

  /// Photos are held as image-store tokens, not as decoded UIImages, so a
  /// project with a thousand photos costs the same to keep in memory as one
  /// with none. The accessors below resolve them on demand.
  var coverToken: String? = nil
  var photoTokens: [String] = []

  var coverImage: UIImage? {
    get { ImageStore.shared.image(for: coverToken) }
    set { coverToken = ImageStore.shared.store(newValue) }
  }

  /// Cheap enough for list rows — prefer this over [coverImage] in scrolling
  /// views, which would decode the full-size original per row.
  var coverThumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: coverToken)
  }

  var photoCount: Int { photoTokens.count }

  /// Every token this project owns, for orphan cleanup.
  var imageTokens: [String] {
    ([coverToken] + photoTokens + schemeAttachments.map(\.imageToken)).compactMap { $0 }
  }

  var searchText: String {
    "\(name) \(customer) \(detail) \(status) \(dueDate.map { DateDisplay.due.string(from: $0) } ?? "") \(schemeAttachments.map(\.name).joined(separator: " "))"
  }

  var persistenceSignature: String {
    let coverSignature = ImageStore.shared.signature(for: coverToken)
    let photoSignature = photoTokens.joined(separator: "|")
    let schemeSignature = schemeAttachments.map(\.persistenceSignature).joined(separator: "|")
    return [
      id, name, customer, detail, status, "\(color.archiveHex)",
      coverSignature, photoSignature,
      "\(dueDate?.timeIntervalSince1970 ?? 0)",
      schemeSignature
    ].joined(separator: "||")
  }

  static let samples: [ProjectItem] = []
}

struct ComponentGroup: Identifiable {
  let id: String
  let name: String
  let items: [PanelComponent]

  static let samples = [
    ComponentGroup(id: "mcbs", name: "MCBs", items: [
      PanelComponent(id: "abb-s201-1p", manufacturer: "ABB", type: "MCB", model: "S201", rating: "Set A", poles: "1P", curve: "B/C/D Curve", about: "Single-pole miniature circuit breaker for one final circuit, protecting against overload and short circuit. Pick the curve for the load: B for resistive and lighting, C for general mixed loads, D for high-inrush motors and transformers."),
      PanelComponent(id: "abb-s202-2p", manufacturer: "ABB", type: "MCB", model: "S202", rating: "Set A", poles: "2P", curve: "B/C/D Curve", about: "Two-pole MCB that breaks line and neutral together, common on single-phase circuits where full isolation is required for maintenance."),
      PanelComponent(id: "abb-s203-3p", manufacturer: "ABB", type: "MCB", model: "S203", rating: "Set A", poles: "3P", curve: "B/C/D Curve", about: "Three-pole MCB for three-phase loads. All three poles trip together so a fault on one phase cannot leave a motor running single-phased."),
      PanelComponent(id: "abb-s204-4p", manufacturer: "ABB", type: "MCB", model: "S204", rating: "Set A", poles: "4P", curve: "B/C/D Curve", about: "Four-pole MCB breaking three phases plus neutral, used where the neutral must be isolated, such as on generator or changeover circuits."),
      PanelComponent(id: "abb-sn201-1pn", manufacturer: "ABB", type: "MCB", model: "SN201", rating: "Set A", poles: "1P+N", curve: "B/C Curve", about: "One pole plus switched neutral in a single module width, the usual choice for apartment and lighting boards where DIN space is tight."),
      PanelComponent(id: "abb-s300-p", manufacturer: "ABB", type: "MCB", model: "S300 P", rating: "Set A", poles: "1P-4P", curve: "Industrial", about: "Industrial-grade MCB with a higher breaking capacity than domestic ranges. Specify where the prospective short-circuit current at the board exceeds what a standard 6kA device can clear."),
      PanelComponent(id: "abb-su200", manufacturer: "ABB", type: "MCB", model: "SU200", rating: "Set A", poles: "1P-4P", curve: "UL/CSA", about: "MCB built to UL and CSA ratings for panels destined for North American markets or for machinery exported there."),
      PanelComponent(id: "schneider-ic60n", manufacturer: "Schneider", type: "MCB", model: "Acti9 iC60N", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Standard Acti9 MCB at 6kA breaking capacity, suitable for most commercial final circuits. Pairs with Vigi add-on blocks if earth-leakage protection is needed later."),
      PanelComponent(id: "schneider-ic60h", manufacturer: "Schneider", type: "MCB", model: "Acti9 iC60H", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Higher breaking capacity version of the iC60 for boards closer to the transformer where fault levels are greater."),
      PanelComponent(id: "siemens-5sy", manufacturer: "Siemens", type: "MCB", model: "SENTRON 5SY", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "General purpose SENTRON MCB for final circuit protection across lighting, socket and small power circuits."),
      PanelComponent(id: "siemens-5sl", manufacturer: "Siemens", type: "MCB", model: "SENTRON 5SL", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Compact economy MCB for high-volume repeat circuits in residential and light commercial boards."),
      PanelComponent(id: "eaton-faz", manufacturer: "Eaton", type: "MCB", model: "FAZ", rating: "Set A", poles: "1P-4P", curve: "B/C/D", about: "Eaton MCB range with a wide curve and rating selection, frequently specified in machine-building and OEM panels.")
    ]),
    ComponentGroup(id: "rcbo", name: "RCBOs & RCDs", items: [
      PanelComponent(id: "abb-ds201-1pn", manufacturer: "ABB", type: "RCBO", model: "DS201", rating: "Set A", poles: "1P+N", curve: "B/C Curve + RCD", about: "Combined MCB and residual current device in one module: overload, short-circuit and earth-leakage protection for a single circuit. Common at 30mA for socket outlets requiring additional protection."),
      PanelComponent(id: "abb-ds202-2p", manufacturer: "ABB", type: "RCBO", model: "DS202", rating: "Set A", poles: "2P", curve: "B/C Curve + RCD", about: "Two-pole RCBO providing overcurrent and earth-leakage protection while isolating both line and neutral."),
      PanelComponent(id: "abb-ds203-3p", manufacturer: "ABB", type: "RCBO", model: "DS203", rating: "Set A", poles: "3P", curve: "B/C Curve + RCD", about: "Three-pole RCBO for three-phase circuits needing residual current protection without a separate upstream RCCB."),
      PanelComponent(id: "abb-ds204-4p", manufacturer: "ABB", type: "RCBO", model: "DS204", rating: "Set A", poles: "4P", curve: "B/C Curve + RCD", about: "Four-pole RCBO covering three phases and neutral. Used where individual circuit discrimination matters more than a single shared RCCB."),
      PanelComponent(id: "abb-ds200", manufacturer: "ABB", type: "RCBO", model: "DS200", rating: "up to 63A", poles: "1P+N/3P+N", curve: "30-300mA, 10kA", about: "Higher breaking capacity RCBO range for boards with elevated fault levels where a standard 6kA device would be inadequate."),
      PanelComponent(id: "schneider-acti9-rcbo", manufacturer: "Schneider", type: "RCBO", model: "Acti9 iDPN Vigi", rating: "Set A", poles: "1P+N", curve: "B/C + RCD", about: "Acti9 RCBO in one module width, giving each circuit its own earth-leakage protection so a single fault does not trip an entire board section."),
      PanelComponent(id: "generic-rccb", manufacturer: "Generic", type: "RCD/RCCB", model: "Residual Current Device", rating: "Set A", poles: "2P/4P", curve: "30-300mA", about: "Residual current circuit breaker detecting earth leakage but offering no overload protection, so it always sits behind or above separate overcurrent devices. Choose the type by load: AC for simple resistive, A where electronics are present, B where drives or DC components can produce smooth residual currents."),
      PanelComponent(id: "abb-f200", manufacturer: "ABB", type: "RCD/RCCB", model: "F200", rating: "25-125A", poles: "2P/4P", curve: "30-500mA, Type AC/A", about: "Residual current circuit breaker protecting a group of circuits against earth leakage. At 30mA it provides additional protection against electric shock; at 300mA it is normally used for fire protection on a whole section."),
      PanelComponent(id: "schneider-iid", manufacturer: "Schneider", type: "RCD/RCCB", model: "Acti9 iID", rating: "25-100A", poles: "2P/4P", curve: "30-300mA, Type AC/A/B", about: "Acti9 residual current device available in Type A and Type B. Type B is required where variable speed drives can produce smooth DC residual current that would blind a Type AC device."),
      PanelComponent(id: "siemens-5sv", manufacturer: "Siemens", type: "RCD/RCCB", model: "SENTRON 5SV", rating: "25-125A", poles: "2P/4P", curve: "30-300mA", about: "SENTRON RCCB for group earth-leakage protection. Consider splitting circuits across several RCCBs so one nuisance trip does not take out an entire board.")
    ]),
    ComponentGroup(id: "mccbs", name: "MCCBs & ACBs", items: [
      PanelComponent(id: "abb-tmax-xt1", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT1", rating: "Set A - max 160A", poles: "3P/4P", curve: "Basic - thermal-magnetic", about: "Compact moulded case breaker for feeders up to 160A with a fixed thermal-magnetic trip. Suits outgoing ways on small distribution boards."),
      PanelComponent(id: "abb-tmax-xt2", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT2", rating: "Set A - max 160A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch", about: "160A frame with a choice of thermal-magnetic or Ekip electronic trip units, giving adjustable settings for selectivity against downstream devices."),
      PanelComponent(id: "abb-tmax-xt3", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT3", rating: "Set A - max 250A", poles: "3P/4P", curve: "Basic - thermal-magnetic", about: "250A frame thermal-magnetic breaker for mid-size feeders and sub-board supplies."),
      PanelComponent(id: "abb-tmax-xt4", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT4", rating: "Set A - max 250A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch", about: "250A frame with electronic trip options, used where adjustable overload and instantaneous settings are needed to coordinate with upstream protection."),
      PanelComponent(id: "abb-tmax-xt5", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT5", rating: "Set A - max 630A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch", about: "400 to 630A frame for major feeders, transformer outgoings and sub-main distribution."),
      PanelComponent(id: "abb-tmax-xt6", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT6", rating: "Set A - max 1000A", poles: "3P/4P", curve: "Basic - thermal-magnetic/Ekip Dip", about: "630 to 800A frame typically used as a main incomer on medium boards or feeding large mechanical plant."),
      PanelComponent(id: "abb-tmax-xt7", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT7", rating: "Set A - max 1600A", poles: "3P/4P", curve: "Heavy duty - Ekip Dip/Touch", about: "1000 to 1600A frame for main incoming protection on large distribution boards where an air circuit breaker is not required."),
      PanelComponent(id: "abb-tmax-xt7m", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT7 M", rating: "Set A - max 1600A", poles: "3P/4P", curve: "Motorized - Ekip Dip/Touch", about: "Motorised version of the XT7 for remote or automatic operation, used in transfer schemes and where remote tripping is part of the control philosophy."),
      PanelComponent(id: "schneider-nsx", manufacturer: "Schneider", type: "MCCB", model: "Compact NSX", rating: "16-630A", poles: "3P/4P", curve: "TM/Micrologic", about: "Compact NSX moulded case breaker with interchangeable TM or Micrologic trip units. The electronic units add metering and adjustable protection curves."),
      PanelComponent(id: "schneider-nsj", manufacturer: "Schneider", type: "MCCB", model: "EasyPact CVS/NSX", rating: "16-630A", poles: "3P/4P", curve: "Thermal Magnetic", about: "Cost-focused moulded case breaker for standard distribution feeders where adjustable electronic protection is not required."),
      PanelComponent(id: "siemens-3va1", manufacturer: "Siemens", type: "MCCB", model: "SENTRON 3VA1", rating: "16-160A", poles: "3P/4P", curve: "Thermal Magnetic", about: "SENTRON moulded case breaker with thermal-magnetic trip for general distribution feeders."),
      PanelComponent(id: "siemens-3va2", manufacturer: "Siemens", type: "MCCB", model: "SENTRON 3VA2", rating: "25-630A", poles: "3P/4P", curve: "ETU", about: "SENTRON breaker with electronic trip units and optional communications, suited to boards where energy data and selectivity are both required."),
      PanelComponent(id: "eaton-nzm", manufacturer: "Eaton", type: "MCCB", model: "NZM", rating: "20-1600A", poles: "3P/4P", curve: "Electronic/TM", about: "Eaton moulded case breaker range covering a wide band of frame sizes, common as both incomer and outgoing protection in industrial boards."),
      PanelComponent(id: "eaton-bzmx", manufacturer: "Eaton", type: "MCCB", model: "BZMX", rating: "15-250A", poles: "3P/4P", curve: "Thermal Magnetic", about: "Compact moulded case breaker for smaller feeders where space in the board is limited."),
      PanelComponent(id: "generic-acb", manufacturer: "Generic", type: "ACB", model: "Air Circuit Breaker", rating: "Set A", poles: "3P/4P", curve: "Withdrawable/fixed", about: "Air circuit breaker for main incoming protection at high current, typically above 800A. Decide early whether it is fixed or withdrawable, since withdrawable versions need far more depth and a defined racking area in front of the board."),
      PanelComponent(id: "abb-emax2", manufacturer: "ABB", type: "ACB", model: "SACE Emax 2", rating: "630-6300A", poles: "3P/4P", curve: "Fixed or withdrawable", about: "Air circuit breaker for main incoming protection with Ekip trip units offering full protection, metering and communications. Withdrawable versions allow maintenance without a full shutdown but need defined racking space in front of the board."),
      PanelComponent(id: "schneider-mtz", manufacturer: "Schneider", type: "ACB", model: "MasterPact MTZ", rating: "630-6300A", poles: "3P/4P", curve: "Micrologic X", about: "Main air circuit breaker with Micrologic X control units providing measurement, diagnostics and remote connectivity. Common as the incomer on large main LV boards."),
      PanelComponent(id: "siemens-3wa", manufacturer: "Siemens", type: "ACB", model: "SENTRON 3WA", rating: "630-6300A", poles: "3P/4P", curve: "ETU trip unit", about: "SENTRON air circuit breaker for main and coupler positions. Confirm the trip unit family early since it drives the metering and communications you can offer later."),
      PanelComponent(id: "eaton-izmx", manufacturer: "Eaton", type: "ACB", model: "IZMX", rating: "630-1600A", poles: "3P/4P", curve: "Fixed or withdrawable", about: "Compact air circuit breaker for main protection where panel depth is constrained but ACB features are still required.")
    ]),
    ComponentGroup(id: "surge-arc", name: "Surge & Arc Protection", items: [
      PanelComponent(id: "generic-spd", manufacturer: "Generic", type: "SPD", model: "Surge Protection Device", rating: "Type 2", poles: "3P+N", curve: "40kA", about: "Surge protection device diverting transient overvoltage from lightning and switching to earth. Type 1 goes at the origin where there is a lightning protection system, Type 2 at distribution boards. It needs a correctly rated backup fuse or breaker and the shortest possible connecting leads."),
      PanelComponent(id: "abb-ovr", manufacturer: "ABB", type: "SPD", model: "OVR T2", rating: "Type 2", poles: "1P-4P", curve: "40kA Imax", about: "Type 2 surge arrester for distribution boards, diverting switching and induced lightning transients. Keep the connecting leads under half a metre or the let-through voltage rises sharply."),
      PanelComponent(id: "schneider-iprd", manufacturer: "Schneider", type: "SPD", model: "Acti9 iPRD", rating: "Type 2", poles: "1P-4P", curve: "20-65kA", about: "Acti9 surge protection with a status window showing when the cartridge is spent, and a remote signalling contact so a failed arrester does not sit unnoticed."),
      PanelComponent(id: "phoenix-valms", manufacturer: "Phoenix", type: "SPD", model: "VAL-MS", rating: "Type 2", poles: "1P-4P", curve: "Pluggable", about: "Pluggable surge protection where the protection module can be replaced without disturbing the wiring, useful on boards in high-exposure locations."),
      PanelComponent(id: "abb-afdd", manufacturer: "ABB", type: "AFDD", model: "S-ARC1", rating: "6-40A", poles: "1P+N", curve: "B/C Curve", about: "Arc fault detection device recognising the signature of a series or parallel arcing fault that a normal MCB or RCD will not see. Specified for fire risk areas such as sleeping accommodation and timber structures."),
      PanelComponent(id: "siemens-5sm6", manufacturer: "Siemens", type: "AFDD", model: "5SM6", rating: "6-40A", poles: "1P+N", curve: "Combined MCB", about: "Arc fault detection combined with overcurrent protection in one device, reducing the DIN width needed compared with separate units."),
      PanelComponent(id: "abb-cm-iwx", manufacturer: "ABB", type: "RCM", model: "CM-IWx", rating: "30mA-30A", poles: "DIN", curve: "Residual current monitor", about: "Residual current monitor that measures and reports leakage continuously instead of tripping, letting you catch a deteriorating circuit before it causes an outage.")
    ]),
    ComponentGroup(id: "switching", name: "Switching & Isolation", items: [
      PanelComponent(id: "generic-isolator", manufacturer: "Generic", type: "Isolator", model: "Load break switch", rating: "Set A", poles: "3P/4P", curve: "Door-coupled", about: "Load break switch providing a visible, lockable point of isolation so a board or section can be worked on safely. Rated for making and breaking load current, unlike a plain disconnector."),
      PanelComponent(id: "abb-ot", manufacturer: "ABB", type: "Isolator", model: "OT switch disconnector", rating: "16-3150A", poles: "3P/4P", curve: "Door or base mount", about: "Switch disconnector for main isolation or outgoing feeders, available with door-coupled rotary handles that can be padlocked off for safe working."),
      PanelComponent(id: "schneider-ins", manufacturer: "Schneider", type: "Isolator", model: "Interpact INS", rating: "40-2500A", poles: "3P/4P", curve: "Load break", about: "Load break switch for isolation duty on incomers and outgoing feeders where switching capability without protection is required."),
      PanelComponent(id: "generic-changeover", manufacturer: "Generic", type: "Changeover Switch", model: "Manual changeover", rating: "Set A", poles: "4P", curve: "I-0-II", about: "Manual changeover switch selecting between two supplies, typically utility and generator. The I-0-II arrangement mechanically prevents both sources being connected at once."),
      PanelComponent(id: "socomec-sirco", manufacturer: "Socomec", type: "Changeover Switch", model: "Sirco MOT", rating: "125-3200A", poles: "3P/4P", curve: "Motorised I-0-II", about: "Motorised changeover switch for automatic transfer between utility and generator, mechanically interlocked so both sources can never be paralleled."),
      PanelComponent(id: "abb-ats021", manufacturer: "ABB", type: "ATS Controller", model: "ATS021", rating: "24VDC", poles: "DIN", curve: "Auto transfer control", about: "Automatic transfer controller monitoring the normal supply and commanding changeover to the standby source. Set the transfer and return delays deliberately so brief dips do not start the generator unnecessarily."),
      PanelComponent(id: "deepsea-dse", manufacturer: "Generic", type: "ATS Controller", model: "Generator controller", rating: "12/24VDC", poles: "Door mount", curve: "Auto mains failure", about: "Auto mains failure controller starting the generator on supply loss, transferring load and returning it once the mains is stable. It needs clear wiring to the generator start contacts and both source sensing points."),
      PanelComponent(id: "generic-fuse", manufacturer: "Generic", type: "Fuse", model: "NH fuse link", rating: "Set A", poles: "1P", curve: "gG/gL", about: "NH fuse link giving very high breaking capacity in a compact body, often used ahead of large feeders or where the fault level exceeds what a breaker can handle economically. gG is for general cable protection, aM for motor circuits."),
      PanelComponent(id: "generic-fuse-holder", manufacturer: "Generic", type: "Fuse Holder", model: "DIN fuse holder", rating: "Set A", poles: "1P/3P", curve: "10x38/NH", about: "DIN rail fuse carrier holding cartridge or NH fuse links, giving isolation when the carrier is withdrawn. Confirm the fuse size it accepts and whether a blown-fuse indicator is required."),
      PanelComponent(id: "abb-af16-30-10", manufacturer: "ABB", type: "Contactor", model: "AF16-30-10", rating: "16A", poles: "3P", curve: "1NO Aux", about: "Three-pole contactor around 16A AC-3 with one normally-open auxiliary, sized for small motors and controlled loads. The AF electronic coil accepts a wide voltage band, which reduces the number of coil variants to stock."),
      PanelComponent(id: "abb-af26-30-00", manufacturer: "ABB", type: "Contactor", model: "AF26-30-00", rating: "26A", poles: "3P", curve: "No Aux", about: "Mid-size three-pole contactor for motor and load switching where no built-in auxiliary contact is required."),
      PanelComponent(id: "abb-af38-30-00", manufacturer: "ABB", type: "Contactor", model: "AF38-30-00", rating: "38A", poles: "3P", curve: "No Aux", about: "Larger three-pole contactor for motors up to roughly 18.5kW at 400V. Check AC-3 rating against motor full-load amps rather than the AC-1 figure."),
      PanelComponent(id: "schneider-lc1d", manufacturer: "Schneider", type: "Contactor", model: "TeSys D", rating: "9-150A", poles: "3P", curve: "AC-3", about: "TeSys D contactor, the workhorse for motor starters and load switching. Add-on auxiliary blocks and mechanical interlocks let it build reversing and star-delta arrangements."),
      PanelComponent(id: "siemens-3rt", manufacturer: "Siemens", type: "Contactor", model: "SIRIUS 3RT", rating: "9-250A", poles: "3P", curve: "AC-3", about: "SIRIUS contactor sized by frame across a wide kW range, designed to clip together with matching 3RU or 3RB overload relays into a compact starter."),
      PanelComponent(id: "eaton-dilm", manufacturer: "Eaton", type: "Contactor", model: "DILM", rating: "7-170A", poles: "3P", curve: "AC-3", about: "Eaton DILM contactor range with matching overloads and accessory blocks, common in machine control panels.")
    ]),
    ComponentGroup(id: "drives", name: "Drives & Soft Starters", items: [
      PanelComponent(id: "abb-acs355", manufacturer: "ABB", type: "VFD", model: "ACS355", rating: "0.37-22kW", poles: "3PH", curve: "Machinery drive", about: "Machinery drive for conveyors, mixers and small pumps, built for panel mounting with straightforward parameter setup."),
      PanelComponent(id: "abb-acs580", manufacturer: "ABB", type: "VFD", model: "ACS580", rating: "0.75-250kW", poles: "3PH", curve: "General purpose", about: "General purpose drive covering most building services and industrial motor loads, with a built-in choke that reduces harmonic current without an external reactor."),
      PanelComponent(id: "abb-ach580", manufacturer: "ABB", type: "VFD", model: "ACH580", rating: "0.75-500kW", poles: "3PH", curve: "HVAC drive", about: "HVAC variant tuned for fans and pumps, including firefighter override and PID control for pressure and flow."),
      PanelComponent(id: "abb-acs880", manufacturer: "ABB", type: "VFD", model: "ACS880", rating: "0.55-3200kW", poles: "3PH", curve: "Industrial drive", about: "Industrial drive for demanding applications including regenerative and common DC bus configurations. Confirm cooling and cabinet depth early, since larger frames are substantial."),
      PanelComponent(id: "schneider-atv12", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV12", rating: "0.18-4kW", poles: "1PH/3PH", curve: "Basic machines", about: "Entry-level drive for small machines and single-phase supplies, typically fitted straight onto the machine panel."),
      PanelComponent(id: "schneider-atv320", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV320", rating: "0.18-15kW", poles: "3PH", curve: "Machine drive", about: "Compact machine drive available in book and compact formats, with integrated safety functions such as Safe Torque Off."),
      PanelComponent(id: "schneider-atv340", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV340", rating: "0.75-75kW", poles: "3PH", curve: "High performance", about: "High performance drive for dynamic machine control where fast response and precise speed regulation matter."),
      PanelComponent(id: "schneider-atv630", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV630", rating: "0.75-315kW", poles: "3PH", curve: "Process drive", about: "Process drive for pumps, fans and compressors with energy-saving control and built-in EMC filtering."),
      PanelComponent(id: "siemens-v20", manufacturer: "Siemens", type: "VFD", model: "SINAMICS V20", rating: "0.12-30kW", poles: "1PH/3PH", curve: "Basic drive", about: "Basic drive for simple fan, pump and conveyor duties where a full parameter set would be overkill."),
      PanelComponent(id: "siemens-g120c", manufacturer: "Siemens", type: "VFD", model: "SINAMICS G120C", rating: "0.55-132kW", poles: "3PH", curve: "Compact drive", about: "Compact single-unit drive combining control and power in one housing, saving panel width against the modular G120."),
      PanelComponent(id: "siemens-g120", manufacturer: "Siemens", type: "VFD", model: "SINAMICS G120", rating: "0.55-250kW", poles: "3PH", curve: "Modular drive", about: "Modular drive where control unit and power module are selected separately, so the same power module can serve different control and communication needs."),
      PanelComponent(id: "danfoss-fc51", manufacturer: "Danfoss", type: "VFD", model: "VLT Micro FC 51", rating: "0.18-22kW", poles: "1PH/3PH", curve: "Micro drive", about: "Micro drive for basic speed control on small motors, common in HVAC and simple machinery."),
      PanelComponent(id: "danfoss-fc202", manufacturer: "Danfoss", type: "VFD", model: "VLT AQUA FC 202", rating: "0.25-1400kW", poles: "3PH", curve: "Pump drive", about: "Drive tuned for water and wastewater duty, with pump-specific features such as dry-run detection, pipe fill and cascade control."),
      PanelComponent(id: "danfoss-fc302", manufacturer: "Danfoss", type: "VFD", model: "VLT Automation FC 302", rating: "0.25-800kW", poles: "3PH", curve: "Automation drive", about: "Automation drive for demanding motor control including closed loop and servo-like applications."),
      PanelComponent(id: "delta-ms300", manufacturer: "Delta", type: "VFD", model: "MS300", rating: "0.4-22kW", poles: "3PH", curve: "Compact vector", about: "Compact vector drive giving good torque control in a small footprint, widely used in OEM machine panels."),
      PanelComponent(id: "delta-c2000", manufacturer: "Delta", type: "VFD", model: "C2000+", rating: "0.75-400kW", poles: "3PH", curve: "Heavy duty vector", about: "Heavy duty vector drive for cranes, hoists and high-torque applications where overload capability matters."),
      PanelComponent(id: "eaton-dc1", manufacturer: "Eaton", type: "VFD", model: "PowerXL DC1", rating: "0.37-11kW", poles: "1PH/3PH", curve: "Compact drive", about: "Compact drive for basic speed control, sized for small panels and simple commissioning."),
      PanelComponent(id: "eaton-dg1", manufacturer: "Eaton", type: "VFD", model: "PowerXL DG1", rating: "0.75-250kW", poles: "3PH", curve: "General purpose", about: "General purpose drive with active energy control, used across pump, fan and conveyor duties."),
      PanelComponent(id: "generic-soft-starter", manufacturer: "Generic", type: "Soft Starter", model: "Motor soft starter", rating: "Set kW", poles: "3PH", curve: "Ramp start/stop", about: "Ramps motor voltage up and down to limit inrush current and mechanical shock on belts, couplings and pumps. Confirm whether a bypass is built in, and remember it still needs upstream isolation and overload protection."),
      PanelComponent(id: "abb-psr", manufacturer: "ABB", type: "Soft Starter", model: "PSR", rating: "3-105A", poles: "3PH", curve: "Compact ramp", about: "Compact soft starter for small motors where the aim is simply to take the shock out of starting. No internal bypass, so allow for the heat it dissipates while ramping."),
      PanelComponent(id: "abb-pse", manufacturer: "ABB", type: "Soft Starter", model: "PSE", rating: "18-370A", poles: "3PH", curve: "Bypass + current limit", about: "Soft starter with internal bypass and current limiting, so it stops dissipating heat once the motor is up to speed."),
      PanelComponent(id: "abb-pstx", manufacturer: "ABB", type: "Soft Starter", model: "PSTX", rating: "30-1250A", poles: "3PH", curve: "Advanced, built-in bypass", about: "Advanced soft starter with built-in bypass, torque control and motor protection, suitable for large pumps and compressors where starting stress is a real problem."),
      PanelComponent(id: "schneider-ats01", manufacturer: "Schneider", type: "Soft Starter", model: "Altistart ATS01", rating: "3-32A", poles: "3PH", curve: "Basic ramp", about: "Basic soft starter for small motors, providing a simple voltage ramp without configurable protection."),
      PanelComponent(id: "schneider-ats22", manufacturer: "Schneider", type: "Soft Starter", model: "Altistart ATS22", rating: "17-590A", poles: "3PH", curve: "Torque control", about: "Soft starter with torque control giving smoother starts and stops on pumps, which reduces water hammer in pipework."),
      PanelComponent(id: "schneider-ats480", manufacturer: "Schneider", type: "Soft Starter", model: "Altistart ATS480", rating: "17-1200A", poles: "3PH", curve: "Advanced, bypass", about: "Advanced soft starter with integrated bypass, protection and diagnostics for larger motors and critical duties."),
      PanelComponent(id: "siemens-3rw30", manufacturer: "Siemens", type: "Soft Starter", model: "SIRIUS 3RW30", rating: "3-106A", poles: "3PH", curve: "Standard ramp", about: "Standard soft starter for straightforward ramp starting on general purpose motors."),
      PanelComponent(id: "siemens-3rw52", manufacturer: "Siemens", type: "Soft Starter", model: "SIRIUS 3RW52", rating: "13-370A", poles: "3PH", curve: "Bypass + protection", about: "Soft starter combining bypass and motor protection in one device, reducing the component count in the starter section."),
      PanelComponent(id: "siemens-3rw44", manufacturer: "Siemens", type: "Soft Starter", model: "SIRIUS 3RW44", rating: "29-1214A", poles: "3PH", curve: "High feature", about: "High-feature soft starter for large motors with adjustable torque control and comprehensive protection and diagnostics."),
      PanelComponent(id: "eaton-ds7", manufacturer: "Eaton", type: "Soft Starter", model: "DS7", rating: "9-135A", poles: "3PH", curve: "Integrated bypass", about: "Soft starter with integrated bypass controlling two phases, compact enough to fit where a full three-phase controlled unit would not.")
    ]),
    ComponentGroup(id: "motor-protection", name: "Motor Protection & Starters", items: [
      PanelComponent(id: "abb-ms132", manufacturer: "ABB", type: "MPCB", model: "MS132", rating: "0.1-32A", poles: "3P", curve: "Manual motor starter", about: "Manual motor starter combining short-circuit, overload and manual switching in one device. Dial the current setting to motor full-load amps and check the breaking capacity against the board fault level."),
      PanelComponent(id: "abb-ms165", manufacturer: "ABB", type: "MPCB", model: "MS165", rating: "10-65A", poles: "3P", curve: "Manual motor starter", about: "Larger frame manual motor starter for motors up to roughly 30kW, with the same combined protection and switching function."),
      PanelComponent(id: "schneider-gv2me", manufacturer: "Schneider", type: "MPCB", model: "TeSys GV2ME", rating: "0.1-32A", poles: "3P", curve: "Thermal-magnetic", about: "TeSys manual motor starter with thermal-magnetic protection and a rotary handle, commonly the first device in a compact motor feeder."),
      PanelComponent(id: "schneider-gv3", manufacturer: "Schneider", type: "MPCB", model: "TeSys GV3", rating: "9-65A", poles: "3P", curve: "Thermal-magnetic", about: "Larger TeSys motor circuit breaker for mid-size motors, often paired with a matching contactor to form a compact starter."),
      PanelComponent(id: "siemens-3rv2", manufacturer: "Siemens", type: "MPCB", model: "SIRIUS 3RV2", rating: "0.11-100A", poles: "3P", curve: "Motor protection", about: "SIRIUS motor starter protector that clips directly to matching 3RT contactors, forming a tested combination without extra wiring."),
      PanelComponent(id: "eaton-pkzm0", manufacturer: "Eaton", type: "MPCB", model: "PKZM0", rating: "0.1-32A", poles: "3P", curve: "Motor protective", about: "Motor protective circuit breaker with adjustable overload, used as a compact combined isolator and protection device."),
      PanelComponent(id: "generic-overload", manufacturer: "Generic", type: "Overload Relay", model: "Thermal overload relay", rating: "Set A", poles: "3P", curve: "Motor protection", about: "Thermal overload relay protecting a motor from sustained overcurrent such as a jammed load or lost phase. Set the dial to motor full-load amps and check the trip class suits the starting time."),
      PanelComponent(id: "abb-ta25du", manufacturer: "ABB", type: "Overload Relay", model: "TA25DU", rating: "0.1-32A", poles: "3P", curve: "Thermal, Class 10", about: "Thermal overload relay mounting directly onto matching contactors. Set the dial to motor full-load amps, and reset behaviour should be chosen deliberately since automatic reset on a motor can restart machinery."),
      PanelComponent(id: "abb-ef19", manufacturer: "ABB", type: "Overload Relay", model: "EF19", rating: "0.1-18.9A", poles: "3P", curve: "Electronic, Class 10-30", about: "Electronic overload relay with a wider setting range and selectable trip class, holding accuracy better than a bimetallic relay across ambient changes."),
      PanelComponent(id: "schneider-lrd", manufacturer: "Schneider", type: "Overload Relay", model: "TeSys LRD", rating: "0.1-140A", poles: "3P", curve: "Thermal, Class 10/20", about: "TeSys thermal overload relay clipping onto LC1D contactors, the standard partner in a Schneider motor starter."),
      PanelComponent(id: "schneider-lr9", manufacturer: "Schneider", type: "Overload Relay", model: "TeSys LR9", rating: "0.3-630A", poles: "3P", curve: "Electronic", about: "Electronic overload relay for larger motors, with a wide adjustment range and better protection against phase loss."),
      PanelComponent(id: "siemens-3ru21", manufacturer: "Siemens", type: "Overload Relay", model: "SIRIUS 3RU21", rating: "0.11-100A", poles: "3P", curve: "Thermal, Class 10", about: "Thermal overload relay designed to mount directly on 3RT contactors, forming a compact tested starter combination."),
      PanelComponent(id: "siemens-3rb30", manufacturer: "Siemens", type: "Overload Relay", model: "SIRIUS 3RB30", rating: "0.1-100A", poles: "3P", curve: "Electronic, Class 5-30", about: "Electronic overload relay with selectable trip class from 5 to 30, useful for motors with long run-up times such as large fans."),
      PanelComponent(id: "generic-dol-starter", manufacturer: "Generic", type: "Motor Starter", model: "Direct-on-line starter", rating: "Set kW", poles: "3PH", curve: "Contactor + overload", about: "Direct-on-line starter combining contactor and overload for the simplest motor start. Draws six to eight times full-load current at start, so confirm the supply and any generator can accept that step."),
      PanelComponent(id: "generic-star-delta", manufacturer: "Generic", type: "Motor Starter", model: "Star-delta starter", rating: "Set kW", poles: "3PH", curve: "3 contactors + timer", about: "Star-delta starter reducing starting current by first running the motor in star, then switching to delta. The motor must have all six leads available and the transition timer needs setting to the actual run-up time."),
      PanelComponent(id: "generic-reversing", manufacturer: "Generic", type: "Motor Starter", model: "Reversing starter", rating: "Set kW", poles: "3PH", curve: "Interlocked pair", about: "Reversing starter using two mechanically and electrically interlocked contactors to swap two phases. The interlock is a safety requirement, not an option, since both closing together is a direct phase-to-phase fault.")
    ]),
    ComponentGroup(id: "control-power", name: "Control Power & UPS", items: [
      PanelComponent(id: "generic-transformer", manufacturer: "Generic", type: "Transformer", model: "Control transformer", rating: "Set VA", poles: "1PH", curve: "400/230V", about: "Control transformer stepping the panel supply down to a separate control voltage, typically 230V or 110V, and isolating the control circuit from the power circuit. Size the VA for the inrush of all contactor coils picking up together, not just their holding current."),
      PanelComponent(id: "phoenix-step", manufacturer: "Phoenix", type: "PSU", model: "STEP POWER", rating: "24VDC", poles: "1PH", curve: "0.5-10A basic", about: "Basic 24VDC supply for small control loads such as a handful of relays and sensors, where power reserve features are unnecessary."),
      PanelComponent(id: "phoenix-trio", manufacturer: "Phoenix", type: "PSU", model: "TRIO POWER", rating: "24VDC", poles: "1PH/3PH", curve: "2.5-20A", about: "Mid-range 24VDC supply for typical control panels, with a stable output and compact DIN footprint."),
      PanelComponent(id: "phoenix-quint", manufacturer: "Phoenix", type: "PSU", model: "QUINT POWER", rating: "24VDC", poles: "1PH/3PH", curve: "5-40A, SFB tech", about: "Premium 24VDC supply whose selective fuse breaking technology delivers extra current briefly, so a downstream fault clears its protective device instead of dragging the whole 24V rail down."),
      PanelComponent(id: "abb-cpd", manufacturer: "ABB", type: "PSU", model: "CP-D", rating: "24VDC", poles: "1PH", curve: "0.42-2.5A compact", about: "Compact 24VDC supply for small control tasks where DIN width is at a premium."),
      PanelComponent(id: "abb-cpe", manufacturer: "ABB", type: "PSU", model: "CP-E", rating: "24VDC", poles: "1PH", curve: "0.75-20A", about: "General purpose 24VDC supply covering most panel control loads, with adjustable output voltage to compensate for line drop."),
      PanelComponent(id: "siemens-psu100s", manufacturer: "Siemens", type: "PSU", model: "SITOP PSU100S", rating: "24VDC", poles: "1PH", curve: "2.5-40A", about: "Single-phase SITOP supply for control circuits and SIMATIC controllers, with reserve capacity for short overloads."),
      PanelComponent(id: "siemens-psu8200", manufacturer: "Siemens", type: "PSU", model: "SITOP PSU8200", rating: "24VDC", poles: "3PH", curve: "10-40A", about: "Three-phase SITOP supply for larger 24VDC loads, balancing the draw across all three phases rather than loading one."),
      PanelComponent(id: "meanwell-dr", manufacturer: "Mean Well", type: "PSU", model: "DR series", rating: "24VDC", poles: "1PH", curve: "15-120W", about: "Economical DIN rail supply for light control duties, widely used in OEM panels."),
      PanelComponent(id: "meanwell-hdr", manufacturer: "Mean Well", type: "PSU", model: "HDR series", rating: "24VDC", poles: "1PH", curve: "15-150W ultra slim", about: "Ultra-slim DIN supply for tight enclosures where every millimetre of rail counts."),
      PanelComponent(id: "meanwell-ndr", manufacturer: "Mean Well", type: "PSU", model: "NDR series", rating: "24VDC", poles: "1PH", curve: "75-480W", about: "Higher power DIN supply for panels with substantial 24VDC load such as banks of valves or extensive I/O."),
      PanelComponent(id: "meanwell-tdr", manufacturer: "Mean Well", type: "PSU", model: "TDR series", rating: "24VDC", poles: "3PH", curve: "240-960W", about: "Three-phase DIN supply for heavy 24VDC loads, keeping phase loading balanced on larger installations."),
      PanelComponent(id: "delta-drp", manufacturer: "Delta", type: "PSU", model: "CliQ DRP", rating: "24VDC", poles: "1PH/3PH", curve: "60-960W", about: "CliQ series supply available in single and three-phase versions with good efficiency and a compact footprint."),
      PanelComponent(id: "eaton-psg", manufacturer: "Eaton", type: "PSU", model: "PSG", rating: "24VDC", poles: "1PH", curve: "1.3-20A", about: "General purpose 24VDC supply for control circuits, with models sized from small interface duty upward."),
      PanelComponent(id: "phoenix-quint-ups", manufacturer: "Phoenix", type: "DC-UPS", model: "QUINT UPS-IQ", rating: "24VDC", poles: "DIN", curve: "5-40A + battery", about: "DC uninterruptible supply with intelligent battery management that reports remaining backup time, so control power outlives a brief mains loss."),
      PanelComponent(id: "siemens-ups1600", manufacturer: "Siemens", type: "DC-UPS", model: "SITOP UPS1600", rating: "24VDC", poles: "DIN", curve: "10-40A managed", about: "Managed DC-UPS with configurable buffer time and diagnostics over the controller network, letting a PLC shut down cleanly rather than dying mid-operation."),
      PanelComponent(id: "abb-cpa-ru", manufacturer: "ABB", type: "DC-UPS", model: "CP-A RU", rating: "24VDC", poles: "DIN", curve: "Redundancy + buffer", about: "Redundancy and buffer module decoupling two power supplies so a single failed unit cannot pull down the shared 24V rail."),
      PanelComponent(id: "meanwell-drc", manufacturer: "Mean Well", type: "DC-UPS", model: "DRC series", rating: "24VDC", poles: "DIN", curve: "Charger + backup", about: "DIN rail supply with an integrated battery charger and changeover, a cost-effective route to backed-up control power on smaller panels.")
    ]),
    ComponentGroup(id: "control-automation", name: "Control & Automation", items: [
      PanelComponent(id: "generic-plc", manufacturer: "Generic", type: "PLC", model: "Compact PLC", rating: "24VDC", poles: "DIN", curve: "Digital I/O", about: "Programmable logic controller running the panel control sequence. Count the digital and analogue I/O needed with spare capacity, and confirm the communication protocol before fixing the enclosure layout."),
      PanelComponent(id: "siemens-s71200", manufacturer: "Siemens", type: "PLC", model: "SIMATIC S7-1200", rating: "24VDC", poles: "DIN", curve: "Compact controller", about: "Compact controller for panel automation with expandable digital and analogue I/O. Confirm the I/O count with spare capacity and whether PROFINET or Modbus is required before finalising the layout."),
      PanelComponent(id: "schneider-m221", manufacturer: "Schneider", type: "PLC", model: "Modicon M221", rating: "24VDC", poles: "DIN", curve: "Machine controller", about: "Machine controller for pump, HVAC and small process panels, with built-in Ethernet on most references."),
      PanelComponent(id: "abb-ac500", manufacturer: "ABB", type: "PLC", model: "AC500-eCo", rating: "24VDC", poles: "DIN", curve: "Modular controller", about: "Modular controller that scales from small to large I/O counts, useful where the same panel design must cover several plant sizes."),
      PanelComponent(id: "delta-dvp", manufacturer: "Delta", type: "PLC", model: "DVP series", rating: "24VDC", poles: "DIN", curve: "Compact controller", about: "Cost-effective compact PLC widely used in OEM machine panels with straightforward digital and analogue expansion."),
      PanelComponent(id: "siemens-ktp", manufacturer: "Siemens", type: "HMI", model: "SIMATIC KTP", rating: "24VDC", poles: "Door mount", curve: "4-15 inch touch", about: "Door-mounted touch panel giving the operator status, alarms and setpoints. Cutting the door aperture accurately matters, and the IP rating only holds if the supplied gasket is fitted correctly."),
      PanelComponent(id: "schneider-hmigxu", manufacturer: "Schneider", type: "HMI", model: "Harmony HMIGXU", rating: "24VDC", poles: "Door mount", curve: "3.5-7 inch touch", about: "Compact operator terminal for smaller panels where a full PC-based interface is unnecessary."),
      PanelComponent(id: "pilz-pnoz", manufacturer: "Generic", type: "Safety Relay", model: "PNOZ safety relay", rating: "24VDC", poles: "DIN", curve: "Emergency stop / guard", about: "Safety relay monitoring emergency stops, guard switches and light curtains, providing a redundant and monitored trip path. It must be wired to the documented category and cannot be bypassed by ordinary control logic."),
      PanelComponent(id: "siemens-3sk1", manufacturer: "Siemens", type: "Safety Relay", model: "SIRIUS 3SK1", rating: "24VDC", poles: "DIN", curve: "Safety monitoring", about: "Safety relay for emergency stop and guard monitoring with expandable output modules for larger safety circuits."),
      PanelComponent(id: "generic-relay", manufacturer: "Generic", type: "Relay", model: "Interface relay", rating: "24VDC", poles: "DIN", curve: "1CO/2CO", about: "Interface relay isolating low-power controller outputs from the coils and loads they switch, and converting between control voltages. The slim DIN format keeps a dense I/O interface tidy."),
      PanelComponent(id: "phoenix-plcrsc", manufacturer: "Phoenix", type: "Relay", model: "PLC-RSC interface", rating: "24VDC", poles: "DIN", curve: "6.2mm slim", about: "Slim plug-in interface relay isolating controller outputs from field loads. The pluggable design lets a failed relay be swapped without disturbing terminal wiring."),
      PanelComponent(id: "finder-55", manufacturer: "Generic", type: "Relay", model: "Finder 55 series", rating: "24-230V", poles: "DIN", curve: "2CO/3CO", about: "General purpose plug-in relay with a socket base, used for interposing and simple control logic in panels of every size."),
      PanelComponent(id: "generic-timer", manufacturer: "Generic", type: "Timer", model: "Time relay", rating: "24-230V", poles: "DIN", curve: "On/off delay", about: "Time relay providing on-delay, off-delay or cyclic switching for sequencing, pump alternation and star-delta transitions."),
      PanelComponent(id: "finder-80", manufacturer: "Generic", type: "Timer", model: "Finder 80 multifunction", rating: "12-240V", poles: "DIN", curve: "Multifunction", about: "Multifunction timer covering on-delay, off-delay, interval and cyclic modes in one part, which cuts down on stocked variants."),
      PanelComponent(id: "abb-cm-mps", manufacturer: "ABB", type: "Monitoring Relay", model: "CM-MPS", rating: "3x400V", poles: "DIN", curve: "Phase failure / sequence", about: "Three-phase monitoring relay detecting phase loss, wrong phase sequence, under and overvoltage. It is what stops a motor running single-phased after an upstream fuse clears one leg."),
      PanelComponent(id: "siemens-3ug4", manufacturer: "Siemens", type: "Monitoring Relay", model: "SIRIUS 3UG4", rating: "3x400V", poles: "DIN", curve: "Voltage / phase monitor", about: "Line monitoring relay for phase sequence, asymmetry and voltage window, commonly interlocked into the start circuit of motor panels.")
    ]),
    ComponentGroup(id: "metering", name: "Metering & Monitoring", items: [
      PanelComponent(id: "generic-meter", manufacturer: "Generic", type: "Meter", model: "Digital meter", rating: "230/400V", poles: "3PH", curve: "Panel mount", about: "Panel-mounted digital meter showing voltage, current and basic energy values on the board door. Confirm whether it measures directly or needs current transformers."),
      PanelComponent(id: "schneider-iem3000", manufacturer: "Schneider", type: "Meter", model: "Acti9 iEM3000", rating: "230/400V", poles: "3PH", curve: "DIN, Modbus", about: "DIN rail energy meter for sub-billing and consumption monitoring, available in direct-connect and CT versions with Modbus output."),
      PanelComponent(id: "siemens-pac3200", manufacturer: "Siemens", type: "Meter", model: "SENTRON PAC3200", rating: "230/400V", poles: "3PH", curve: "Door mount", about: "Door-mounted multifunction meter showing the full set of electrical values with Modbus or PROFINET reporting."),
      PanelComponent(id: "carlogavazzi-em21", manufacturer: "Generic", type: "Meter", model: "Carlo Gavazzi EM21", rating: "230/400V", poles: "3PH", curve: "DIN, Modbus", about: "Compact DIN rail energy meter widely used for sub-metering individual feeders in tenant and process installations."),
      PanelComponent(id: "generic-power-analyzer", manufacturer: "Generic", type: "Power Analyzer", model: "Power quality analyzer", rating: "230/400V", poles: "3PH", curve: "Modbus", about: "Power quality analyser recording harmonics, power factor, demand and event data, usually reporting over Modbus to a monitoring system. Specify where energy billing or harmonic problems need evidence."),
      PanelComponent(id: "schneider-pm2000", manufacturer: "Schneider", type: "Power Analyzer", model: "PowerLogic PM2000", rating: "230/400V", poles: "3PH", curve: "Panel mount", about: "Panel-mounted power meter measuring energy, demand and basic power quality, suited to tenant metering and energy management."),
      PanelComponent(id: "siemens-pac4200", manufacturer: "Siemens", type: "Power Analyzer", model: "SENTRON PAC4200", rating: "230/400V", poles: "3PH", curve: "Harmonics + logging", about: "Advanced meter adding harmonic analysis and data logging, used where power quality has to be proven rather than assumed."),
      PanelComponent(id: "abb-m2m", manufacturer: "ABB", type: "Power Analyzer", model: "M2M network analyzer", rating: "230/400V", poles: "3PH", curve: "Modbus", about: "Network analyser recording power quality and harmonic content, typically fitted where drives and non-linear loads dominate."),
      PanelComponent(id: "generic-ct", manufacturer: "Generic", type: "Current Transformer", model: "Split or solid core CT", rating: "50-5000A", poles: "1PH each", curve: "Class 0.5-1", about: "Current transformer scaling feeder current down to a meter input, usually 5A or 1A. Match the ratio and accuracy class to the meter, and never leave the secondary open circuit while primary current flows."),
      PanelComponent(id: "generic-test-block", manufacturer: "Generic", type: "Test Block", model: "CT test block", rating: "5A", poles: "Panel mount", curve: "Shorting type", about: "Test block allowing meters and protection relays to be tested or replaced without breaking the CT secondary, which it shorts automatically as the plug is withdrawn.")
    ]),
    ComponentGroup(id: "power-quality", name: "Power Factor & Quality", items: [
      PanelComponent(id: "abb-rvt", manufacturer: "ABB", type: "PFC Controller", model: "RVT controller", rating: "230/400V", poles: "Door mount", curve: "6-12 stages", about: "Power factor controller switching capacitor stages to hold the target power factor and avoid reactive energy charges. Set the target and the C/k ratio to suit the CT and the smallest stage."),
      PanelComponent(id: "schneider-varlogic", manufacturer: "Schneider", type: "PFC Controller", model: "Varlogic NR", rating: "230/400V", poles: "Door mount", curve: "6-12 stages", about: "Power factor controller with stage health monitoring, which matters because a failed capacitor stage otherwise goes unnoticed until the bill rises."),
      PanelComponent(id: "abb-clmd", manufacturer: "ABB", type: "Capacitor", model: "CLMD capacitor", rating: "Set kVAr", poles: "3PH", curve: "Dry type", about: "Dry-type power capacitor forming the stages of a correction bank. Capacitors need discharge resistors and adequate ventilation, and they age faster in hot or harmonic-rich environments."),
      PanelComponent(id: "generic-detuned-reactor", manufacturer: "Generic", type: "Reactor", model: "Detuned reactor", rating: "Set kVAr", poles: "3PH", curve: "7% or 14%", about: "Detuned reactor placed in series with capacitor stages to shift the resonant frequency away from prevailing harmonics. Required wherever significant drive or UPS load shares the installation."),
      PanelComponent(id: "generic-line-reactor", manufacturer: "Generic", type: "Reactor", model: "Line/load reactor", rating: "Set A", poles: "3PH", curve: "2-5% impedance", about: "Line or load reactor fitted with a drive to reduce current distortion, protect the drive input and limit voltage stress on long motor cables."),
      PanelComponent(id: "generic-active-filter", manufacturer: "Generic", type: "Harmonic Filter", model: "Active harmonic filter", rating: "30-300A", poles: "3PH", curve: "Real time correction", about: "Active filter injecting counter-current to cancel harmonics in real time. Specify from a measured harmonic survey rather than assumption, since sizing depends on the actual spectrum.")
    ]),
    ComponentGroup(id: "terminals", name: "Terminals & Wiring", items: [
      PanelComponent(id: "phoenix-terminal", manufacturer: "Phoenix", type: "Terminal Block", model: "UK series", rating: "2.5-35mm²", poles: "DIN", curve: "cm rail", about: "Screw-clamp terminal block for field wiring connections. Grouping terminals by function and numbering them consistently is what makes later fault finding fast."),
      PanelComponent(id: "phoenix-ut", manufacturer: "Phoenix", type: "Terminal Block", model: "CLIPLINE UT", rating: "0.14-95mm2", poles: "DIN", curve: "Screw clamp", about: "Screw clamp terminal range covering signal through power cross-sections in a consistent form, with matching bridges, markers and test accessories."),
      PanelComponent(id: "phoenix-pt", manufacturer: "Phoenix", type: "Terminal Block", model: "CLIPLINE PT", rating: "0.14-16mm2", poles: "DIN", curve: "Push-in spring", about: "Push-in spring terminal that accepts a ferruled conductor without a tool, cutting wiring time and removing the retorquing that screw terminals need."),
      PanelComponent(id: "wago-2002", manufacturer: "Generic", type: "Terminal Block", model: "WAGO TOPJOB S", rating: "0.25-16mm2", poles: "DIN", curve: "Push-in CAGE CLAMP", about: "Spring clamp terminal that holds tension regardless of vibration or thermal cycling, which is why it is common on machinery and transport panels."),
      PanelComponent(id: "weidmuller-a", manufacturer: "Generic", type: "Terminal Block", model: "Weidmuller A-series", rating: "0.14-95mm2", poles: "DIN", curve: "Push-in", about: "Push-in terminal system with a uniform accessory set across cross-sections, keeping cross-bridging and marking consistent through the panel."),
      PanelComponent(id: "phoenix-ptfix", manufacturer: "Phoenix", type: "Distribution Block", model: "PTFIX", rating: "1.5-6mm2", poles: "DIN or adhesive", curve: "Potential distributor", about: "Potential distribution block splitting one supply into many outgoing points, tidying up the 24VDC and earth distribution that otherwise turns into daisy-chained terminals."),
      PanelComponent(id: "generic-power-distribution-block", manufacturer: "Generic", type: "Distribution Block", model: "Power distribution block", rating: "125-800A", poles: "1P/3P/4P", curve: "Insulated body", about: "Insulated distribution block taking one large incoming cable and splitting it to several outgoing ways without a full busbar system."),
      PanelComponent(id: "generic-ferrule", manufacturer: "Generic", type: "Ferrule", model: "Bootlace ferrule", rating: "0.5-35mm2", poles: "Per conductor", curve: "Crimped", about: "Bootlace ferrule terminating a stranded conductor so no strand escapes the terminal. Use the correct crimp tool and die, since an under-crimped ferrule becomes a hot joint."),
      PanelComponent(id: "generic-lug", manufacturer: "Generic", type: "Cable Lug", model: "Compression lug", rating: "10-630mm2", poles: "Per conductor", curve: "Crimped", about: "Compression lug terminating large cables onto busbars and breaker pads. Match lug, die and tool from the same system, and confirm bolt torque against the manufacturer figure."),
      PanelComponent(id: "generic-marker", manufacturer: "Generic", type: "Wire Marker", model: "Wire and terminal markers", rating: "All sizes", poles: "Per conductor", curve: "Printed", about: "Printed markers identifying conductors and terminals to the drawing. Consistent numbering is the single thing that most reduces fault-finding time years later."),
      PanelComponent(id: "generic-trunking", manufacturer: "Generic", type: "Trunking", model: "Wiring duct", rating: "Set cm", poles: "PVC", curve: "Slotted", about: "Slotted wiring duct routing and containing panel wiring. Leave real spare capacity, since ducts filled to the brim make later modifications painful and trap heat."),
      PanelComponent(id: "generic-cable-gland", manufacturer: "Generic", type: "Cable Gland", model: "Cable gland", rating: "Set size", poles: "M thread", curve: "IP rated", about: "Cable gland sealing a cable where it enters the enclosure, maintaining the IP rating and providing strain relief. Metal glands additionally terminate cable armour or screen."),
      PanelComponent(id: "generic-din", manufacturer: "Generic", type: "DIN Rail", model: "35mm rail", rating: "1m", poles: "DIN", curve: "Cut to cm", about: "Standard 35mm DIN rail carrying modular devices. Plan rail heights and spacing around wiring duct so devices remain accessible after wiring.")
    ]),
    ComponentGroup(id: "busbars", name: "Busbars & Earthing", items: [
      PanelComponent(id: "generic-busbar-250", manufacturer: "Generic", type: "Busbar", model: "Copper busbar", rating: "250A", poles: "3P+N", curve: "cm/m sizing", about: "Copper busbar system rated around 250A for distributing current across a board section, keeping outgoing connections short and consistent."),
      PanelComponent(id: "generic-busbar-630", manufacturer: "Generic", type: "Busbar", model: "Copper busbar", rating: "630A", poles: "3P+N", curve: "cm/m sizing", about: "Higher rated busbar for main distribution sections, where cable connections to every outgoing device would be impractical."),
      PanelComponent(id: "rittal-riline", manufacturer: "Rittal", type: "Busbar System", model: "RiLine busbar system", rating: "100-1600A", poles: "3P/4P", curve: "Component adaptor", about: "Busbar system with component adaptors that clip devices directly onto the bars, cutting internal cabling and giving a repeatable, tested arrangement."),
      PanelComponent(id: "generic-copper-bar", manufacturer: "Generic", type: "Copper Bar", model: "Copper bar", rating: "Set cm", poles: "Flat bar", curve: "Busbar", about: "Copper bar carrying current between sections and devices inside the board. Size it for continuous current and short-circuit withstand, and check the support spacing for the fault level."),
      PanelComponent(id: "generic-flexible-busbar", manufacturer: "Generic", type: "Busbar", model: "Flexible braided busbar", rating: "Set A", poles: "Per phase", curve: "Laminated", about: "Flexible laminated connector between busbar and device, absorbing vibration and thermal movement and easing awkward connection geometry."),
      PanelComponent(id: "generic-busbar-support", manufacturer: "Generic", type: "Busbar Support", model: "Busbar support block", rating: "Set A", poles: "3P/4P", curve: "Insulated", about: "Insulated busbar support holding bars at a fixed spacing. Support spacing is a short-circuit withstand question, not a tidiness one: bars must not deflect together under fault forces."),
      PanelComponent(id: "generic-earth-bar", manufacturer: "Generic", type: "Earth Bar", model: "PE bar", rating: "Set length", poles: "PE", curve: "Copper/brass", about: "Protective earth bar giving every circuit a common bonding point. It must be sized for the largest fault current and clearly labelled and accessible."),
      PanelComponent(id: "generic-neutral-bar", manufacturer: "Generic", type: "Neutral Bar", model: "N bar", rating: "Set length", poles: "N", curve: "Copper/brass", about: "Neutral bar collecting circuit neutrals. Keep neutrals grouped with their own circuits so that RCD protection and later fault finding both work predictably."),
      PanelComponent(id: "generic-earth-braid", manufacturer: "Generic", type: "Earth Bonding", model: "Earth bonding braid", rating: "6-25mm2", poles: "Per door", curve: "Flexible", about: "Flexible bonding braid earthing doors and hinged plates. Doors carrying any electrical device must be bonded, and paint has to be removed at the fixing point for the bond to be real.")
    ]),
    ComponentGroup(id: "enclosure", name: "Enclosure & Climate", items: [
      PanelComponent(id: "rittal-ae", manufacturer: "Rittal", type: "Enclosure", model: "AE compact enclosure", rating: "IP66", poles: "Wall mount", curve: "Sheet steel", about: "Compact wall-mounting enclosure for smaller boards and control panels. Confirm the IP rating survives every cut-out and gland you add to it."),
      PanelComponent(id: "rittal-vx25", manufacturer: "Rittal", type: "Enclosure", model: "VX25 bayed enclosure", rating: "IP55", poles: "Floor standing", curve: "Frame system", about: "Bayable floor-standing frame system for large boards, allowing sections to be joined into a lineup with continuous busbar and shared cable zones."),
      PanelComponent(id: "generic-fan", manufacturer: "Generic", type: "Fan", model: "Panel fan", rating: "230V", poles: "Filter fan", curve: "Airflow", about: "Filter fan drawing cooler outside air through the enclosure to remove heat from drives, transformers and breakers. It needs a matching exit filter, and the filter mats need a cleaning interval in the maintenance plan."),
      PanelComponent(id: "rittal-sk-fan", manufacturer: "Rittal", type: "Fan", model: "SK filter fan", rating: "230V", poles: "Door or side", curve: "Filtered airflow", about: "Filter fan with matched exit filter for forced ventilation. Size airflow from the calculated heat load and remember it can only cool to ambient, never below it."),
      PanelComponent(id: "rittal-bluee", manufacturer: "Rittal", type: "Cooling Unit", model: "Blue e cooling unit", rating: "230/400V", poles: "Wall or roof", curve: "Active cooling", about: "Active cooling unit refrigerating the enclosure below ambient, needed where drives and transformers exceed what filtered ventilation can remove. It needs condensate management and a sealed enclosure to work correctly."),
      PanelComponent(id: "generic-heater", manufacturer: "Generic", type: "Heater", model: "Panel heater", rating: "230V", poles: "DIN", curve: "PTC element", about: "Panel heater preventing condensation in cold or outdoor enclosures. Condensation, not cold, is what damages electronics, so pair it with a hygrostat or thermostat."),
      PanelComponent(id: "generic-thermostat", manufacturer: "Generic", type: "Thermostat", model: "Panel thermostat", rating: "230V", poles: "DIN", curve: "NO/NC", about: "Panel thermostat switching a fan or heater at a set temperature. Use a normally-closed unit for heating and a normally-open unit for cooling."),
      PanelComponent(id: "generic-hygrostat", manufacturer: "Generic", type: "Hygrostat", model: "Panel hygrostat", rating: "230V", poles: "DIN", curve: "Humidity control", about: "Hygrostat switching a heater on humidity rather than temperature, which is the more reliable way to keep an outdoor enclosure dry."),
      PanelComponent(id: "generic-panel-light", manufacturer: "Generic", type: "Panel Light", model: "LED enclosure light", rating: "230V", poles: "Interior", curve: "Door switch", about: "Interior LED light, usually with a door switch, so maintenance inside a deep board does not depend on a hand torch."),
      PanelComponent(id: "generic-panel-socket", manufacturer: "Generic", type: "Socket", model: "Service socket outlet", rating: "230V", poles: "DIN or panel", curve: "16A", about: "Service socket inside the enclosure for test equipment and tools. It should be fed from its own protected circuit with RCD protection."),
      PanelComponent(id: "generic-door-interlock", manufacturer: "Generic", type: "Door Interlock", model: "Door interlock", rating: "Set A", poles: "Handle", curve: "Mechanical", about: "Mechanical door interlock preventing the enclosure being opened while the main switch is closed, with a defeat facility for authorised testing.")
    ]),
    ComponentGroup(id: "door-devices", name: "Door & Operator Devices", items: [
      PanelComponent(id: "generic-estop", manufacturer: "Generic", type: "Emergency Stop", model: "Emergency stop mushroom", rating: "22/40mm", poles: "NC contacts", curve: "Twist release", about: "Latching emergency stop with positively-driven normally-closed contacts. It must break the control path directly, not merely request a stop from a controller."),
      PanelComponent(id: "generic-push-button", manufacturer: "Generic", type: "Push Button", model: "Push button", rating: "22mm", poles: "NO/NC", curve: "Panel door", about: "22mm door-mounted push button for start, stop and reset commands. Contact blocks are ordered separately, so confirm how many NO and NC contacts each function needs."),
      PanelComponent(id: "schneider-xb4", manufacturer: "Schneider", type: "Push Button", model: "Harmony XB4", rating: "22mm", poles: "NO/NC blocks", curve: "Metal bezel", about: "Metal-bezel control station range for doors, with a wide selection of heads and contact blocks that share one mounting cut-out."),
      PanelComponent(id: "siemens-3su1", manufacturer: "Siemens", type: "Push Button", model: "SIRIUS ACT 3SU1", rating: "22mm", poles: "NO/NC blocks", curve: "Plastic or metal", about: "Modular door control range with plastic and metal versions, and connection options from screw terminals to an integrated bus module."),
      PanelComponent(id: "generic-selector", manufacturer: "Generic", type: "Selector Switch", model: "Selector switch", rating: "22mm", poles: "2/3 position", curve: "Panel door", about: "Panel door selector switch giving a positive two or three position choice such as hand-off-auto. Confirm the contact arrangement matches the control logic before drilling the door."),
      PanelComponent(id: "generic-indicator", manufacturer: "Generic", type: "Indicator Light", model: "Pilot light", rating: "24/230V", poles: "22mm", curve: "LED", about: "Pilot light showing run, trip or supply-healthy status on the door. LED versions draw far less current and last longer than filament equivalents."),
      PanelComponent(id: "generic-ammeter", manufacturer: "Generic", type: "Ammeter", model: "Analogue ammeter", rating: "Via CT", poles: "1PH each", curve: "Moving iron", about: "Analogue ammeter giving an at-a-glance load indication on the door. Still favoured on motor panels because a swinging needle shows a struggling load better than a digital readout."),
      PanelComponent(id: "generic-selector-ammeter", manufacturer: "Generic", type: "Selector Switch", model: "Ammeter selector switch", rating: "Via CT", poles: "3PH+off", curve: "Shorting type", about: "Ammeter selector letting one meter read each phase in turn. It must be the CT-shorting type so the transformer secondary is never opened while switching.")
    ])
  ]
}

struct PanelComponent: Identifiable {
  let id: String
  let manufacturer: String
  let type: String
  let model: String
  let rating: String
  let poles: String
  let curve: String
  var sourceID: String = ""

  /// What this specific part does and what to check when specifying it.
  /// Empty for user-created components, which fall back to the generic
  /// per-type text in `ComponentIcon.description(for:)`.
  var about: String = ""

  var imageStorageID: String {
    sourceID.isEmpty ? id : sourceID
  }

  var imageLookupIDs: [String] {
    Array(NSOrderedSet(array: [id, imageStorageID])) as? [String] ?? [id, imageStorageID]
  }

  var displayName: String {
    [manufacturer, type, model]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " ")
  }

  var ratingLabel: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.localizedCaseInsensitiveContains("set a") { return "Set A" }
    return trimmed
  }

  var detailLine: String {
    [model, poles, curve]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " • ")
  }

  var searchText: String {
    "\(manufacturer) \(type) \(model) \(rating) \(poles) \(curve)"
  }
}

struct BoardDraft: Identifiable {
  let id: String
  var number: String
  var group: String
  var name: String
  var customer: String
  var company: String = ""
  var project: String
  var type: String
  var subtype: String = BoardSubtypeCatalog.defaultSubtype
  var manufacturer: String = "Generic"
  var ampere: String
  var cabinetCount: String
  var buildFormat: String = "Panels"
  var dateOut: Date = Date()
  var dueDate: Date? = nil
  var finishDate: Date? = nil
  var finishTimeHours: String = ""
  var mainBreakerType: String
  var mainBreakerModel: String = ""
  var mainBreakerAmpere: String
  var componentTypes: [String]
  var color: Color = Color(hex: 0x5E78FF)

  /// Image-store tokens rather than decoded images — see [ProjectItem].
  var coverToken: String? = nil
  var photoTokens: [String] = []
  var schemeAttachments: [SchemeAttachment] = []
  var completedChecklistItems: Set<String> = []
  var personalChecklistItems: [PersonalChecklistItem] = []
  /// Completed checklist item IDs per cabinet, index 0 = cabinet 1. Each cabinet
  /// is built and tracked on its own; the board's completion averages them.
  var cabinetChecklists: [Set<String>] = []

  var coverImage: UIImage? {
    get { ImageStore.shared.image(for: coverToken) }
    set { coverToken = ImageStore.shared.store(newValue) }
  }

  /// Use in scrolling views instead of [coverImage].
  var coverThumbnail: UIImage? {
    ImageStore.shared.thumbnail(for: coverToken)
  }

  var photoCount: Int { photoTokens.count }

  /// Every token this board owns, for orphan cleanup.
  var imageTokens: [String] {
    ([coverToken] + photoTokens + schemeAttachments.map(\.imageToken)).compactMap { $0 }
  }

  var searchText: String {
    "\(number) \(group) \(name) \(customer) \(company) \(project) \(type) \(subtype) \(manufacturer) \(ampere) \(cabinetCount) \(buildFormat) \(DateDisplay.short.string(from: dateOut)) \(dueDate.map { DateDisplay.due.string(from: $0) } ?? "") \(finishDate.map { DateDisplay.short.string(from: $0) } ?? "") \(mainBreakerType) \(mainBreakerModel) \(mainBreakerAmpere) \(componentTypes.joined(separator: " "))"
  }

  var displayType: String {
    let cleanSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    guard BoardSubtypeCatalog.isVisible(cleanSubtype) else { return type }
    return "\(type) • \(cleanSubtype)"
  }

  var cabinetCountValue: Int { max(Int(cabinetCount) ?? 1, 1) }

  /// Per-cabinet checklists sized to the current cabinet count. Migrates a legacy
  /// single shared checklist into cabinet 1 so existing boards keep their progress.
  var normalizedCabinetChecklists: [Set<String>] {
    var lists = cabinetChecklists
    if lists.isEmpty && !completedChecklistItems.isEmpty {
      lists = [completedChecklistItems]
    }
    let n = cabinetCountValue
    if lists.count < n {
      lists.append(contentsOf: Array(repeating: Set<String>(), count: n - lists.count))
    } else if lists.count > n {
      lists = Array(lists.prefix(n))
    }
    return lists
  }

  var persistenceSignature: String {
    let coverSignature = ImageStore.shared.signature(for: coverToken)
    let photoSignature = photoTokens.joined(separator: "|")
    let schemeSignature = schemeAttachments.map(\.persistenceSignature).joined(separator: "|")
    return [
      id, number, group, name, customer, project, type, subtype, manufacturer,
      company,
      ampere, cabinetCount, buildFormat, "\(dateOut.timeIntervalSince1970)",
      "\(dueDate?.timeIntervalSince1970 ?? 0)",
      "\(finishDate?.timeIntervalSince1970 ?? 0)", finishTimeHours,
      mainBreakerType, mainBreakerModel, mainBreakerAmpere,
      componentTypes.joined(separator: ","), "\(color.archiveHex)",
      coverSignature, photoSignature,
      schemeSignature,
      normalizedCabinetChecklists.map { $0.sorted().joined(separator: ",") }.joined(separator: ";"),
      personalChecklistItems.map { "\($0.id):\($0.title):\($0.isDone)" }.joined(separator: ",")
    ].joined(separator: "||")
  }

  var mainBreakerLabel: String {
    [(mainBreakerType == "Main Breaker" ? nil : mainBreakerType), mainBreakerModel, mainBreakerAmpere]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
  }

  /// Board completion is the average of each cabinet's checklist completion.
  var completion: Int {
    let checklist = ChecklistTemplate.items(for: cabinetCount)
    let totalWeight = max(checklist.map(\.weight).reduce(0, +), 1)
    let lists = normalizedCabinetChecklists
    guard !lists.isEmpty else { return 0 }
    let averageFraction = lists.map { checked in
      let done = checklist.filter { checked.contains($0.id) }.map(\.weight).reduce(0, +)
      return Double(done) / Double(totalWeight)
    }.reduce(0, +) / Double(lists.count)
    return Int((averageFraction * 100).rounded())
  }

  var isCompleted: Bool {
    completion >= 100
  }

  var statusTitle: String {
    isCompleted ? "Finished" : "In Progress"
  }
}

struct PersonalChecklistItem: Identifiable, Hashable {
  let id: String
  var title: String
  var isDone: Bool

  init(id: String = "personal-\(UUID().uuidString)", title: String, isDone: Bool = false) {
    self.id = id
    self.title = title
    self.isDone = isDone
  }
}

enum EquipmentCompany {
  static let all = ["ABB", "Schneider", "Siemens", "Eaton", "Legrand", "Hager", "Mean Well", "Phoenix", "Generic"]
}

enum BoardSubtypeCatalog {
  static let defaultSubtype = "No subtype"

  static func isVisible(_ subtype: String) -> Bool {
    let cleanSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    return !cleanSubtype.isEmpty && cleanSubtype != defaultSubtype && cleanSubtype != "General"
  }

  static func options(for boardType: String) -> [String] {
    let lower = boardType.lowercased()
    var options = [defaultSubtype, "Control", "EV Charger", "Metering", "Automation", "Pump Control", "HVAC Control", "Generator Control", "Solar", "UPS", "Temporary Site"]
    if lower.contains("ev") || lower.contains("charging") {
      options = [defaultSubtype, "EV Charger", "Load Management", "Parking Level", "Fast Charger", "Metering"]
    } else if lower.contains("mcc") || lower.contains("motor") || lower.contains("pump") || lower.contains("hvac") {
      options = [defaultSubtype, "Control", "Pump Control", "HVAC Control", "VFD", "Soft Starter", "Automation"]
    } else if lower.contains("lighting") {
      options = [defaultSubtype, "Indoor Lighting", "Outdoor Lighting", "Emergency Lighting", "Timer Control", "Astronomical Clock"]
    } else if lower.contains("ats") || lower.contains("generator") {
      options = [defaultSubtype, "Generator Control", "ATS Control", "Synchronization", "Bypass"]
    }
    return Array(NSOrderedSet(array: options)) as? [String] ?? options
  }
}

enum EquipmentTypeCatalog {
  static let all = [
    "MCB", "MCCB", "ACB", "RCD/RCCB", "RCBO", "Contactor", "Overload Relay",
    "VFD", "Soft Starter", "PSU", "Transformer", "Busbar", "Terminal Block",
    "SPD", "Fuse", "Fuse Holder", "Isolator", "Changeover Switch", "Meter",
    "Power Analyzer", "PLC", "Relay", "Timer", "Selector Switch", "Push Button",
    "Indicator Light", "Fan", "Thermostat", "Door Interlock", "Cable Gland",
    "DIN Rail", "Trunking", "Copper Bar", "Earth Bar", "Neutral Bar"
  ]
}

enum AmpereRating {
  static let all = [
    "0.5A", "1A", "2A", "3A", "4A", "6A", "10A", "13A", "16A", "20A",
    "25A", "32A", "40A", "50A", "63A", "80A", "100A", "125A", "160A",
    "200A", "225A", "250A", "315A", "400A", "500A", "630A", "800A",
    "1000A", "1250A", "1600A", "2000A", "2500A", "3200A", "4000A",
    "5000A", "6300A"
  ]
}

enum PoleRating {
  static let all = ["1P", "1P+N", "2P", "3P", "3P+N", "4P", "3PH", "1PH", "DIN"]
}
