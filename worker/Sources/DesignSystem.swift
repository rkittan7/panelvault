// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

struct TabBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .opacity(configuration.isPressed ? 0.86 : 1)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }
}

struct BottomTabClearance: View {
  var height: CGFloat = 96

  var body: some View {
    Color.clear
      .frame(height: height)
      .allowsHitTesting(false)
  }
}

struct PanelPressButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.992 : 1)
      .opacity(configuration.isPressed ? 0.97 : 1)
      .shadow(color: .black.opacity(configuration.isPressed ? 0.08 : 0.12), radius: configuration.isPressed ? 2 : 4, y: configuration.isPressed ? 1 : 2)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct PanelToggleStyle: ToggleStyle {
  let theme: PanelTheme

  func makeBody(configuration: Configuration) -> some View {
    Button {
      withAnimation(.easeOut(duration: 0.16)) {
        configuration.isOn.toggle()
      }
    } label: {
      HStack {
        configuration.label
        Spacer()
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
          Capsule()
            .fill(configuration.isOn ? theme.primary.opacity(0.95) : Color.primary.opacity(0.16))
            .frame(width: 50, height: 30)
          Circle()
            .fill(.white)
            .frame(width: 24, height: 24)
            .padding(3)
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

struct GlassCard<Content: View>: View {
  let theme: PanelTheme
  /// The ported warehouse screens pack denser cards than PanelVault's, so the
  /// inset is a parameter here. Defaults to PanelVault's 14.
  var padding: CGFloat = 14
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(padding)
      .background(theme.surface.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
          .stroke(theme.cardBorder, lineWidth: 1)
      )
  }
}

struct TopScrollBlur: View {
  let theme: PanelTheme

  var body: some View {
    Rectangle()
      .fill(
        LinearGradient(
          stops: [
            .init(color: theme.background.opacity(0.98), location: 0),
            .init(color: theme.background.opacity(0.82), location: 0.34),
            .init(color: theme.background.opacity(0.36), location: 0.72),
            .init(color: .clear, location: 1)
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .frame(height: 58)
      .ignoresSafeArea(edges: .top)
      .allowsHitTesting(false)
  }
}

struct EmptyStateCard: View {
  let theme: PanelTheme
  let title: String
  let subtitle: String

  var body: some View {
    GlassCard(theme: theme) {
      VStack(spacing: 8) {
        Image(systemName: "tray")
          .font(.title2)
          .foregroundStyle(.secondary)
        Text(title)
          .font(.headline)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
    }
  }
}

struct ViewAllInlineButton: View {
  let theme: PanelTheme
  let title: String
  let action: () -> Void

  var body: some View {
    HStack {
      Spacer()
      Button(action: action) {
        HStack(spacing: 7) {
          Text(title)
          Image(systemName: "arrow.up.right")
            .font(.system(size: 11, weight: .black))
        }
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
          LinearGradient(
            colors: [theme.primary.opacity(0.92), theme.secondary.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
        .clipShape(Capsule())
        .overlay(
          Capsule()
            .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: theme.primary.opacity(0.24), radius: 12, y: 4)
      .buttonStyle(PanelPressButtonStyle())
      Spacer()
    }
    .padding(.top, 2)
  }
}

struct InfoLine: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .fontWeight(.semibold)
        .multilineTextAlignment(.trailing)
    }
  }
}

struct SimpleListRow: Identifiable {
  let id = UUID()
  let symbol: String
  let title: String
  let subtitle: String
  let color: Color
}

struct SimpleListSheet: View {
  let theme: PanelTheme
  let title: String
  let rows: [SimpleListRow]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          if rows.isEmpty {
            EmptyStateCard(theme: theme, title: "Nothing here yet", subtitle: "Create a project or board and this list will fill in.")
          }
          ForEach(rows) { row in
            GlassCard(theme: theme) {
              HStack(spacing: 12) {
                Image(systemName: row.symbol)
                  .foregroundStyle(row.color)
                  .frame(width: 40, height: 40)
                  .background(row.color.opacity(0.14))
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                  Text(row.title).font(.headline)
                  if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                  }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct MoreRow: View {
  let theme: PanelTheme
  let symbol: String
  let title: String
  let subtitle: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(theme.primary)
        .frame(width: 38, height: 38)
        .background(theme.primary.opacity(0.14))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right").foregroundStyle(.secondary)
    }
    .padding(12)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
  }
}

struct PickerLikeRow: View {
  let title: String
  let value: String
  let color: Color

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      Text(value)
        .fontWeight(.bold)
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Image(systemName: "chevron.down")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
  }
}

struct BoardReferenceSection<Content: View>: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let color: Color
  @ViewBuilder let content: Content

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
          Text(title)
            .font(.headline)
        }
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct BoardBulletList: View {
  let items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(items, id: \.self) { item in
        HStack(alignment: .top, spacing: 8) {
          Circle()
            .fill(.secondary)
            .frame(width: 5, height: 5)
            .padding(.top, 7)
          Text(item)
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

struct DeleteIconButton: View {
  let theme: PanelTheme
  let action: () -> Void
  @State private var confirmingDelete = false

  var body: some View {
    Menu {
      Button(role: .destructive) {
        confirmingDelete = true
      } label: {
        Label("Delete", systemImage: "trash")
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 30, height: 30)
        .background(theme.surface.opacity(0.85))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete", role: .destructive, action: action)
      Button("Cancel", role: .cancel) {}
    }
  }
}
