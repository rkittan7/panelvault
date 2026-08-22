// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import UIKit

struct PanelVaultSnapshot: Codable {
  let projects: [ProjectRecord]
  let boards: [BoardRecord]
  let customers: [CustomerRecord]
  let companies: [CompanyRecord]?
  let manufacturers: [ManufacturerRecord]?

  init(projects: [ProjectItem], boards: [BoardDraft], customers: [CustomerItem], companies: [ContractorCompany], manufacturers: [ManufacturerItem]) {
    self.projects = projects.map(ProjectRecord.init(project:))
    self.boards = boards.map(BoardRecord.init(board:))
    self.customers = customers.map(CustomerRecord.init(customer:))
    self.companies = companies.map(CompanyRecord.init(company:))
    self.manufacturers = manufacturers.map(ManufacturerRecord.init(manufacturer:))
  }

  func encoded() -> String {
    guard let data = try? JSONEncoder().encode(self) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func decode(_ rawValue: String) -> PanelVaultSnapshot? {
    guard let data = rawValue.data(using: .utf8), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(PanelVaultSnapshot.self, from: data)
  }
}

/// Disk-backed image storage, addressed by short filename tokens.
///
/// PanelVault used to base64-encode every photo into the snapshot JSON that
/// lived in UserDefaults. Because UserDefaults is read wholly into memory at
/// launch and rewritten as one plist, that capped the archive at a handful of
/// photos and made saving one text edit rewrite every image in the vault.
///
/// Images now live as individual files in Application Support and records hold
/// only a `<uuid>.jpg` token, so the archive is bounded by disk space rather
/// than by UserDefaults, and memory is bounded by the caches below no matter
/// how many photos exist.
final class ImageStore {
  static let shared = ImageStore()

  /// Long-side cap for the stored original, so the vault never keeps 48MP
  /// camera originals. Applied once, on import.
  static let maximumDimension: CGFloat = 2200

  /// Long side of the list thumbnail. Rows decode this instead of the original.
  static let thumbnailDimension: CGFloat = 400

  private let fullCache = NSCache<NSString, UIImage>()
  private let thumbnailCache = NSCache<NSString, UIImage>()

  /// Reverse map from a live UIImage back to its token, so a view re-assigning
  /// the same image through a binding does not write a duplicate file.
  ///
  /// Weak keys matter: an NSCache retains its keys, which would pin every image
  /// ever stored in memory and defeat the point of moving them to disk. Here the
  /// entry disappears as soon as the caller stops holding the image.
  private let tokenForImage = NSMapTable<UIImage, NSString>.weakToStrongObjects()

  /// NSCache is thread-safe; NSMapTable is not, and `store` runs both on the
  /// main actor and on import tasks.
  private let tokenLock = NSLock()

  private let fileManager = FileManager.default

  private init() {
    // Bounded by bytes, not just count: 400 thumbnails held as decoded bitmaps
    // would be hundreds of megabytes.
    fullCache.countLimit = 24
    fullCache.totalCostLimit = 64 * 1024 * 1024
    thumbnailCache.countLimit = 400
    thumbnailCache.totalCostLimit = 32 * 1024 * 1024
  }

  private(set) lazy var directory: URL = {
    let base = fileManager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    let folder = base.appendingPathComponent("PanelVault/Images", isDirectory: true)
    try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }()

  // MARK: - Writing

  /// Writes `image` to disk and returns its token.
  ///
  /// Synchronous on purpose: a photo the user just imported has to survive the
  /// app being killed a moment later.
  func store(_ image: UIImage?) -> String? {
    guard let image else { return nil }
    if let known = knownToken(for: image) { return known }

    let prepared = ImageStore.prepared(image)
    let usePNG = prepared.hasTransparency
    guard let data = usePNG
      ? prepared.pngData()
      : prepared.jpegData(compressionQuality: 0.72) else { return nil }

    let token = "\(UUID().uuidString).\(usePNG ? "png" : "jpg")"
    do {
      try data.write(to: url(for: token), options: .atomic)
    } catch {
      return nil
    }

    remember(prepared, as: token)
    if prepared !== image {
      associate(image, with: token)
    }
    writeThumbnail(for: prepared, token: token)
    return token
  }

  func store(_ images: [UIImage]) -> [String] {
    images.compactMap { store($0) }
  }

