// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

struct StatusBadge: View {
  let status: String

  private var color: Color {
    switch status {
    case "Design":
      return Color(hex: 0xD85CFF)
    case "In Progress", "Active":
      return Color(hex: 0x2F8CFF)
    case "Completed", "Done", "Finished":
      return Color(hex: 0x35E177)
    default:
      return Color(hex: 0x8B4DFF)
    }
  }

  var body: some View {
    Text(status)
      .font(.caption.bold())
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.22))
      .clipShape(Capsule())
      .shadow(color: color.opacity(0.34), radius: 10, y: 2)
  }
}

struct BoardProgressStatusBadge: View {
  let board: BoardDraft

  private var progress: CGFloat {
    min(max(CGFloat(board.completion) / 100, 0), 1)
  }

  var body: some View {
    if board.isCompleted {
      StatusBadge(status: board.statusTitle)
    } else {
      ZStack(alignment: .leading) {
        Capsule()
          .fill(progressColor.opacity(0.18))
        GeometryReader { proxy in
          Capsule()
            .fill(
              LinearGradient(
                colors: [progressColor.opacity(0.78), progressColor],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: max(proxy.size.width * progress, progress > 0 ? 12 : 0))
        }
        Text("\(board.completion)%")
          .font(.system(size: 10, weight: .black))
          .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
      }
      .frame(width: 62, height: 26)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(progressColor.opacity(0.28), lineWidth: 1)
      )
      .shadow(color: progressColor.opacity(0.26), radius: 10, y: 2)
    }
  }

  private var progressColor: Color {
    let value = min(max(Double(board.completion) / 100, 0), 1)
    return Color(red: 1.0 - value * 0.78, green: 0.22 + value * 0.66, blue: 0.20 + value * 0.08)
  }
}

struct RecentStatusBadge: View {
  let status: String

  private var color: Color {
    switch status {
    case "Design":
      return Color(hex: 0xD85CFF)
    case "In Progress", "Active":
      return Color(hex: 0x2F8CFF)
    case "Completed", "Done", "Finished":
      return Color(hex: 0x35E177)
    default:
      return Color(hex: 0x8B4DFF)
    }
  }

  var body: some View {
    Text(status)
      .font(.system(size: 10, weight: .heavy))
      .foregroundStyle(color)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .frame(height: 21)
      .background(color.opacity(0.18))
      .clipShape(Capsule())
  }
}

struct RecentKindBadge: View {
  let title: String
  let color: Color

  var body: some View {
    Text(title)
      .font(.system(size: 10, weight: .heavy))
      .foregroundStyle(color)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .frame(height: 21)
      .background(color.opacity(0.16))
      .clipShape(Capsule())
  }
}

struct RecentBoardTypeChip: View {
  let boardType: BoardType
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      BoardTypeIcon(board: boardType, size: 18, overrideColor: color)
      Text(boardType.name)
        .font(.system(size: 11, weight: .black))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .background(color.opacity(0.13))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
  }
}

struct RecentBoardInfoChip: View {
  let symbol: String
  let text: String
  let color: Color

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .black))
      Text(text.isEmpty ? "-" : text)
        .font(.system(size: 11, weight: .black))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(color.opacity(0.12))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
  }
}

struct RecentManufacturerChip: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  private var name: String {
    let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
    return manufacturer?.name ?? (trimmed.isEmpty ? "Manufacturer" : trimmed)
  }

  var body: some View {
    ManufacturerMarkView(manufacturer: manufacturer, fallbackName: name, size: 22)
    .padding(.horizontal, 5)
    .padding(.vertical, 3)
    .background(color.opacity(0.13))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
    .accessibilityLabel(name)
  }
}

struct DueDateBadge: View {
  let date: Date
  var compact = false

  private var color: Color {
    dueUrgencyColor(for: date)
  }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "clock.badge.exclamationmark.fill")
        .font(.system(size: compact ? 9 : 11, weight: .black))
      Text(DateDisplay.due.string(from: date))
        .font(.system(size: compact ? 10 : 12, weight: .black))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .foregroundStyle(color)
    .padding(.horizontal, compact ? 8 : 10)
    .padding(.vertical, compact ? 4 : 6)
    .background(color.opacity(0.16))
    .clipShape(Capsule())
    .overlay(
      Capsule()
        .stroke(color.opacity(0.34), lineWidth: 1)
    )
    .shadow(color: color.opacity(0.22), radius: compact ? 4 : 7, y: 1)
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(2)
  }
}

