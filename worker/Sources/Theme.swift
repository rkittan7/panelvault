// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI
import UIKit

struct PanelTheme: Identifiable, Equatable {
  let id: String
  let name: String
  let description: String
  let background: Color
  let surface: Color
  let primary: Color
  let secondary: Color

  // MARK: Design tokens
  // These default to the dark control-room language so every existing theme
  // keeps its current look with no call-site changes. Light skins such as
  // Cupertino override them to change the whole feel — not just the accent.
  var colorScheme: ColorScheme = .dark
  var radiusCard: CGFloat = 16
  var radiusControl: CGFloat = 12
  var radiusPill: CGFloat = 8
  var cardBorder: Color = Color.white.opacity(0.07)
  var elevatedSurface: Color = Color.white.opacity(0.06)
  // Semantic status colors, tuned per skin so pills stay legible on the ground.
  var success: Color = Color(hex: 0x35E177)
  var info: Color = Color(hex: 0x64D2FF)
  var designAccent: Color = Color(hex: 0xFF4FD8)
  var danger: Color = Color(hex: 0xFF6B6B)
  // Floating tab-bar material. Dark skins use a black glass pill; light skins
  // opt into a light one so it doesn't read as a hole in the layout.
  var tabBarTint: Color = Color.black
  var tabBarInactive: Color = Color.white.opacity(0.78)

