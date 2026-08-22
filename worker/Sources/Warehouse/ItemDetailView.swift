// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import SwiftUI

struct ItemDetailView: View {
  let theme: PanelTheme
  let partID: String
  @EnvironmentObject private var store: WarehouseStore
  @State private var adjusting = false

  private var part: CatalogPart? { store.part(for: partID) }
  private var entry: StockEntry? { store.entry(for: partID) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let part {
          header(part)
          if !part.about.isEmpty {
            GlassCard(theme: theme) {
              Text(part.about)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          settingsCard
          SectionHeading(title: "History")
          let history = store.movements(for: partID)
          if history.isEmpty {
            GlassCard(theme: theme) {
              Text("No movements for this part yet.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
          } else {
            ForEach(history) { movement in
              MovementRow(theme: theme, movement: movement)
            }
          }
        }
      }
      .padding(18)
    }
    .background(theme.background.ignoresSafeArea())
    .navigationTitle(part?.model ?? "Part")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Adjust") { adjusting = true }
          .fontWeight(.bold)
      }
    }
    .sheet(isPresented: $adjusting) {
      AdjustSheet(theme: theme, partID: partID)
        .presentationDetents([.medium])
    }
  }

  private func header(_ part: CatalogPart) -> some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          CatalogPartThumb(theme: theme, part: part, size: 64)
          VStack(alignment: .leading, spacing: 4) {
            Text(part.displayName)
              .font(.title3.weight(.black))
            HStack(spacing: 6) {
              CatalogBrandMark(manufacturer: part.manufacturer)
              Text("\(part.type) • \(part.rating) • \(part.poles)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
            if let serialNumber = part.serialNumber, !serialNumber.isEmpty {
              Text("Serial: \(serialNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.primary)
            }
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text("\(entry?.onHand ?? 0)")
              .font(.system(size: 34, weight: .black))
              .foregroundStyle((entry?.isLow ?? false) ? theme.warning : theme.positive)
            Text("on hand")
              .font(.caption2.weight(.bold))
              .foregroundStyle(theme.mutedText)
          }
        }
      }
    }
  }

  private var settingsCard: some View {
    GlassCard(theme: theme) {
      let current = entry?.settings ?? .none
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Minimum level", systemImage: "exclamationmark.triangle")
            .font(.subheadline.weight(.bold))
          Spacer()
          Stepper(
            "\(current.minimumLevel ?? 0)",
            value: Binding(
              get: { current.minimumLevel ?? 0 },
              set: { store.updateSettings(for: partID, PartSettings(minimumLevel: $0 == 0 ? nil : $0, location: current.location)) }
            ),
            in: 0...9999
          )
          .fixedSize()
        }
        HStack {
          Label("Location", systemImage: "mappin.and.ellipse")
            .font(.subheadline.weight(.bold))
          Spacer()
          TextField(
            "Shelf / drawer",
            text: Binding(
              get: { current.location },
              set: { store.updateSettings(for: partID, PartSettings(minimumLevel: current.minimumLevel, location: $0)) }
            )
          )
          .multilineTextAlignment(.trailing)
          .font(.subheadline.weight(.semibold))
        }
      }
    }
  }
}

/// Manual stock correction: physical count or board consumption.
struct AdjustSheet: View {
  let theme: PanelTheme
  let partID: String
  @EnvironmentObject private var store: WarehouseStore
  @Environment(\.dismiss) private var dismiss
  @State private var kind: StockMovement.Kind = .adjust
  @State private var quantityText = ""
  @State private var reference = ""

  var body: some View {
    NavigationStack {
      Form {
        Picker("Type", selection: $kind) {
          Text("Correction").tag(StockMovement.Kind.adjust)
          Text("Used on board").tag(StockMovement.Kind.consume)
          Text("Received").tag(StockMovement.Kind.receive)
        }
        .pickerStyle(.segmented)

        TextField(kind == .adjust ? "Change (+/-)" : "Quantity", text: $quantityText)
          .keyboardType(kind == .adjust ? .numbersAndPunctuation : .numberPad)

        TextField(kind == .consume ? "Board number" : "Reference (optional)", text: $reference)
      }
      .scrollContentBackground(.hidden)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Adjust Stock")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            guard let quantity = Int(quantityText), quantity != 0 else { return }
            store.append(StockMovement(
              partID: partID,
              kind: kind,
              quantity: kind == .adjust ? quantity : abs(quantity),
              reference: reference.trimmingCharacters(in: .whitespaces)
            ))
            dismiss()
          }
          .fontWeight(.bold)
          .disabled(Int(quantityText) == nil || Int(quantityText) == 0)
        }
      }
    }
    .preferredColorScheme(.dark)
  }
}

struct ActivityView: View {
  let theme: PanelTheme
  @EnvironmentObject private var store: WarehouseStore

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          if store.recentMovements.isEmpty {
            GlassCard(theme: theme) {
              Text("Every stock movement will appear here — receipts, board usage and corrections.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.mutedText)
            }
          }
          ForEach(store.recentMovements) { movement in
            MovementRow(theme: theme, movement: movement)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Activity")
    }
  }
}
