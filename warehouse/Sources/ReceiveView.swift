import SwiftUI

/// Receiving hub: scan a delivery note, or punch a line in manually.
struct ReceiveView: View {
  let theme: WarehouseTheme
  @EnvironmentObject private var store: WarehouseStore
  @State private var scanning = false
  @State private var processing = false
  @State private var review: DeliveryScan?
  @State private var manualPart: CatalogPart?
  @State private var pickingManual = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              Label("Scan delivery note", systemImage: "doc.viewfinder.fill")
                .font(.headline.weight(.heavy))
              Text("Photograph the supplier's paper. Lines are read, matched to your catalog, and shown for you to confirm — nothing updates until you approve it.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
              Button {
                scanning = true
              } label: {
                Label(processing ? "Reading…" : "Scan", systemImage: "camera.fill")
                  .font(.headline.weight(.black))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 12)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(processing)
            }
          }

          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              Label("Manual entry", systemImage: "keyboard.fill")
                .font(.headline.weight(.heavy))
              Text("Find the part and enter the quantity yourself.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.mutedText)
              Button {
                pickingManual = true
              } label: {
                Label("Choose part", systemImage: "magnifyingglass")
                  .font(.headline.weight(.bold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 12)
              }
              .buttonStyle(.bordered)
              .tint(theme.secondary)
            }
          }

          if !store.recentDeliveries.isEmpty {
            GlassCard(theme: theme) {
              VStack(alignment: .leading, spacing: 10) {
                Label("Confirmed deliveries", systemImage: "shippingbox.fill")
                  .font(.headline.weight(.heavy))
                ForEach(store.recentDeliveries.prefix(5)) { delivery in
                  DeliveryHistoryRow(theme: theme, delivery: delivery)
                }
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Receive")
      .fullScreenCover(isPresented: $scanning) {
        DocumentScanner { pages in
          processing = true
          // The moment the paper was photographed, kept separately from the
          // moment it was confirmed: reviewing a long note takes minutes, and
          // the delivery record should say when each happened.
          let scannedAt = Date()
          Task { [customParts = store.customParts, pageCount = pages.count] in
            let lines = await DeliveryNoteOCR.recognizeLines(in: pages)
            let parsed = DeliveryNoteParser.parse(lines: lines, extraParts: customParts)
            await MainActor.run {
              processing = false
              review = DeliveryScan(scannedAt: scannedAt, pageCount: pageCount, lines: parsed)
            }
          }
        }
        .ignoresSafeArea()
      }
      .sheet(isPresented: $pickingManual) {
        PartPickerSheet(theme: theme, title: "Receive Part") { part in
          manualPart = part
        }
      }
      .sheet(item: $manualPart) { part in
        ManualReceiveSheet(theme: theme, part: part)
          .presentationDetents([.medium])
      }
      .sheet(item: $review) { scan in
        ScanReviewView(theme: theme, scan: scan) {
          review = nil
        }
      }
    }
  }
}

/// One completed camera pass, waiting to be reviewed.
struct DeliveryScan: Identifiable {
  let id = UUID()
  let scannedAt: Date
  let pageCount: Int
  let lines: [ParsedDeliveryLine]
}

/// One confirmed delivery, as the worker who confirmed it sees it afterwards.
struct DeliveryHistoryRow: View {
  let theme: WarehouseTheme
  let delivery: DeliveryBatch

  private var subtitle: String {
    let skipped = delivery.lines.count - delivery.lines.filter(\.included).count
    var parts = [delivery.confirmedAt.formatted(date: .abbreviated, time: .shortened)]
    if delivery.pageCount > 0 {
      parts.append("\(delivery.pageCount) page\(delivery.pageCount == 1 ? "" : "s")")
    }
    if skipped > 0 { parts.append("\(skipped) not received") }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(delivery.title)
          .font(.subheadline.weight(.heavy))
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(theme.mutedText)
      }
      Spacer(minLength: 8)
      Text("+\(delivery.receivedUnits)")
        .font(.subheadline.weight(.black))
        .foregroundStyle(theme.positive)
    }
  }
}

struct ManualReceiveSheet: View {
  let theme: WarehouseTheme
  let part: CatalogPart
  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss
  @State private var quantityText = ""
  @State private var reference = ""

  var body: some View {
    NavigationStack {
      Form {
        LabeledContent("Part", value: part.displayName)
        TextField("Quantity", text: $quantityText)
          .keyboardType(.numberPad)
        TextField("Delivery note # (optional)", text: $reference)
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Receive Stock")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Receive") {
            guard let quantity = Int(quantityText), quantity > 0 else { return }
            store.append(StockMovement(
              partID: part.id,
              kind: .receive,
              quantity: quantity,
              reference: reference.trimmingCharacters(in: .whitespaces)
            ))
            dismiss()
          }
          .fontWeight(.bold)
          .disabled((Int(quantityText) ?? 0) <= 0)
        }
      }
    }
    .preferredColorScheme(.dark)
  }
}