  /// A freshly imported photo: the prepared image for immediate display, and
  /// the token it was stored under.
  ///
  /// The token is returned rather than looked up later because the reverse cache
  /// is an NSCache and may evict — a lookup miss would silently drop the photo
  /// even though its file was written.
  struct Imported {
    let image: UIImage
    let token: String
  }

  /// Decodes, downscales and writes a freshly picked photo off the main actor.
  ///
  /// Every photo import goes through here, so JPEG encoding never runs on the
  /// main thread and the file is on disk before the UI ever shows it.
  static func imported(from data: Data) async -> Imported? {
    await Task.detached(priority: .userInitiated) {
      guard let decoded = UIImage(data: data) else { return nil as Imported? }
      let prepared = ImageStore.prepared(decoded)
      guard let token = ImageStore.shared.store(prepared) else {
        return nil as Imported?
      }
      return Imported(image: prepared, token: token)
    }.value
  }

  /// Accepts either a current token or a legacy base64 blob from an older
  /// snapshot, so existing archives migrate on first load without data loss.
  func adopt(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if ImageStore.isToken(raw) { return raw }
    guard let data = Data(base64Encoded: raw),
          let image = UIImage(data: data) else { return nil }
    return store(image)
  }

  func adopt(_ raws: [String]?) -> [String] {
    raws?.compactMap { adopt($0) } ?? []
  }

  // MARK: - Reading

  func image(for token: String?) -> UIImage? {
    // Validating the token also keeps a corrupted index from turning into a
    // path traversal out of the images directory.
    guard let token, ImageStore.isToken(token) else { return nil }
    if let cached = fullCache.object(forKey: token as NSString) { return cached }

    guard let data = try? Data(contentsOf: url(for: token)),
          let image = UIImage(data: data) else { return nil }

    remember(image, as: token)
    return image
  }

  /// Small representation for list rows and grids. Falls back to generating the
  /// thumbnail from the original when it is missing.
  func thumbnail(for token: String?) -> UIImage? {
    guard let token, ImageStore.isToken(token) else { return nil }
    if let cached = thumbnailCache.object(forKey: token as NSString) { return cached }

    if let data = try? Data(contentsOf: thumbnailURL(for: token)),
       let image = UIImage(data: data) {
      cache(image, as: token, in: thumbnailCache)
      return image
    }

    guard let full = image(for: token) else { return nil }
    let thumbnail = ImageStore.prepared(
      full,
      maximumDimension: ImageStore.thumbnailDimension
    )
    if let data = thumbnail.jpegData(compressionQuality: 0.7) {
      try? data.write(to: thumbnailURL(for: token), options: .atomic)
    }
    cache(thumbnail, as: token, in: thumbnailCache)
    return thumbnail
  }

  // MARK: - Deleting

  func delete(_ token: String?) {
    guard let token, ImageStore.isToken(token) else { return }
    fullCache.removeObject(forKey: token as NSString)
    thumbnailCache.removeObject(forKey: token as NSString)
    try? fileManager.removeItem(at: url(for: token))
    try? fileManager.removeItem(at: thumbnailURL(for: token))
  }

  func delete(_ tokens: [String]) {
    tokens.forEach { delete($0) }
  }

  /// Removes image files nothing references any more — photos whose project or
  /// board was deleted, replaced covers, and so on.
  ///
  /// Only ever call this with the token set of a snapshot that actually loaded:
  /// passing an empty set because loading failed would erase the archive.
  func sweepOrphans(keeping tokens: Set<String>) {
    let keptBases = Set(
      tokens
        .filter { ImageStore.isToken($0) }
        .map { ($0 as NSString).deletingPathExtension }
    )

    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      guard let names = try? self.fileManager
        .contentsOfDirectory(atPath: self.directory.path) else { return }

      for name in names {
        let base = name.hasSuffix(".thumb.jpg")
          ? String(name.dropLast(".thumb.jpg".count))
          : (name as NSString).deletingPathExtension
        guard !keptBases.contains(base) else { continue }
        try? self.fileManager
          .removeItem(at: self.directory.appendingPathComponent(name))
      }
    }
  }

  // MARK: - Helpers

  /// Change-detection key. Tokens are stable across launches, unlike the object
  /// identity the old implementation hashed — which made saves fire constantly.
  func signature(for token: String?) -> String {
    token ?? "no-image"
  }