struct BoardTypeIcon: View {
  let board: BoardType
  let size: CGFloat
  var overrideColor: Color? = nil

  private var iconColor: Color {
    overrideColor ?? board.color
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(iconColor.opacity(0.16))
      if let emoji = board.emoji, !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(emoji)
          .font(.system(size: size * 0.48, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      } else {
        Image(systemName: board.symbol)
          .font(.system(size: size * 0.48, weight: .bold))
          .foregroundStyle(iconColor)
      }
    }
    .frame(width: size, height: size)
  }
}

struct EquipmentBrandBadge: View {
  let name: String
  var image: UIImage? = nil

  /// The caller's logo, or the one bundled in `assets/catalog` for this brand.
  /// Resolved here rather than at each call site so every badge in the app
  /// picks up a newly added logo without another edit.
  private var resolvedImage: UIImage? {
    image ?? CatalogImageLibrary.manufacturerThumbnail(name: name)
  }

  var body: some View {
    Group {
      if let image = resolvedImage {
        TransparentImageBubble(
          image: image,
          width: 50,
          height: 50,
          cornerRadius: 12,
          glowColor: brandGlowColor
        )
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white)
          Text(name)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(brandColor)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 5)
        }
        .frame(width: 50, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .frame(width: 50, height: resolvedImage == nil ? 28 : 50)
  }

  private var brandGlowColor: Color {
    switch name {
    case "ABB": Color.red
    case "Schneider": Color(hex: 0x5F9F79)
    case "Siemens": Color(hex: 0x4F9AA8)
    default: Color(hex: 0x7FA6C9)
    }
  }

  private var brandColor: Color {
    switch name {
    case "ABB": Color.red
    case "Schneider": Color(hex: 0x5F9F79)
    case "Siemens": Color(hex: 0x4F9AA8)
    default: Color.black
    }
  }
}

struct EquipmentPill: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
  }
}

struct TransparentImageBubble: View {
  let image: UIImage
  let width: CGFloat
  let height: CGFloat
  var cornerRadius: CGFloat = 12
  let glowColor: Color

  var body: some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .padding(3)
      .frame(width: width, height: height)
      .shadow(color: glowColor.opacity(0.34), radius: 9, x: 0, y: 0)
      .shadow(color: glowColor.opacity(0.18), radius: 18, x: 0, y: 0)
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct PanelVaultLogoMark: View {
  let theme: PanelTheme
  let size: CGFloat

  var body: some View {
    Image(systemName: "bolt")
      .font(.system(size: size, weight: .regular))
      .foregroundStyle(theme.primary)
      .frame(width: size, height: size)
      .shadow(color: theme.primary.opacity(0.9), radius: size * 0.32)
      .shadow(color: theme.primary.opacity(0.55), radius: size * 0.7)
  }
}

struct ABBLogo: View {
  var body: some View {
    Text("ABB")
      .font(.system(size: 13, weight: .black))
      .foregroundStyle(.red)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(.white)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

struct ManufacturerLogoView: View {
  let manufacturer: ManufacturerItem

  /// A logo the user set on this device, else the one bundled for this brand.
  private var logo: UIImage? {
    manufacturer.thumbnail
      ?? CatalogImageLibrary.manufacturerThumbnail(name: manufacturer.name)
  }

  var body: some View {
    Group {
      if let image = logo {
        TransparentImageBubble(
          image: image,
          width: 54,
          height: 54,
          glowColor: manufacturer.color
        )
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(manufacturer.color.gradient)
          Text(manufacturer.initials)
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    }
    .frame(width: 54, height: 54)
  }
}

struct ManufacturerMarkView: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String
  let size: CGFloat

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  private var initials: String {
    if let manufacturer { return manufacturer.initials }
    let parts = fallbackName.split(separator: " ")
    let letters = parts.prefix(2).compactMap(\.first)
    return letters.isEmpty ? String(fallbackName.prefix(2)).uppercased() : String(letters).uppercased()
  }

  /// The brand's own logo where the mark is used for a known manufacturer, and
  /// the bundled catalog logo otherwise — including for the plain-name case,
  /// where a board records a brand nobody has added as a manufacturer yet.
  private var logo: UIImage? {
    manufacturer?.thumbnail
      ?? CatalogImageLibrary.manufacturerThumbnail(name: manufacturer?.name ?? fallbackName)
  }

  var body: some View {
    Group {
      if let image = logo {
        TransparentImageBubble(
          image: image,
          width: size,
          height: size,
          cornerRadius: max(size * 0.22, 5),
          glowColor: color
        )
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: max(size * 0.22, 5), style: .continuous)
            .fill(color.opacity(0.18))
          Text(initials)
            .font(.system(size: max(size * 0.34, 7), weight: .black))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .frame(width: size, height: size)
      }
    }
    .frame(width: size, height: size)
  }
}

struct ManufacturerInlineMark: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String

