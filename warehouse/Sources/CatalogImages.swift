// Copied verbatim from worker/Sources/CatalogImages.swift so all four
// PanelVault surfaces resolve catalog pictures identically. If you change the
// lookup rules, change them there first and copy the file across.

import UIKit

/// The pictures that ship with the app: one logo per manufacturer, one photo
/// per catalog part.
///
/// The files live in `assets/catalog` at the repo root and are bundled as a
/// folder reference, so PanelVault, the Worker app, the Warehouse app and
/// PanelVault Cloud all show the same photograph of the same part — there is
/// exactly one copy of each file in the repository and every surface points at
/// it. `assets/catalog/index.json`, written by tools/sync_catalog_images.py,
/// maps a catalog id to its filename. A part the manifest does not list simply
/// has no photo yet, and the caller falls back to its category symbol.
///
/// Everything here is a *default*. A photo the user took on this device lives
/// in `ImageStore` and always wins; nothing in this type ever writes there, so
/// a bundled picture can never overwrite or delete someone's own.
enum CatalogImageLibrary {
  /// The folder as it is named inside the built app, which is the last path
  /// component of the folder reference in each Xcode project.
  private static let bundleFolder = "catalog"

  /// Long side of the row thumbnail. Matches `ImageStore.thumbnailDimension`
  /// so a catalog photo and a user photo look identical in the same list.
  private static let thumbnailDimension: CGFloat = 400

  private struct Manifest: Decodable {
    var manufacturers: [String: String]?
    var components: [String: String]?
  }

  /// Decoded once, lazily. A `static let` is initialized under `swift_once`,
  /// so concurrent first access from several rows is safe.
  private static let manifest: Manifest = {
    guard let base = Bundle.main.resourceURL else { return Manifest() }
    let url = base
      .appendingPathComponent(bundleFolder, isDirectory: true)
      .appendingPathComponent("index.json")
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(Manifest.self, from: data)
    else { return Manifest() }
    return decoded
  }()

  private static let fullCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 12
    cache.totalCostLimit = 32 * 1024 * 1024
    return cache
  }()

  private static let thumbnailCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 240
    cache.totalCostLimit = 24 * 1024 * 1024
    return cache
  }()

  // MARK: - Lookup

  /// Whether a part has a bundled photo, without paying to decode it.
  static func hasComponentImage(id: String) -> Bool {
    manifest.components?[id] != nil
  }

  static func componentImage(id: String) -> UIImage? {
    image(at: manifest.components?[id])
  }

  static func componentThumbnail(id: String) -> UIImage? {
    thumbnail(at: manifest.components?[id])
  }

  /// The first of `ids` that has a photo. Catalog parts carry both an `id` and
  /// a `sourceID` — a part placed on a board keeps its own id but is the same
  /// product as the catalog entry it came from — so callers pass both.
  static func componentThumbnail(ids: [String]) -> UIImage? {
    for id in ids {
      if let image = thumbnail(at: manifest.components?[id]) { return image }
    }
    return nil
  }

  static func manufacturerImage(name: String) -> UIImage? {
    image(at: manifest.manufacturers?[slug(name)])
  }

  static func manufacturerThumbnail(name: String) -> UIImage? {
    thumbnail(at: manifest.manufacturers?[slug(name)])
  }

  /// `Mean Well` -> `mean-well`. Must stay in step with `slug()` in
  /// tools/sync_catalog_images.py, which names the files.
  static func slug(_ name: String) -> String {
    let lowered = name.lowercased()
    let mapped = lowered.map { character -> Character in
      character.isLetter || character.isNumber ? character : "-"
    }
    return String(mapped)
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }

  // MARK: - Loading

  private static func image(at relativePath: String?) -> UIImage? {
    guard let relativePath, let key = cacheKey(relativePath) else { return nil }
    if let cached = fullCache.object(forKey: key) { return cached }
    guard let url = url(for: relativePath),
          let data = try? Data(contentsOf: url),
          let image = UIImage(data: data) else { return nil }
    fullCache.setObject(image, forKey: key, cost: cost(of: image))
    return image
  }

  private static func thumbnail(at relativePath: String?) -> UIImage? {
    guard let relativePath, let key = cacheKey(relativePath) else { return nil }
    if let cached = thumbnailCache.object(forKey: key) { return cached }
    guard let full = image(at: relativePath) else { return nil }
    let scaled = downscaled(full, to: thumbnailDimension)
    thumbnailCache.setObject(scaled, forKey: key, cost: cost(of: scaled))
    return scaled
  }

  private static func cacheKey(_ relativePath: String) -> NSString? {
    relativePath.isEmpty ? nil : relativePath as NSString
  }

  /// The manifest is generated and ships inside the bundle, so it is trusted —
  /// but a path is a path, and a stray `..` in a hand-edited index.json should
  /// not be able to read files outside the catalog folder.
  private static func url(for relativePath: String) -> URL? {
    guard !relativePath.hasPrefix("/"),
          !relativePath.split(separator: "/").contains("..") else { return nil }
    return Bundle.main.resourceURL?
      .appendingPathComponent(bundleFolder, isDirectory: true)
      .appendingPathComponent(relativePath)
  }

  private static func downscaled(_ image: UIImage, to maximumDimension: CGFloat) -> UIImage {
    let longestSide = max(image.size.width, image.size.height)
    guard longestSide > maximumDimension else { return image }

    let scale = maximumDimension / longestSide
    let targetSize = CGSize(
      width: max((image.size.width * scale).rounded(), 1),
      height: max((image.size.height * scale).rounded(), 1)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    // Logos arrive as cut-outs on transparency and are drawn over the row, so
    // an opaque context would fill their background with black.
    format.opaque = false
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private static func cost(of image: UIImage) -> Int {
    Int(image.size.width * image.size.height * image.scale * image.scale * 4)
  }
}