  static func isToken(_ value: String) -> Bool {
    // "<uuid>.jpg": 36 UUID characters plus a four-character extension.
    guard value.count == 40,
          value.hasSuffix(".jpg") || value.hasSuffix(".png") else { return false }
    return UUID(uuidString: String(value.dropLast(4))) != nil
  }

  static func prepared(
    _ image: UIImage,
    maximumDimension: CGFloat = ImageStore.maximumDimension
  ) -> UIImage {
    let longestSide = max(image.size.width, image.size.height)
    guard longestSide > maximumDimension else { return image }

    let scale = maximumDimension / longestSide
    let targetSize = CGSize(
      width: max((image.size.width * scale).rounded(), 1),
      height: max((image.size.height * scale).rounded(), 1)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = !image.hasTransparency
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private func remember(_ image: UIImage, as token: String) {
    cache(image, as: token, in: fullCache)
    associate(image, with: token)
  }

  private func knownToken(for image: UIImage) -> String? {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    return tokenForImage.object(forKey: image) as String?
  }

  private func associate(_ image: UIImage, with token: String) {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    tokenForImage.setObject(token as NSString, forKey: image)
  }

  /// Caches with a byte cost so `totalCostLimit` can actually bound memory.
  private func cache(
    _ image: UIImage,
    as token: String,
    in cache: NSCache<NSString, UIImage>
  ) {
    cache.setObject(image, forKey: token as NSString, cost: ImageStore.cost(of: image))
  }

  /// Approximate decoded size in bytes.
  private static func cost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else {
      return Int(image.size.width * image.size.height * 4)
    }
    return cgImage.bytesPerRow * cgImage.height
  }

  private func writeThumbnail(for image: UIImage, token: String) {
    let thumbnail = ImageStore.prepared(
      image,
      maximumDimension: ImageStore.thumbnailDimension
    )
    guard let data = thumbnail.jpegData(compressionQuality: 0.7) else { return }
    try? data.write(to: thumbnailURL(for: token), options: .atomic)
    cache(thumbnail, as: token, in: thumbnailCache)
  }

  private func url(for token: String) -> URL {
    directory.appendingPathComponent(token)
  }

  private func thumbnailURL(for token: String) -> URL {
    let base = (token as NSString).deletingPathExtension
    return directory.appendingPathComponent("\(base).thumb.jpg")
  }
}

/// The archive index (projects, boards, customers, companies, manufacturers) as
/// a JSON file in Application Support.
///
/// It used to live in UserDefaults, which has no room for a growing archive and
/// silently stops saving once it gets large. A plain file has no such ceiling.
enum ArchiveStore {
  private static let legacySnapshotKey = "panelvault.savedSnapshot"

  static var directory: URL {
    let manager = FileManager.default
    let base = manager
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? manager.temporaryDirectory
    let folder = base.appendingPathComponent("PanelVault", isDirectory: true)
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  static var snapshotURL: URL {
    directory.appendingPathComponent("snapshot.json")
  }

  /// Returns the stored JSON, migrating a legacy UserDefaults snapshot the
  /// first time it runs. A nil result means "nothing stored yet" — callers must
  /// not treat it as "the archive is empty" and start deleting files.
  static func loadSnapshot() -> String? {
    if let migrated = migrateLegacySnapshot() { return migrated }
    guard let data = try? Data(contentsOf: snapshotURL), !data.isEmpty else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func saveSnapshot(_ json: String) {
    write(json, to: snapshotURL)
  }

  private static func migrateLegacySnapshot() -> String? {
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: legacySnapshotKey),
          !legacy.isEmpty else { return nil }

    // Write the old payload across before dropping it, so an interrupted
    // migration cannot lose the archive.
    try? Data(legacy.utf8).write(to: snapshotURL, options: .atomic)
    defaults.removeObject(forKey: legacySnapshotKey)
    return legacy
  }

  /// Atomic and off the main thread — the snapshot is now small (tokens, not
  /// images), but it is still written on every edit.
  static func write(_ json: String, to url: URL) {
    let data = Data(json.utf8)
    DispatchQueue.global(qos: .utility).async {
      try? data.write(to: url, options: .atomic)
    }
  }
}

/// Component photos, keyed by component id. Same story as the snapshot: this
/// was a second base64 blob in UserDefaults.
enum ComponentImageStore {
  private static let legacyKey = "panelvault.componentImages"