  private var name: String {
    manufacturer?.name ?? fallbackName
  }

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  var body: some View {
    HStack(spacing: 5) {
      ManufacturerMarkView(manufacturer: manufacturer, fallbackName: fallbackName, size: 18)
      Text(name)
        .font(.caption2.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(color.opacity(0.13))
    .clipShape(Capsule())
    .overlay(
      Capsule()
        .stroke(color.opacity(0.22), lineWidth: 1)
    )
  }
}

struct CompanyColorLogo: View {
  let color: Color
  let symbol: String

  var body: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(color.gradient)
      .frame(width: 44, height: 44)
      .overlay(
        Image(systemName: symbol)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
      )
  }
}

enum ComponentIcon {
  /// Order matters: the most specific match has to win first. "Power Analyzer"
  /// contains "power" and would otherwise draw the PSU plug, and a soft starter
  /// would otherwise share the VFD speedometer.
  static func symbol(for type: String) -> String {
    let lowered = type.lowercased()

    // Drives and motor control.
    if lowered.contains("vfd") || lowered.contains("drive") { return "speedometer" }
    if lowered.contains("soft starter") { return "chart.line.uptrend.xyaxis" }
    if lowered.contains("motor starter") { return "gearshape.fill" }
    if lowered.contains("mpcb") || lowered.contains("motor protection") { return "gearshape.2.fill" }
    if lowered.contains("overload") { return "thermometer.medium" }

    // Control power.
    if lowered.contains("ups") { return "battery.100percent.bolt" }
    if lowered.contains("psu") || lowered.contains("power supply") { return "powerplug.fill" }
    if lowered.contains("current transformer") { return "smallcircle.filled.circle.fill" }
    if lowered.contains("transformer") { return "square.stack.3d.up.fill" }

    // Protection and switching.
    if lowered.contains("rcbo") || lowered.contains("rccb") || lowered.contains("rcd") { return "waveform.path.ecg" }
    if lowered.contains("afdd") { return "flame.fill" }
    if lowered.contains("mcb") || lowered.contains("mccb") || lowered.contains("acb") || lowered.contains("breaker") { return "bolt.shield.fill" }
    if lowered.contains("spd") || lowered.contains("surge") { return "bolt.trianglebadge.exclamationmark.fill" }
    if lowered.contains("fuse") { return "bolt.horizontal.fill" }
    if lowered.contains("contactor") { return "switch.2" }
    if lowered.contains("ats controller") { return "arrow.left.arrow.right.circle.fill" }
    if lowered.contains("changeover") { return "arrow.left.arrow.right" }
    if lowered.contains("isolator") { return "power" }
    if lowered.contains("interlock") { return "lock.fill" }
    if lowered.contains("emergency stop") { return "exclamationmark.octagon.fill" }

    // Measurement, control and I/O.
    if lowered.contains("analyzer") { return "chart.xyaxis.line" }
    if lowered.contains("rcm") { return "magnifyingglass.circle.fill" }
    if lowered.contains("test block") { return "cable.connector" }
    if lowered.contains("meter") { return "gauge.with.dots.needle.67percent" }
    if lowered.contains("plc") { return "cpu.fill" }
    if lowered.contains("hmi") { return "display" }
    if lowered.contains("timer") { return "timer" }
    if lowered.contains("safety") { return "shield.lefthalf.filled" }
    if lowered.contains("monitoring") { return "waveform.path.ecg.rectangle.fill" }
    if lowered.contains("relay") { return "rectangle.connected.to.line.below" }
    if lowered.contains("button") || lowered.contains("selector") { return "button.programmable" }
    if lowered.contains("indicator") || lowered.contains("light") { return "lightbulb.fill" }

    // Power factor and quality.
    if lowered.contains("pfc") { return "slider.horizontal.3" }
    if lowered.contains("capacitor") { return "bolt.circle.fill" }
    if lowered.contains("reactor") { return "wave.3.right" }
    if lowered.contains("harmonic") || lowered.contains("filter") { return "waveform.path" }

    // Terminals, wiring and bars.
    if lowered.contains("distribution block") { return "arrow.triangle.branch" }
    if lowered.contains("terminal") { return "point.3.connected.trianglepath.dotted" }
    if lowered.contains("ferrule") { return "capsule.fill" }
    if lowered.contains("lug") { return "link" }
    if lowered.contains("marker") { return "tag.fill" }
    if lowered.contains("bonding") { return "point.bottomleft.forward.to.point.topright.scurvepath" }
    if lowered.contains("busbar") || lowered.contains("bar") { return "rectangle.grid.1x2.fill" }
    if lowered.contains("din rail") || lowered.contains("trunking") { return "rectangle.split.3x1.fill" }
    if lowered.contains("gland") { return "circle.circle.fill" }

    // Enclosure and climate.
    if lowered.contains("enclosure") { return "cabinet.fill" }
    if lowered.contains("cooling") { return "snowflake" }
    if lowered.contains("fan") { return "fan.fill" }
    if lowered.contains("heater") { return "thermometer.sun.fill" }
    if lowered.contains("hygrostat") { return "humidity.fill" }
    if lowered.contains("thermostat") { return "thermometer.medium" }
    if lowered.contains("socket") { return "poweroutlet.type.b.fill" }

    return "shippingbox.fill"
  }

