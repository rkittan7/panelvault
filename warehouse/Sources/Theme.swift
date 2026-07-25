import SwiftUI

/// Visual language copied from PanelVault so the two apps read as one product.
/// Values mirror PanelTheme "Obsidian Blue" in ios/Runner/SceneDelegate.swift.
struct WarehouseTheme {
  let background = Color(hex: 0x050607)
  let surface = Color(hex: 0x121417)
  let primary = Color(hex: 0x6E86FF)
  let secondary = Color(hex: 0x4CC9F0)
  let positive = Color(hex: 0x35E177)
  let warning = Color(hex: 0xFFC43D)
  let negative = Color(hex: 0xFF4E5F)
  let mutedText = Color(hex: 0xB8BECA)

  static let standard = WarehouseTheme()
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

/// The rounded translucent card used everywhere in PanelVault.
struct GlassCard<Content: View>: View {
  let theme: WarehouseTheme
  var padding: CGFloat = 14
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.surface.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.white.opacity(0.07))
      )
      .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 8)
  }
}

struct SectionHeading: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title2.weight(.heavy))
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct StatTile: View {
  let theme: WarehouseTheme
  let title: String
  let value: String
  let symbol: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme, padding: 10) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(color)
        Text(title)
          .font(.caption.weight(.bold))
          .foregroundStyle(theme.mutedText)
          .lineLimit(2)
        Text(value)
          .font(.system(size: 26, weight: .black))
          .foregroundStyle(color)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    }
  }
}