  static var fileURL: URL {
    ArchiveStore.directory.appendingPathComponent("componentImages.json")
  }

  /// Component id -> image token.
  static func load() -> [String: String] {
    if let migrated = migrateLegacyImages() { return migrated }
    guard let data = try? Data(contentsOf: fileURL),
          let tokens = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return tokens.filter { ImageStore.isToken($0.value) }
  }

  static func save(_ tokens: [String: String]) {
    guard let data = try? JSONEncoder().encode(tokens),
          let json = String(data: data, encoding: .utf8) else { return }
    ArchiveStore.write(json, to: fileURL)
  }

  private static func migrateLegacyImages() -> [String: String]? {
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty,
          let data = legacy.data(using: .utf8),
          let encoded = try? JSONDecoder().decode([String: String].self, from: data)
    else { return nil }

    let tokens = encoded.compactMapValues { ImageStore.shared.adopt($0) }
    save(tokens)
    defaults.removeObject(forKey: legacyKey)
    return tokens
  }
}

extension UIImage {
  var hasTransparency: Bool {
    guard let alphaInfo = cgImage?.alphaInfo else { return false }
    switch alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast:
      return true
    default:
      return false
    }
  }
}

struct ProjectRecord: Codable {
  let id: String
  let name: String
  let customer: String
  let detail: String
  let status: String
  let colorHex: UInt32
  let coverImageData: String?
  let photoImageData: [String]?
  let dueDate: Date?
  let schemes: [SchemeRecord]

  init(project: ProjectItem) {
    id = project.id
    name = project.name
    customer = project.customer
    detail = project.detail
    status = project.status
    colorHex = project.color.archiveHex
    coverImageData = project.coverToken
    photoImageData = project.photoTokens
    dueDate = project.dueDate
    schemes = project.schemeAttachments.map(SchemeRecord.init(attachment:))
  }

  var project: ProjectItem {
    // `adopt` passes tokens straight through and converts base64 left over from
    // an older snapshot into files, so existing archives migrate on first load.
    ProjectItem(
      id: id,
      name: name,
      customer: customer,
      detail: detail,
      status: status,
      color: Color(hex: colorHex),
      dueDate: dueDate,
      schemeAttachments: schemes.map(\.attachment),
      coverToken: ImageStore.shared.adopt(coverImageData),
      photoTokens: ImageStore.shared.adopt(photoImageData)
    )
  }
}

struct BoardRecord: Codable {
  let id: String
  let number: String
  let group: String
  let name: String
  let customer: String
  let company: String?
  let project: String
  let type: String
  let subtype: String?
  let manufacturer: String
  let ampere: String
  let cabinetCount: String
  let buildFormat: String
  let dateOut: Date
  let dueDate: Date?
  let finishDate: Date?
  let finishTimeHours: String?
  let mainBreakerType: String
  let mainBreakerModel: String
  let mainBreakerAmpere: String
  let componentTypes: [String]
  let colorHex: UInt32
  let coverImageData: String?
  let photoImageData: [String]?
  let schemes: [SchemeRecord]
  let completedChecklistItems: [String]
  let cabinetChecklists: [[String]]?
  let personalChecklistItems: [PersonalChecklistRecord]

  init(board: BoardDraft) {
    id = board.id
    number = board.number
    group = board.group
    name = board.name
    customer = board.customer
    company = board.company
    project = board.project
    type = board.type
    subtype = board.subtype
    manufacturer = board.manufacturer
    ampere = board.ampere
    cabinetCount = board.cabinetCount
    buildFormat = board.buildFormat
    dateOut = board.dateOut
    dueDate = board.dueDate
    finishDate = board.finishDate
    finishTimeHours = board.finishTimeHours
    mainBreakerType = board.mainBreakerType
    mainBreakerModel = board.mainBreakerModel
    mainBreakerAmpere = board.mainBreakerAmpere
    componentTypes = board.componentTypes
    colorHex = board.color.archiveHex
    coverImageData = board.coverToken
    photoImageData = board.photoTokens
    schemes = board.schemeAttachments.map(SchemeRecord.init(attachment:))
    completedChecklistItems = Array(board.completedChecklistItems)
    cabinetChecklists = board.normalizedCabinetChecklists.map { Array($0) }
    personalChecklistItems = board.personalChecklistItems.map(PersonalChecklistRecord.init(item:))
  }