/// The safety gate between OCR and the stock log: every parsed line is shown
/// with its match and quantity, correctable, and nothing applies until Confirm.
struct ScanReviewView: View {
  let theme: WarehouseTheme
  let scan: DeliveryScan
  let onDone: () -> Void
  @EnvironmentObject private var store: WarehouseStore
  @State private var lines: [ParsedDeliveryLine]
  @State private var deliveryReference = ""
  @State private var supplier = ""
  @State private var correctingLine: UUID?

  init(theme: WarehouseTheme, scan: DeliveryScan, onDone: @escaping () -> Void) {
    self.theme = theme
    self.scan = scan
    self.onDone = onDone
    _lines = State(initialValue: scan.lines)
  }

  private var includedCount: Int {
    lines.filter { $0.include && $0.matchedPartID != nil }.count
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("Delivery note number (optional)", text: $deliveryReference)
            .listRowBackground(theme.surface)
          TextField("Supplier (optional)", text: $supplier)
            .listRowBackground(theme.surface)
        } footer: {
          Text("\(scan.pageCount) page\(scan.pageCount == 1 ? "" : "s") scanned. Everything read is kept with the delivery, including the lines you leave off.")
            .foregroundStyle(theme.mutedText)
        }
        Section("\(lines.count) lines read — confirm what arrived") {
          ForEach($lines) { $line in
            ReviewLineRow(theme: theme, line: $line) {
              correctingLine = line.id
            }
            .listRowBackground(theme.surface)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Review Delivery")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { onDone() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Confirm \(includedCount)") {
            confirm()
            onDone()
          }
          .fontWeight(.black)
          .disabled(includedCount == 0)
        }
      }
      .sheet(isPresented: Binding(
        get: { correctingLine != nil },
        set: { if !$0 { correctingLine = nil } }
      )) {
        PartPickerSheet(theme: theme, title: "Match Part") { part in
          if let id = correctingLine,
             let index = lines.firstIndex(where: { $0.id == id }) {
            lines[index].matchedPartID = part.id
            lines[index].include = true
          }
          correctingLine = nil
        }
      }
    }
    .preferredColorScheme(.dark)
    .interactiveDismissDisabled()
  }

  /// Turns the reviewed screen into stock plus the paperwork behind it.
  ///
  /// Every line the camera read is recorded, not just the accepted ones — the
  /// question the boss asks later is usually "what did it say?", and a record
  /// that dropped the rejected lines cannot answer it.
  private func confirm() {
    let reference = deliveryReference.trimmingCharacters(in: .whitespaces)
    var movements: [StockMovement] = []
    var batchLines: [DeliveryBatch.Line] = []

    for line in lines {
      let receiving = line.include && line.matchedPartID != nil && line.quantity > 0
      var movementID: String?
      if receiving, let partID = line.matchedPartID {
        let movement = StockMovement(
          partID: partID,
          kind: .receive,
          quantity: line.quantity,
          reference: reference.isEmpty ? "Scanned delivery" : reference
        )
        movements.append(movement)
        movementID = movement.id
      }
      batchLines.append(DeliveryBatch.Line(
        id: line.id.uuidString,
        rawText: line.rawText,
        quantity: line.quantity,
        partID: line.matchedPartID,
        included: receiving,
        movementID: movementID
      ))
    }

    store.confirm(
      DeliveryBatch(
        noteNumber: reference,
        supplier: supplier.trimmingCharacters(in: .whitespaces),
        source: .scan,
        scannedAt: scan.scannedAt,
        pageCount: scan.pageCount,
        lines: batchLines,
        movementIDs: movements.map(\.id)
      ),
      movements: movements
    )
  }
}

struct ReviewLineRow: View {
  let theme: WarehouseTheme
  @Binding var line: ParsedDeliveryLine
  let onCorrect: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Toggle(isOn: $line.include) {
          Text(line.matchedPart?.displayName ?? "No match — tap to choose")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(line.matchedPart == nil ? theme.warning : .primary)
            .lineLimit(1)
        }
        .toggleStyle(.switch)
        .tint(theme.positive)
        .disabled(line.matchedPart == nil)
      }
      Text(line.rawText)
        .font(.caption)
        .foregroundStyle(theme.mutedText)
        .lineLimit(2)
      HStack {
        Stepper("Qty: \(line.quantity)", value: $line.quantity, in: 1...9999)
          .font(.subheadline.weight(.bold))
        Spacer()
        Button(line.matchedPart == nil ? "Choose part" : "Change") {
          onCorrect()
        }
        .font(.caption.weight(.black))
        .buttonStyle(.bordered)
        .tint(theme.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}
