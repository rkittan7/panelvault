// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import SwiftUI

/// Receiving hub: scan a delivery note, or punch a line in manually.
struct ReceiveView: View {
  let theme: PanelTheme
  @EnvironmentObject private var store: WarehouseStore
  @State private var scanning = false
  @State private var processing = false
  @State private var reviewLines: [ParsedDeliveryLine]?
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
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Receive")
      .fullScreenCover(isPresented: $scanning) {
        DocumentScanner { pages in
          processing = true
          Task { [customParts = store.customParts] in
            let lines = await DeliveryNoteOCR.recognizeLines(in: pages)
            let parsed = DeliveryNoteParser.parse(lines: lines, extraParts: customParts)
            await MainActor.run {
              processing = false
              reviewLines = parsed
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
      .sheet(isPresented: Binding(
        get: { reviewLines != nil },
        set: { if !$0 { reviewLines = nil } }
      )) {
        if let lines = reviewLines {
          ScanReviewView(theme: theme, lines: lines) {
            reviewLines = nil
          }
        }
      }
    }
  }
}

struct ManualReceiveSheet: View {
  let theme: PanelTheme
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
  let theme: PanelTheme
  @State var lines: [ParsedDeliveryLine]
  let onDone: () -> Void
  @EnvironmentObject private var store: WarehouseStore
  @State private var deliveryReference = ""
  @State private var correctingLine: UUID?

  private var includedCount: Int {
    lines.filter { $0.include && $0.matchedPartID != nil }.count
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          TextField("Delivery note number (optional)", text: $deliveryReference)
            .listRowBackground(theme.surface)
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
            let reference = deliveryReference.trimmingCharacters(in: .whitespaces)
            let batch = lines
              .filter { $0.include }
              .compactMap { line -> StockMovement? in
                guard let partID = line.matchedPartID, line.quantity > 0 else { return nil }
                return StockMovement(
                  partID: partID,
                  kind: .receive,
                  quantity: line.quantity,
                  reference: reference.isEmpty ? "Scanned delivery" : reference
                )
              }
            store.append(batch)
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
}

struct ReviewLineRow: View {
  let theme: PanelTheme
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
