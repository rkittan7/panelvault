import SwiftUI
import Vision
import VisionKit

struct ScannedBarcode: Identifiable {
  let code: String
  let symbology: String
  var id: String { code }
}

struct BarcodeStocktakeView: View {
  let theme: WarehouseTheme
  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss

  @State private var isScanning = true
  @State private var unmappedBarcode: ScannedBarcode?
  @State private var showingManualCode = false
  @State private var manualCode = ""
  @State private var showingAddLocation = false
  @State private var newLocation = ""
  @State private var choosingLoosePart = false
  @State private var showingReview = false
  @State private var confirmingDiscard = false
  @State private var lastAcceptedCode = ""
  @State private var lastAcceptedAt = Date.distantPast
  @State private var duplicateNotice = ""

  private var draft: StocktakeSession? { store.activeStocktake }
  private var lines: [StocktakeSession.Line] { draft?.lines ?? [] }
  private var currentLocationIsOpen: Bool { draft?.currentLocation?.isComplete == false }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          locationCard
          scannerPanel
          lastScanCard
          summary
          if lines.isEmpty {
            GlassCard(theme: theme) {
              VStack(alignment: .leading, spacing: 6) {
                Text("Nothing counted yet")
                  .font(.headline.weight(.heavy))
                Text("Scan each sealed box once, then add loose units from opened boxes.")
                  .font(.subheadline)
                  .foregroundStyle(theme.mutedText)
              }
            }
          } else {
            ForEach(lines) { line in
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
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            showingManualCode = true
          } label: {
            Image(systemName: "keyboard")
          }
          .accessibilityLabel("Enter barcode")
          Menu {
            Button {
              choosingLoosePart = true
            } label: {
              Label("Add loose item", systemImage: "plus.circle")
            }
            Button(role: .destructive) {
              confirmingDiscard = true
            } label: {
              Label("Discard stocktake", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          showingReview = true
        } label: {
          Label(reviewButtonTitle, systemImage: "checkmark.circle.fill")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
        .disabled(lines.isEmpty || draft?.allLocationsComplete != true)
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
          accept(mapping)
          unmappedBarcode = nil
        }
      }
      .sheet(isPresented: $choosingLoosePart) {
        PartPickerSheet(theme: theme, title: "Loose Component") { part in
          store.changeStocktakeLooseUnits(for: part.id, by: 1)
        }
      }
      .fullScreenCover(isPresented: $showingReview) {
        StocktakeReviewView(theme: theme) {
          showingReview = false
          dismiss()
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
      .alert("Add a location", isPresented: $showingAddLocation) {
        TextField("Shelf, room, or zone", text: $newLocation)
        Button("Cancel", role: .cancel) { newLocation = "" }
        Button("Add") {
          store.addStocktakeLocation(named: newLocation)
          newLocation = ""
          isScanning = true
        }
      } message: {
        Text("Count one location at a time to avoid missed or duplicated boxes.")
      }
      .alert("Discard this saved stocktake?", isPresented: $confirmingDiscard) {
        Button("Cancel", role: .cancel) {}
        Button("Discard", role: .destructive) {
          store.discardActiveStocktake()
          dismiss()
        }
      } message: {
        Text("All box scans, loose-unit counts, and completed locations in this draft will be removed.")
      }
    }
    .preferredColorScheme(.dark)
    .onAppear {
      _ = store.startOrResumeStocktake()
      isScanning = currentLocationIsOpen
    }
  }

  private var reviewButtonTitle: String {
    guard draft?.allLocationsComplete == true else { return "Finish Every Location First" }
    return "Review Variances"
  }

  private var locationCard: some View {
    GlassCard(theme: theme, padding: 14) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("COUNTING LOCATION")
              .font(.caption2.weight(.black))
              .foregroundStyle(theme.mutedText)
            Menu {
              ForEach(draft?.locations ?? []) { location in
                Button {
                  store.selectStocktakeLocation(location.id)
                  isScanning = !location.isComplete
                } label: {
                  Label(location.name, systemImage: location.isComplete ? "checkmark.circle.fill" : "circle")
                }
              }
              Divider()
              Button {
                showingAddLocation = true
              } label: {
                Label("Add location", systemImage: "plus")
              }
            } label: {
              HStack(spacing: 6) {
                Text(draft?.currentLocation?.name ?? "Choose location")
                  .font(.headline.weight(.heavy))
                Image(systemName: "chevron.down")
                  .font(.caption.weight(.bold))
              }
            }
          }
          Spacer()
          Text("\(draft?.locations.filter(\.isComplete).count ?? 0)/\(draft?.locations.count ?? 0)")
            .font(.subheadline.weight(.black))
            .foregroundStyle(theme.mutedText)
        }

        Button {
          let complete = !(draft?.currentLocation?.isComplete ?? false)
          store.setCurrentStocktakeLocationComplete(complete)
          isScanning = !complete
        } label: {
          Label(
            currentLocationIsOpen ? "Mark Location Complete" : "Reopen This Location",
            systemImage: currentLocationIsOpen ? "checkmark.circle" : "arrow.uturn.backward.circle"
          )
          .font(.subheadline.weight(.bold))
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(currentLocationIsOpen ? theme.secondary : theme.primary)
      }
    }
  }

  private var scannerPanel: some View {
    ZStack(alignment: .bottom) {
      if !currentLocationIsOpen {
        Rectangle()
          .fill(theme.surface)
          .overlay {
            VStack(spacing: 8) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(theme.primary)
              Text("Location complete")
                .font(.headline.weight(.heavy))
              Text("Choose another location or reopen this one.")
                .font(.caption)
                .foregroundStyle(theme.mutedText)
            }
          }
      } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
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
        Text("\(lines.reduce(0) { $0 + $1.boxScans }) scans")
          .font(.caption.weight(.black))
      }
      .padding(12)
      .background(.ultraThinMaterial)
    }
    .frame(height: 290)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12)))
  }

  @ViewBuilder
  private var lastScanCard: some View {
    if !duplicateNotice.isEmpty {
      Label(duplicateNotice, systemImage: "exclamationmark.triangle.fill")
        .font(.footnote.weight(.bold))
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 4)
    } else if let scan = draft?.scans.last, let part = store.part(for: scan.partID) {
      GlassCard(theme: theme, padding: 12) {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(theme.primary)
          VStack(alignment: .leading, spacing: 2) {
            Text("Last: \(part.displayName)")
              .font(.subheadline.weight(.bold))
              .lineLimit(1)
            Text("Added 1 box × \(scan.packageQuantity)")
              .font(.caption)
              .foregroundStyle(theme.mutedText)
          }
          Spacer()
          if scan.locationID == draft?.currentLocationID && currentLocationIsOpen {
            Button("Undo") {
              store.undoLastStocktakeScan()
              lastAcceptedCode = ""
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.bordered)
          }
        }
      }
    }
  }

  private var summary: some View {
    HStack(spacing: 10) {
      Label("\(lines.count) component types", systemImage: "shippingbox.fill")
      Spacer()
      Text("\(lines.reduce(0) { $0 + $1.counted }) units counted")
    }
    .font(.subheadline.weight(.bold))
    .foregroundStyle(theme.mutedText)
    .padding(.horizontal, 4)
  }

  private func stocktakeRow(_ line: StocktakeSession.Line) -> some View {
    let part = store.part(for: line.partID)
    let current = store.onHand[line.partID] ?? 0
    return GlassCard(theme: theme, padding: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          Image(systemName: "shippingbox.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(theme.secondary)
            .frame(width: 40, height: 40)
            .background(theme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          VStack(alignment: .leading, spacing: 3) {
            Text(part?.displayName ?? line.partID)
              .font(.subheadline.weight(.heavy))
              .lineLimit(2)
            Text("Recorded \(current)  ·  Counted \(line.counted)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(theme.mutedText)
          }
          Spacer(minLength: 6)
          Text("\(line.counted)")
            .font(.title2.weight(.black))
        }
        Text(packageSummary(line))
          .font(.caption.weight(.semibold))
          .foregroundStyle(theme.mutedText)
        HStack {
          Text("Loose in this location")
            .font(.subheadline.weight(.bold))
          Spacer()
          Button { store.changeStocktakeLooseUnits(for: line.partID, by: -1) } label: {
            Image(systemName: "minus")
          }
          .buttonStyle(.bordered)
          .disabled(!currentLocationIsOpen || currentLocationLooseUnits(line) == 0)
          Text("\(currentLocationLooseUnits(line))")
            .font(.headline.weight(.black))
            .frame(minWidth: 36)
          Button { store.changeStocktakeLooseUnits(for: line.partID, by: 1) } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(.bordered)
          .disabled(!currentLocationIsOpen)
        }
      }
    }
  }

  private func currentLocationLooseUnits(_ line: StocktakeSession.Line) -> Int {
    guard let locationID = draft?.currentLocationID else { return 0 }
    return line.looseUnitsByLocation[locationID] ?? 0
  }

  private func packageSummary(_ line: StocktakeSession.Line) -> String {
    var grouped: [Int: Int] = [:]
    for package in line.packages {
      grouped[package.packageQuantity, default: 0] += package.boxes
    }
    var parts = grouped.keys.sorted().map { quantity in
      let boxes = grouped[quantity] ?? 0
      return "\(boxes) box\(boxes == 1 ? "" : "es") × \(quantity)"
    }
    if line.looseUnits > 0 { parts.append("\(line.looseUnits) loose") }
    return parts.isEmpty ? "Loose units only" : parts.joined(separator: " + ")
  }

  private func handle(_ barcode: ScannedBarcode) {
    let code = barcode.code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard currentLocationIsOpen, !code.isEmpty, unmappedBarcode == nil else { return }
    let now = Date()
    if code.caseInsensitiveCompare(lastAcceptedCode) == .orderedSame,
       now.timeIntervalSince(lastAcceptedAt) < 1.5 {
      duplicateNotice = "Duplicate ignored — move to the next box, then scan again."
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      return
    }
    duplicateNotice = ""
    if let mapping = store.barcodeMapping(for: code) {
      accept(mapping)
    } else {
      isScanning = false
      unmappedBarcode = ScannedBarcode(code: code, symbology: barcode.symbology)
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
  }

  private func accept(_ mapping: BarcodeMapping) {
    store.recordStocktakeScan(mapping)
    lastAcceptedCode = mapping.code
    lastAcceptedAt = Date()
    duplicateNotice = ""
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }
}

struct StocktakeReviewView: View {
  let theme: WarehouseTheme
  let onCommitted: () -> Void

  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss
  @State private var confirming = false

  private var draft: StocktakeSession? { store.activeStocktake }
  private var countedPartIDs: Set<String> { Set(draft?.lines.map(\.partID) ?? []) }
  private var unscannedEntries: [StockEntry] {
    store.entries.filter { $0.onHand != 0 && !countedPartIDs.contains($0.part.id) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
              Label("All locations complete", systemImage: "checkmark.seal.fill")
                .font(.headline.weight(.heavy))
                .foregroundStyle(theme.primary)
              Text(draft?.locations.map(\.name).joined(separator: " · ") ?? "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
          }

          Text("COUNTED VARIANCES")
            .font(.caption2.weight(.black))
            .foregroundStyle(theme.mutedText)
            .padding(.horizontal, 4)

          ForEach(draft?.lines ?? []) { line in
            varianceRow(partID: line.partID, physicalCount: line.counted)
          }

          if !unscannedEntries.isEmpty {
            Text("NOT SCANNED")
              .font(.caption2.weight(.black))
              .foregroundStyle(theme.mutedText)
              .padding(.horizontal, 4)
              .padding(.top, 8)
            GlassCard(theme: theme, padding: 14) {
              Text("These products currently have stock but were not counted. They stay unchanged unless you explicitly mark them missing.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
            ForEach(unscannedEntries) { entry in
              missingRow(entry)
            }
          }
        }
        .padding(18)
        .padding(.bottom, 92)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Review Stocktake")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back") { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          confirming = true
        } label: {
          Label("Apply Physical Count", systemImage: "checkmark.shield.fill")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
      }
      .alert("Apply this physical count?", isPresented: $confirming) {
        Button("Cancel", role: .cancel) {}
        Button("Apply Count") {
          store.commitActiveStocktake()
          onCommitted()
        }
      } message: {
        Text("PanelVault will create auditable adjustments for every variance. This stocktake will remain in delivery and activity history.")
      }
    }
    .preferredColorScheme(.dark)
  }

  private func varianceRow(partID: String, physicalCount: Int) -> some View {
    let recorded = store.onHand[partID] ?? 0
    let difference = physicalCount - recorded
    return GlassCard(theme: theme, padding: 12) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(store.part(for: partID)?.displayName ?? partID)
            .font(.subheadline.weight(.heavy))
            .lineLimit(2)
          Text("Recorded \(recorded)  →  Counted \(physicalCount)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.mutedText)
        }
        Spacer()
        Text(difference == 0 ? "No change" : String(format: "%+d", difference))
          .font(.subheadline.weight(.black))
          .foregroundStyle(difference == 0 ? theme.mutedText : (difference < 0 ? Color.orange : theme.primary))
      }
    }
  }

  private func missingRow(_ entry: StockEntry) -> some View {
    let missing = draft?.zeroedPartIDs.contains(entry.part.id) == true
    return GlassCard(theme: theme, padding: 12) {
      Toggle(isOn: Binding(
        get: { missing },
        set: { store.setStocktakePartMissing(entry.part.id, missing: $0) }
      )) {
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.part.displayName)
            .font(.subheadline.weight(.heavy))
            .lineLimit(2)
          Text(missing ? "Set \(entry.onHand) → 0" : "Keep recorded quantity: \(entry.onHand)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(missing ? Color.orange : theme.mutedText)
        }
      }
      .tint(Color.orange)
    }
  }
}

struct BarcodeMappingSheet: View {
  let theme: WarehouseTheme
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