  // Synthwave. Purple-black ground, hot magenta controls, cyan support, and a
  // neon-tinted card edge instead of the usual hairline.
  static let neonNights = PanelTheme(
    id: "neon-nights",
    name: "Neon Nights",
    description: "Synthwave purple-black with hot magenta and cyan",
    background: Color(hex: 0x0B0313),
    surface: Color(hex: 0x1A0B2E),
    primary: Color(hex: 0xFF2E97),
    secondary: Color(hex: 0x00E5FF),
    colorScheme: .dark,
    radiusCard: 18,
    radiusControl: 14,
    radiusPill: 10,
    cardBorder: Color(hex: 0xFF2E97).opacity(0.20),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x3DFFA8),
    info: Color(hex: 0x00E5FF),
    designAccent: Color(hex: 0xFF2E97),
    danger: Color(hex: 0xFF4D6D),
    tabBarTint: Color(hex: 0x12061F),
    tabBarInactive: Color(hex: 0x9B7FB8)
  )

  // Eighties Miami. Deep teal-navy with hot pink and aqua, soft fat corners.
  static let miami = PanelTheme(
    id: "miami",
    name: "Miami",
    description: "Eighties teal and hot pink with soft fat corners",
    background: Color(hex: 0x071A26),
    surface: Color(hex: 0x0E2C3D),
    primary: Color(hex: 0xFF4FA3),
    secondary: Color(hex: 0x2EE6C5),
    colorScheme: .dark,
    radiusCard: 22,
    radiusControl: 18,
    radiusPill: 12,
    cardBorder: Color(hex: 0x2EE6C5).opacity(0.18),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x2EE6C5),
    info: Color(hex: 0x4FC3F7),
    designAccent: Color(hex: 0xFF4FA3),
    danger: Color(hex: 0xFF6B6B),
    tabBarTint: Color(hex: 0x05141D),
    tabBarInactive: Color(hex: 0x7FA6B8)
  )

  // Electric lime on deep violet. The loudest pairing in the set.
  static let ultraviolet = PanelTheme(
    id: "ultraviolet",
    name: "Ultraviolet",
    description: "Deep violet with electric lime controls",
    background: Color(hex: 0x0A0618),
    surface: Color(hex: 0x171030),
    primary: Color(hex: 0xB4FF39),
    secondary: Color(hex: 0xA855F7),
    colorScheme: .dark,
    radiusCard: 16,
    radiusControl: 12,
    radiusPill: 8,
    cardBorder: Color(hex: 0xB4FF39).opacity(0.16),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0xB4FF39),
    info: Color(hex: 0xA855F7),
    designAccent: Color(hex: 0xC77DFF),
    danger: Color(hex: 0xFF5C7C),
    tabBarTint: Color(hex: 0x080412),
    tabBarInactive: Color(hex: 0x8B7FA8)
  )

  // Molten. Near-black brown ground with vivid orange and yellow.
  static let solarFlare = PanelTheme(
    id: "solar-flare",
    name: "Solar Flare",
    description: "Molten orange and yellow on scorched black",
    background: Color(hex: 0x140A02),
    surface: Color(hex: 0x241203),
    primary: Color(hex: 0xFF7A18),
    secondary: Color(hex: 0xFFD028),
    colorScheme: .dark,
    radiusCard: 10,
    radiusControl: 8,
    radiusPill: 6,
    cardBorder: Color(hex: 0xFF7A18).opacity(0.20),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x7FD858),
    info: Color(hex: 0xFFD028),
    designAccent: Color(hex: 0xFF7A18),
    danger: Color(hex: 0xFF4530),
    tabBarTint: Color(hex: 0x0E0701),
    tabBarInactive: Color(hex: 0xB08A63)
  )

  // CRT terminal. Pure black, phosphor green, amber support, hard corners.
  static let terminal = PanelTheme(
    id: "terminal",
    name: "Terminal",
    description: "Phosphor green and amber on pure black",
    background: Color(hex: 0x000000),
    surface: Color(hex: 0x0A140A),
    primary: Color(hex: 0x33FF66),
    secondary: Color(hex: 0xFFB000),
    colorScheme: .dark,
    radiusCard: 16,
    radiusControl: 12,
    radiusPill: 8,
    cardBorder: Color(hex: 0x33FF66).opacity(0.24),
    elevatedSurface: Color(hex: 0x33FF66).opacity(0.06),
    success: Color(hex: 0x33FF66),
    info: Color(hex: 0x00E5FF),
    designAccent: Color(hex: 0xFFB000),
    danger: Color(hex: 0xFF3B30),
    tabBarTint: Color(hex: 0x000000),
    tabBarInactive: Color(hex: 0x4E7A57)
  )

  // The light funky option. Candy pink ground, magenta and purple, very round.
  static let bubblegum = PanelTheme(
    id: "bubblegum",
    name: "Bubblegum",
    description: "Candy pink and purple, extra round and playful",
    background: Color(hex: 0xFFF0F6),
    surface: Color(hex: 0xFFFFFF),
    primary: Color(hex: 0xE5399B),
    secondary: Color(hex: 0x7C4DFF),
    colorScheme: .light,
    radiusCard: 22,
    radiusControl: 18,
    radiusPill: 14,
    cardBorder: Color(hex: 0xE5399B).opacity(0.16),
    elevatedSurface: Color.black.opacity(0.03),
    success: Color(hex: 0x00B37E),
    info: Color(hex: 0x7C4DFF),
    designAccent: Color(hex: 0xE5399B),
    danger: Color(hex: 0xF43F5E),
    tabBarTint: Color.white,
    tabBarInactive: Color(hex: 0xB08AA0)
  )

  // Apple-native light skin. Light system grays, iOS blue, tighter rounding,
  // and a light frosted tab bar. Reads like a first-party iOS app.
  static let cupertino = PanelTheme(
    id: "cupertino",
    name: "Cupertino",
    description: "Apple-native light theme with system grays and iOS blue",
    background: Color(hex: 0xF2F2F7),
    surface: Color(hex: 0xFFFFFF),
    primary: Color(hex: 0x007AFF),
    secondary: Color(hex: 0x5AC8FA),
    colorScheme: .light,
    radiusCard: 14,
    radiusControl: 10,
    radiusPill: 7,
    cardBorder: Color.black.opacity(0.06),
    elevatedSurface: Color.black.opacity(0.03),
    success: Color(hex: 0x34C759),
    info: Color(hex: 0x007AFF),
    designAccent: Color(hex: 0xFF9500),
    danger: Color(hex: 0xFF3B30),
    tabBarTint: Color.white,
    tabBarInactive: Color(hex: 0x8A8A8E)
  )

  // Draftsman skin. A cool "spec sheet" identity: paper-gray ground, white
  // cards, ink-teal accent. Reads like an electrical single-line diagram.
  static let blueprint = PanelTheme(
    id: "blueprint",
    name: "Blueprint",
    description: "Technical spec-sheet look with paper ground and ink teal",
    background: Color(hex: 0xE9EDF1),
    surface: Color(hex: 0xFFFFFF),
    primary: Color(hex: 0x0F6D7E),
    secondary: Color(hex: 0x1B4D8F),
    colorScheme: .light,
    radiusCard: 14,
    radiusControl: 11,
    radiusPill: 8,
    cardBorder: Color(hex: 0x16222E).opacity(0.16),
    elevatedSurface: Color.black.opacity(0.03),
    success: Color(hex: 0x2F7D32),
    info: Color(hex: 0x0F6D7E),
    designAccent: Color(hex: 0x9A5B00),
    danger: Color(hex: 0xC0392B),
    tabBarTint: Color.white,
    tabBarInactive: Color(hex: 0x5A6B78)
  )

  // Rugged workshop skin. Dark slate with a safety-amber accent — high
  // contrast, warm, built to be read fast on site.
  static let field = PanelTheme(
    id: "field",
    name: "Field",
    description: "Rugged dark slate with a safety-amber accent",
    background: Color(hex: 0x16181C),
    surface: Color(hex: 0x202429),
    primary: Color(hex: 0xFFB020),
    secondary: Color(hex: 0xFF6A3D),
    colorScheme: .dark,
    radiusCard: 8,
    radiusControl: 7,
    radiusPill: 4,
    cardBorder: Color.white.opacity(0.09),
    elevatedSurface: Color.white.opacity(0.06),
    success: Color(hex: 0x5FD08A),
    info: Color(hex: 0x4EA3FF),
    designAccent: Color(hex: 0xFFB020),
    danger: Color(hex: 0xFF6B6B),
    tabBarTint: Color(hex: 0x101215),
    tabBarInactive: Color(hex: 0x9AA0A6)
  )

  static let all = [cupertino, neonNights, miami, ultraviolet, solarFlare, terminal, bubblegum, blueprint, field]
}

