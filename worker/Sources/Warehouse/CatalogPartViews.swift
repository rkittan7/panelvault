// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import SwiftUI

// The catalog picture in the shapes the warehouse screens need. Split from
// CatalogImages.swift because tools/port_warehouse.py carries this file into
// the worker app, swapping the theme type as it goes, while the lookup library
// itself is already there from the PanelVault side.

/// The picture slot at the head of a part row.
///
/// Always the same size whether or not a photo exists, so a list of parts stays
/// on one left edge as photos are added to the catalog a few at a time.
struct CatalogPartThumb: View {
  let theme: PanelTheme
  let part: CatalogPart
  var size: CGFloat = 44

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        .fill(theme.primary.opacity(0.10))
      if let photo = CatalogImageLibrary.componentThumbnail(id: part.id) {
        Image(uiImage: photo)
          .resizable()
          .scaledToFit()
          .padding(size * 0.09)
      } else {
        Image(systemName: CatalogPartThumb.symbol(for: part.type))
          .font(.system(size: size * 0.42, weight: .bold))
          .foregroundStyle(theme.primary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
  }

  /// Mirrors `ComponentIcon.symbol(for:)` in the PanelVault apps, so the same
  /// part is drawn with the same symbol on every screen a worker sees.
  static func symbol(for type: String) -> String {
    let key = type.lowercased()
    switch true {
    case key.contains("mccb"): return "bolt.shield.fill"
    case key.contains("mcb"): return "bolt.fill"
    case key.contains("rcbo"): return "shield.lefthalf.filled"
    case key.contains("rcd"), key.contains("rccb"): return "shield.fill"
    case key.contains("contactor"): return "square.stack.3d.up.fill"
    case key.contains("relay"): return "switch.2"
    case key.contains("vfd"), key.contains("drive"): return "gauge.with.dots.needle.67percent"
    case key.contains("psu"), key.contains("supply"): return "powerplug.fill"
    case key.contains("busbar"), key.contains("bus"): return "rectangle.split.3x1.fill"
    case key.contains("meter"): return "speedometer"
    case key.contains("spd"), key.contains("surge"): return "exclamationmark.shield.fill"
    case key.contains("terminal"): return "circle.grid.3x3.fill"
    case key.contains("transformer"), key.contains("ct"): return "circle.circle.fill"
    default: return "shippingbox.fill"
    }
  }
}

/// The manufacturer's logo, drawn inline next to a part's details. Renders
/// nothing at all when that brand has no logo in `assets/catalog` yet.
struct CatalogBrandMark: View {
  let manufacturer: String
  var height: CGFloat = 13

  var body: some View {
    if let logo = CatalogImageLibrary.manufacturerThumbnail(name: manufacturer) {
      Image(uiImage: logo)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: height * 3.4, maxHeight: height)
        .accessibilityLabel(manufacturer)
    }
  }
}