  var board: BoardDraft {
    BoardDraft(
      id: id,
      number: number,
      group: group,
      name: name,
      customer: customer,
      company: company ?? "",
      project: project,
      type: type,
      subtype: subtype ?? BoardSubtypeCatalog.defaultSubtype,
      manufacturer: manufacturer,
      ampere: ampere,
      cabinetCount: cabinetCount,
      buildFormat: buildFormat,
      dateOut: dateOut,
      dueDate: dueDate,
      finishDate: finishDate,
      finishTimeHours: finishTimeHours ?? "",
      mainBreakerType: mainBreakerType,
      mainBreakerModel: mainBreakerModel,
      mainBreakerAmpere: mainBreakerAmpere,
      componentTypes: componentTypes,
      color: Color(hex: colorHex),
      coverToken: ImageStore.shared.adopt(coverImageData),
      photoTokens: ImageStore.shared.adopt(photoImageData),
      schemeAttachments: schemes.map(\.attachment),
      completedChecklistItems: Set(completedChecklistItems),
      personalChecklistItems: personalChecklistItems.map(\.item),
      cabinetChecklists: (cabinetChecklists ?? []).map(Set.init)
    )
  }
}

struct CustomerRecord: Codable {
  let id: String
  let name: String
  let kind: String?
  let contactName: String?
  let phone: String
  let note: String
  let contacts: [CustomerContactRecord]?
  let colorHex: UInt32?

  init(customer: CustomerItem) {
    id = customer.id
    name = customer.name
    kind = customer.kind
    contactName = customer.contactName
    phone = customer.phone
    note = customer.note
    contacts = customer.contacts.map(CustomerContactRecord.init(contact:))
    colorHex = customer.colorHex
  }

  var customer: CustomerItem {
    CustomerItem(id: id, name: name, kind: kind ?? "Company", contactName: contactName ?? "", phone: phone, note: note, contacts: contacts?.map(\.contact) ?? [], colorHex: colorHex ?? 0x5E78FF)
  }
}

struct CustomerContactRecord: Codable {
  let id: String
  let name: String
  let role: String
  let phone: String

  init(contact: CustomerContact) {
    id = contact.id
    name = contact.name
    role = contact.role
    phone = contact.phone
  }

  var contact: CustomerContact {
    CustomerContact(id: id, name: name, role: role, phone: phone)
  }
}

struct CompanyRecord: Codable {
  let id: String
  let name: String
  let role: String
  let projectCount: String
  let colorHex: UInt32

  init(company: ContractorCompany) {
    id = company.id
    name = company.name
    role = company.role
    projectCount = company.projectCount
    colorHex = company.color.archiveHex
  }

  var company: ContractorCompany {
    ContractorCompany(id: id, name: name, role: role, projectCount: projectCount, color: Color(hex: colorHex))
  }
}

struct ManufacturerRecord: Codable {
  let id: String
  let name: String
  let colorHex: UInt32
  let imageData: String?

  init(manufacturer: ManufacturerItem) {
    id = manufacturer.id
    name = manufacturer.name
    colorHex = manufacturer.colorHex
    imageData = manufacturer.imageToken
  }

  var manufacturer: ManufacturerItem {
    ManufacturerItem(
      id: id,
      name: name,
      colorHex: colorHex,
      imageToken: ImageStore.shared.adopt(imageData)
    )
  }
}

struct SchemeRecord: Codable {
  let id: String
  let kind: String
  let name: String
  let url: String?
  let imageData: String?

  init(attachment: SchemeAttachment) {
    id = attachment.id
    kind = attachment.kind == .pdf ? "pdf" : "photo"
    name = attachment.name
    url = attachment.url?.absoluteString
    imageData = attachment.imageToken
  }

  var attachment: SchemeAttachment {
    SchemeAttachment(
      id: id,
      kind: kind == "pdf" ? .pdf : .photo,
      name: name,
      imageToken: ImageStore.shared.adopt(imageData),
      url: url.flatMap(URL.init(string:))
    )
  }
}

struct PersonalChecklistRecord: Codable {
  let id: String
  let title: String
  let isDone: Bool

  init(item: PersonalChecklistItem) {
    id = item.id
    title = item.title
    isDone = item.isDone
  }

  var item: PersonalChecklistItem {
    PersonalChecklistItem(id: id, title: title, isDone: isDone)
  }
}
