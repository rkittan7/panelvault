import SwiftUI
import VisionKit
import Vision

// MARK: - Document camera

/// Wraps Apple's document scanner. Returns the captured pages as images.
struct DocumentScanner: UIViewControllerRepresentable {
  let onScan: ([UIImage]) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onScan: onScan, dismiss: { dismiss() })
  }

  final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    let onScan: ([UIImage]) -> Void
    let dismiss: () -> Void

    init(onScan: @escaping ([UIImage]) -> Void, dismiss: @escaping () -> Void) {
      self.onScan = onScan
      self.dismiss = dismiss
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFinishWith scan: VNDocumentCameraScan
    ) {
      let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
      dismiss()
      onScan(pages)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      dismiss()
    }

    func documentCameraViewController(
      _ controller: VNDocumentCameraViewController,
      didFailWithError error: Error
    ) {
      dismiss()
    }
  }
}

// MARK: - OCR

enum DeliveryNoteOCR {
  /// Recognized text lines from every page, in reading order.
  static func recognizeLines(in pages: [UIImage]) async -> [String] {
    var lines: [String] = []
    for page in pages {
      guard let cgImage = page.cgImage else { continue }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      // Delivery notes here are English and Hebrew; ask for Hebrew when the
      // OS supports it and fall back silently when it does not.
      let wanted = ["en-US", "he-IL"]
      if let supported = try? request.supportedRecognitionLanguages() {
        request.recognitionLanguages = wanted.filter(supported.contains)
      }
      let handler = VNImageRequestHandler(cgImage: cgImage)
      try? handler.perform([request])
      let observations = request.results ?? []
      lines.append(contentsOf: observations.compactMap { $0.topCandidates(1).first?.string })
    }
    return lines
  }
}

// MARK: - Line parsing and catalog matching

/// One line of a delivery note after parsing: the raw text, the quantity we
/// extracted, and the catalog part we think it is. Never applied without the
/// user confirming it on the review screen.
struct ParsedDeliveryLine: Identifiable {
  let id = UUID()
  let rawText: String
  var quantity: Int
  var matchedPartID: String?
  var include: Bool

  var matchedPart: CatalogPart? {
    matchedPartID.flatMap(Catalog.part(for:))
  }
}

enum DeliveryNoteParser {
  /// Quantity patterns seen on supplier paperwork: "x10", "10x", "10 pcs",
  /// "Qty: 10", a trailing bare integer.
  private static let quantityPatterns = [
    #"(?i)\bqty[.:]?\s*(\d{1,4})\b"#,
    #"(?i)\bx\s*(\d{1,4})\b"#,
    #"(?i)\b(\d{1,4})\s*(?:x|pcs?|pc|units?|יח)\b"#,
    #"\b(\d{1,4})\s*$"#,
  ]

  static func parse(lines: [String]) -> [ParsedDeliveryLine] {
    lines.compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      // Too short to be a goods line, or a pure number (page counts, totals).
      guard trimmed.count >= 4, Int(trimmed) == nil else { return nil }

      let quantity = extractQuantity(from: trimmed)
      let match = bestMatch(for: trimmed)

      // Keep only lines that look like goods: either we matched a part or we
      // found an explicit quantity to review.
      guard match != nil || quantity != nil else { return nil }

      return ParsedDeliveryLine(
        rawText: trimmed,
        quantity: quantity ?? 1,
        matchedPartID: match?.id,
        include: match != nil
      )
    }
  }

  static func extractQuantity(from text: String) -> Int? {
    for pattern in quantityPatterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      guard let match = regex.firstMatch(in: text, range: range),
            let captured = Range(match.range(at: 1), in: text),
            let value = Int(text[captured]), value > 0, value < 10000 else { continue }
      return value
    }
    return nil
  }

  /// Scores every catalog part against the line and returns the best match.
  ///
  /// Model number is the strongest signal on real paperwork ("ACS580",
  /// "S203"), so a model hit scores far above type or manufacturer words.
  static func bestMatch(for text: String) -> CatalogPart? {
    let lowered = text.lowercased()
    var best: (part: CatalogPart, score: Int)?

    for part in Catalog.allParts {
      var score = 0
      let model = part.model.lowercased()
      if lowered.contains(model) {
        score += model.count >= 5 ? 60 : 40
      } else {
        // Try individual model words ("Altivar ATV320" -> "atv320").
        for word in model.split(separator: " ") where word.count >= 4 {
          if lowered.contains(word.lowercased()) { score += 30 }
        }
      }
      if lowered.contains(part.manufacturer.lowercased()) { score += 15 }
      if lowered.contains(part.type.lowercased()) { score += 8 }

      if score > (best?.score ?? 0) {
        best = (part, score)
      }
    }

    // Below this the "match" is a coincidence, not a recognition.
    guard let best, best.score >= 30 else { return nil }
    return best.part
  }
}