struct AccentChoice: Identifiable {
  let id: UInt32
  let name: String

  var color: Color {
    Color(hex: id)
  }
}

enum AccentPalette {
  static let choices = [
    AccentChoice(id: 0x5E78FF, name: "Blue"),
    AccentChoice(id: 0x64D2FF, name: "Sky"),
    AccentChoice(id: 0x35E177, name: "Green"),
    AccentChoice(id: 0x7FAE9A, name: "Sage"),
    AccentChoice(id: 0x00C7BE, name: "Teal"),
    AccentChoice(id: 0xD85CFF, name: "Violet"),
    AccentChoice(id: 0xBF5AF2, name: "Purple"),
    AccentChoice(id: 0xFF9F0A, name: "Amber"),
    AccentChoice(id: 0xFFD60A, name: "Gold"),
    AccentChoice(id: 0xFF4E5F, name: "Red"),
    AccentChoice(id: 0xFF6B35, name: "Orange"),
    AccentChoice(id: 0xAEB4BC, name: "Titanium")
  ]
}

struct ColorSwatchPicker: View {
  let title: String
  @Binding var selectedHex: UInt32
  @State private var customColor = Color(hex: 0x5E78FF)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.caption.bold())
        .foregroundStyle(.secondary)

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
        ForEach(AccentPalette.choices) { choice in
          Button {
            selectedHex = choice.id
          } label: {
            Circle()
              .fill(choice.color.gradient)
              .frame(width: 30, height: 30)
              .overlay {
                if selectedHex == choice.id {
                  Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                }
              }
              .overlay(
                Circle()
                  .stroke(selectedHex == choice.id ? .white.opacity(0.88) : .white.opacity(0.16), lineWidth: selectedHex == choice.id ? 2 : 1)
              )
              .accessibilityLabel(choice.name)
          }
          .buttonStyle(.plain)
        }
      }

      ColorPicker("Custom color", selection: $customColor, supportsOpacity: false)
        .font(.caption.bold())
        .onChange(of: customColor) { newColor in
          if let hex = Self.hexValue(from: newColor) {
            selectedHex = hex
          }
        }
    }
    .onAppear {
      customColor = Color(hex: selectedHex)
    }
  }

  private static func hexValue(from color: Color) -> UInt32? {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
    return (UInt32(red * 255) << 16) | (UInt32(green * 255) << 8) | UInt32(blue * 255)
  }
}

struct InterfaceSize: Identifiable, Equatable {
  let id: String
  let name: String
  let subtitle: String
  let dashboardSpacing: CGFloat
  let dashboardPadding: CGFloat
  let statHeight: CGFloat
  let titleSize: CGFloat
  let logoSize: CGFloat
  let rowScale: CGFloat
  let boardTypeColumns: Int
  let boardTypeIconSize: CGFloat
  let boardTypeTitleSize: CGFloat
  let boardTypeSubtitleSize: CGFloat

  static let compact = InterfaceSize(id: "compact", name: "Compact", subtitle: "More on screen", dashboardSpacing: 12, dashboardPadding: 10, statHeight: 78, titleSize: 20, logoSize: 26, rowScale: 0.94, boardTypeColumns: 3, boardTypeIconSize: 30, boardTypeTitleSize: 12, boardTypeSubtitleSize: 9)
  static let standard = InterfaceSize(id: "standard", name: "Standard", subtitle: "Balanced", dashboardSpacing: 22, dashboardPadding: 18, statHeight: 112, titleSize: 24, logoSize: 32, rowScale: 1, boardTypeColumns: 2, boardTypeIconSize: 38, boardTypeTitleSize: 15, boardTypeSubtitleSize: 11)
  static let large = InterfaceSize(id: "large", name: "Large", subtitle: "Easier to read", dashboardSpacing: 26, dashboardPadding: 20, statHeight: 122, titleSize: 26, logoSize: 36, rowScale: 1.04, boardTypeColumns: 2, boardTypeIconSize: 42, boardTypeTitleSize: 16, boardTypeSubtitleSize: 12)

  static let all = [compact, standard, large]

  static func option(for id: String) -> InterfaceSize {
    all.first { $0.id == id } ?? .standard
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  var archiveHex: UInt32 {
    let uiColor = UIColor(self)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0x5E78FF }
    return (UInt32(red * 255) << 16) | (UInt32(green * 255) << 8) | UInt32(blue * 255)
  }
}

// MARK: - Warehouse stock (PanelVault Cloud)
//
// The warehouse app and this app share one key: a component's catalog id.
// `StockMovement.partID` in warehouse/Sources/Models.swift is exactly
// `PanelComponent.id` here, so on-hand counts pulled from Cloud can be shown
// straight on the catalog. Stock is always replayed from the append-only
// movement log; this client never invents or edits a total.
