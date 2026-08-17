// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import SwiftUI
import Vision
import VisionKit

struct ScannedBarcode: Identifiable {
  let code: String
  let symbology: String
  var id: String { code }
}

struct StocktakeCount: Identifiable {
  let partID: String
  var counted: Int
  var scans: Int
  var id: String { partID }
}

struct BarcodeStocktakeView: View {
  let theme: PanelTheme
  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss

  @State private var isScanning = true
  @State private var unmappedBarcode: ScannedBarcode?
  @State private var counts: [StocktakeCount] = []
  @State private var showingManualCode = false
  @State private var manualCode = ""
  @State private var confirming = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          scannerPanel
          summary
          if counts.isEmpty {
            GlassCard(theme: theme) {
              VStack(alignment: .leading, spacing: 6) {
                Text("No boxes counted yet")
                  .font(.headline.weight(.heavy))
                Text("Scan each box once. The first scan of a new barcode teaches PanelVault what is inside.")
                  .font(.subheadline)
                  .foregroundStyle(theme.mutedText)
              }
            }
          } else {
            ForEach(counts) { line in
              stocktakeRow(line)
            }
          }
        }
        .padding(18)
        .padding(.bottom, 92)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Opening Stocktake")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showingManualCode = true
          } label: {
            Image(systemName: "keyboard")
          }
          .accessibilityLabel("Enter barcode")
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          confirming = true
        } label: {
          Label("Review and Set Stock", systemImage: "checkmark.circle.fill")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
        .disabled(counts.isEmpty)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
      }
      .sheet(item: $unmappedBarcode, onDismiss: { isScanning = true }) { barcode in
        BarcodeMappingSheet(theme: theme, barcode: barcode) { mapping in
          store.upsertBarcodeMapping(
            code: mapping.code,
            symbology: mapping.symbology,
            partID: mapping.partID,
            packageQuantity: mapping.packageQuantity,
            boxLabel: mapping.boxLabel
          )
          add(mapping)
          unmappedBarcode = nil
        }
      }
      .alert("Enter barcode", isPresented: $showingManualCode) {
        TextField("Barcode number", text: $manualCode)
          .keyboardType(.asciiCapable)
          .textInputAutocapitalization(.characters)
        Button("Cancel", role: .cancel) { manualCode = "" }
        Button("Use Code") {
          let value = manualCode
          manualCode = ""
          handle(ScannedBarcode(code: value, symbology: "Manual"))
        }
      } message: {
        Text("Useful in Simulator or when a label is damaged.")
      }
      .alert("Set stock to these counts?", isPresented: $confirming) {
        Button("Cancel", role: .cancel) {}
        Button("Set Stock") { commitStocktake() }
      } message: {
        Text("PanelVault will record an opening adjustment for each counted component. The activity history remains fully auditable.")
      }
    }
    .preferredColorScheme(.dark)
  }

  private var scannerPanel: some View {
    ZStack(alignment: .bottom) {
      if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
        BarcodeCameraView(isScanning: $isScanning, onRecognized: handle)
      } else {
        Rectangle()
          .fill(theme.surface)
          .overlay {
            VStack(spacing: 10) {
              Image(systemName: "barcode.viewfinder")
                .font(.system(size: 36, weight: .medium))
              Text("Camera scanning is not available here")
                .font(.subheadline.weight(.bold))
              Button("Enter Code") { showingManualCode = true }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(theme.mutedText)
          }
      }
      HStack {
        Label("Point at one box barcode", systemImage: "viewfinder")
          .font(.footnote.weight(.bold))
        Spacer()
        Text("\(counts.reduce(0) { $0 + $1.scans }) scans")
          .font(.caption.weight(.black))
      }
      .padding(12)
      .background(.ultraThinMaterial)
    }
    .frame(height: 290)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12)))
  }

  private var summary: some View {
    HStack(spacing: 10) {
      Label("\(counts.count) component types", systemImage: "shippingbox.fill")
      Spacer()
      Text("\(counts.reduce(0) { $0 + $1.counted }) units counted")
    }
    .font(.subheadline.weight(.bold))
    .foregroundStyle(theme.mutedText)
    .padding(.horizontal, 4)
  }

  private func stocktakeRow(_ line: StocktakeCount) -> some View {
    let part = store.part(for: line.partID)
    let current = store.onHand[line.partID] ?? 0
    return GlassCard(theme: theme, padding: 12) {
      HStack(spacing: 12) {
        Image(systemName: "barcode")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(theme.secondary)
          .frame(width: 40, height: 40)
          .background(theme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text(part?.displayName ?? line.partID)
            .font(.subheadline.weight(.heavy))
            .lineLimit(2)
          Text("Recorded \(current)  ·  \(line.scans) box scan\(line.scans == 1 ? "" : "s")")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.mutedText)
        }
        Spacer(minLength: 6)
        Button { change(line.partID, by: -1) } label: {
          Image(systemName: "minus")
        }
        .buttonStyle(.bordered)
        .disabled(line.counted <= 0)
        Text("\(line.counted)")
          .font(.title3.weight(.black))
          .frame(minWidth: 34)
        Button { change(line.partID, by: 1) } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func handle(_ barcode: ScannedBarcode) {
    let code = barcode.code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty, unmappedBarcode == nil else { return }
    if let mapping = store.barcodeMapping(for: code) {
      add(mapping)
    } else {
      isScanning = false
      unmappedBarcode = ScannedBarcode(code: code, symbology: barcode.symbology)
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
  }

  private func add(_ mapping: BarcodeMapping) {
    if let index = counts.firstIndex(where: { $0.partID == mapping.partID }) {
      counts[index].counted += mapping.packageQuantity
      counts[index].scans += 1
    } else {
      counts.append(StocktakeCount(partID: mapping.partID, counted: mapping.packageQuantity, scans: 1))
    }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  private func change(_ partID: String, by amount: Int) {
    guard let index = counts.firstIndex(where: { $0.partID == partID }) else { return }
    counts[index].counted = max(0, counts[index].counted + amount)
  }

  private func commitStocktake() {
    let current = store.onHand
    let movements = counts.compactMap { line -> StockMovement? in
      let delta = line.counted - (current[line.partID] ?? 0)
      guard delta != 0 else { return nil }
      return StockMovement(
        partID: line.partID,
        kind: .adjust,
        quantity: delta,
        reference: "Opening stocktake · barcode"
      )
    }
    store.append(movements)
    dismiss()
  }
}

struct BarcodeMappingSheet: View {
  let theme: PanelTheme
  let barcode: ScannedBarcode
  let onSave: (BarcodeMapping) -> Void

  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss
  @State private var selectedPart: CatalogPart?
  @State private var choosingPart = false
  @State private var packageQuantity = 1
  @State private var boxLabel = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("Scanned barcode") {
          LabeledContent("Code", value: barcode.code)
          LabeledContent("Format", value: barcode.symbology)
        }
        Section("What is in this box?") {
          Button {
            choosingPart = true
          } label: {
            HStack {
              Image(systemName: "magnifyingglass")
              Text(selectedPart?.displayName ?? "Choose component")
              Spacer()
              Image(systemName: "chevron.right")
            }
          }
          TextField("Exact box label or SKU (optional)", text: $boxLabel)
        }
        Section("Package") {
          Stepper("Units in one box: \(packageQuantity)", value: $packageQuantity, in: 1...10_000)
          Text("Each future scan of this barcode adds \(packageQuantity) unit\(packageQuantity == 1 ? "" : "s") to the count.")
            .font(.footnote)
            .foregroundStyle(theme.mutedText)
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Teach Barcode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") { save() }
            .fontWeight(.bold)
            .disabled(selectedPart == nil)
        }
      }
      .sheet(isPresented: $choosingPart) {
        PartPickerSheet(theme: theme, title: "Box Component") { part in
          selectedPart = part
          if boxLabel.isEmpty { boxLabel = part.displayName }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private func save() {
    guard let part = selectedPart else { return }
    onSave(BarcodeMapping(
      code: barcode.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
      symbology: barcode.symbology,
      partID: part.id,
      packageQuantity: packageQuantity,
      boxLabel: boxLabel,
      updatedAt: ISO8601DateFormatter.warehouse.string(from: Date()),
      updatedByDeviceID: StockMovement.currentDeviceID
    ))
    dismiss()
  }
}

struct BarcodeCameraView: UIViewControllerRepresentable {
  @Binding var isScanning: Bool
  let onRecognized: (ScannedBarcode) -> Void

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let controller = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [
        .ean8, .ean13, .upce, .code39, .code93, .code128, .itf14,
        .dataMatrix, .qr, .pdf417,
      ])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isHighFrameRateTrackingEnabled: true,
      isPinchToZoomEnabled: true,
      isGuidanceEnabled: true,
      isHighlightingEnabled: true
    )
    controller.delegate = context.coordinator
    try? controller.startScanning()
    return controller
  }

  func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
    if isScanning && !controller.isScanning {
      try? controller.startScanning()
    } else if !isScanning && controller.isScanning {
      controller.stopScanning()
    }
  }

  static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
    controller.stopScanning()
  }

  func makeCoordinator() -> Coordinator { Coordinator(onRecognized: onRecognized) }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onRecognized: (ScannedBarcode) -> Void

    init(onRecognized: @escaping (ScannedBarcode) -> Void) {
      self.onRecognized = onRecognized
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      guard case .barcode(let barcode) = addedItems.first,
            let code = barcode.payloadStringValue else { return }
      onRecognized(ScannedBarcode(
        code: code,
        symbology: barcode.observation.symbology.rawValue
      ))
    }
  }
}