  static func description(for component: PanelComponent) -> String {
    // Catalog parts carry their own text; fall back to the per-type blurb for
    // components the user created.
    let specific = component.about.trimmingCharacters(in: .whitespacesAndNewlines)
    if !specific.isEmpty { return specific }

    let type = component.type.lowercased()
    if type.contains("mcb") && !type.contains("mccb") {
      return "Miniature circuit breaker used for final circuit protection. Choose poles, curve and ampere rating to match the connected circuit."
    }
    if type.contains("mccb") {
      return "Molded case circuit breaker for higher-current feeders, main breakers and distribution protection. Check frame size, trip unit and breaking capacity."
    }
    if type.contains("rcbo") {
      return "Combined overcurrent and residual-current protection, commonly used when a circuit needs both MCB and RCD protection in one device."
    }
    if type.contains("contactor") {
      return "Electrically operated switching device for motors, lighting banks and controlled loads. Confirm AC duty, coil voltage and auxiliary contacts."
    }
    if type.contains("vfd") {
      return "Variable frequency drive for speed control of motors. Check kW rating, supply voltage, ventilation and EMC requirements."
    }
    if type.contains("soft starter") {
      return "Ramps a motor up and down to limit inrush current and mechanical shock. Check motor kW, start duty cycle, whether a bypass is built in, and whether an isolator and overload are still needed upstream."
    }
    if type.contains("mpcb") {
      return "Manual motor starter combining short-circuit and adjustable overload protection in one device. Set the current dial to the motor full-load amps and check the breaking capacity for the fault level."
    }
    if type.contains("overload") {
      return "Protects a motor from sustained overcurrent. Match the setting range to motor full-load amps, confirm the trip class against start-up time, and check it pairs with the chosen contactor."
    }
    if type.contains("dc-ups") || (type.contains("ups") && !type.contains("psu")) {
      return "Keeps 24VDC control power alive through dips and outages. Check hold-up time at the actual load, battery or capacitor type, and where the alarm contact is wired."
    }
    if type.contains("psu") {
      return "Power supply for control circuits, sensors, PLCs and relays. Check output voltage, current and spare capacity."
    }
    if type.contains("busbar") {
      return "Copper or distribution bar used to carry current between sections or devices. Check current rating, spacing, supports and insulation."
    }
    return "Catalog component used inside the board. Confirm manufacturer data, model, rating, poles/phase and project-specific installation notes."
  }
}

struct ComponentSummaryCard: View {
  let theme: PanelTheme
  let component: PanelComponent
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        Image(systemName: ComponentIcon.symbol(for: component.type))
          .foregroundStyle(color)
          .frame(width: 40, height: 40)
          .background(color.opacity(0.14))
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 4) {
          Text(component.displayName)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
          Text(component.detailLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        Spacer()
      }
    }
  }
}
