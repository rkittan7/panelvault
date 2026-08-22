// Ported from warehouse/Sources by tools/port_warehouse.py so the worker app
// carries the warehouse itself. The standalone warehouse app is unchanged;
// see worker/README.md for how the two relate.

import SwiftUI

struct AccountView: View {
  let theme: PanelTheme
  @EnvironmentObject private var store: WarehouseStore

  @State private var server = UserDefaults.standard.string(forKey: "warehouse.cloudServer") ?? ""
  @State private var companyCode = ""
  @State private var companyName = ""
  @State private var inviteCode = ""
  @State private var name = ""
  @State private var password = ""
  @State private var isConnecting = false
  @State private var message = ""
  @FocusState private var focusedField: Field?

  @State private var mode: AccountMode = .signIn

  private enum Field { case server, company, companyName, invite, name, password }
  private enum AccountMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case create = "Create"
    case join = "Join"
    var id: String { rawValue }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let account = store.account {
            connectedView(account)
          } else {
            signInView
          }
        }
        .padding(18)
        .padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("PanelVault Cloud")
    }
  }

  private var signInView: some View {
    VStack(alignment: .leading, spacing: 18) {
      GlassCard(theme: theme) {
        HStack(spacing: 14) {
          Image(systemName: "icloud.and.arrow.up.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(theme.secondary)
            .frame(width: 46, height: 46)
            .background(theme.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          VStack(alignment: .leading, spacing: 3) {
            Text("Connect this warehouse")
              .font(.headline.weight(.heavy))
            Text("Stock movements stay on this phone until they are safely uploaded.")
              .font(.subheadline)
              .foregroundStyle(theme.mutedText)
          }
        }
      }

      Picker("Account action", selection: $mode) {
        ForEach(AccountMode.allCases) { option in
          Text(option.rawValue).tag(option)
        }
      }
      .pickerStyle(.segmented)

      SectionHeading(title: "Workspace")
      VStack(spacing: 1) {
        cloudField("Server address", text: $server, symbol: "network", field: .server)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .autocorrectionDisabled()
        switch mode {
        case .signIn:
          cloudField("Company code", text: $companyCode, symbol: "building.2.fill", field: .company)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        case .create:
          cloudField("Company name", text: $companyName, symbol: "building.2.crop.circle.fill", field: .companyName)
            .textContentType(.organizationName)
        case .join:
          cloudField("Company code (optional with full link)", text: $companyCode, symbol: "building.2.fill", field: .company)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
          cloudField("Paste invite link or code", text: $inviteCode, symbol: "link", field: .invite)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        cloudField("Your name", text: $name, symbol: "person.fill", field: .name)
          .textContentType(.username)
        cloudField("Password", text: $password, symbol: "lock.fill", field: .password, secure: true)
          .textContentType(.password)
      }
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))

      if !message.isEmpty {
        Label(message, systemImage: "exclamationmark.circle.fill")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(theme.negative)
      }

      Button(action: submit) {
        HStack(spacing: 9) {
          if isConnecting { ProgressView().tint(.white) }
          Text(isConnecting ? "Connecting" : submitTitle)
          if !isConnecting { Image(systemName: "arrow.right") }
        }
        .font(.headline.weight(.bold))
        .frame(maxWidth: .infinity)
        .frame(height: 52)
      }
      .buttonStyle(.borderedProminent)
      .tint(theme.primary)
      .disabled(!canSubmit || isConnecting)
    }
  }

  private func connectedView(_ account: WarehouseCloudAccount) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      GlassCard(theme: theme) {
        HStack(spacing: 14) {
          ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .fill(theme.positive.opacity(0.14))
            Image(systemName: "checkmark.icloud.fill")
              .font(.system(size: 27, weight: .semibold))
              .foregroundStyle(theme.positive)
          }
          .frame(width: 50, height: 50)
          VStack(alignment: .leading, spacing: 3) {
            Text(account.companyName)
              .font(.title3.weight(.heavy))
            Text("\(account.userName)  ·  \(account.role.capitalized)")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(theme.mutedText)
          }
        }
      }

      SectionHeading(title: "Sync")
      GlassCard(theme: theme) {
        VStack(spacing: 14) {
          HStack {
            Label(store.syncPhase.title, systemImage: syncSymbol)
              .font(.headline.weight(.bold))
              .foregroundStyle(syncColor)
            Spacer()
            if store.syncPhase == .syncing { ProgressView().tint(theme.secondary) }
          }
          Divider().overlay(Color.white.opacity(0.08))
          HStack {
            Text("Waiting to upload")
              .foregroundStyle(theme.mutedText)
            Spacer()
            Text("\(store.pendingMovementCount)")
              .font(.headline.weight(.black))
          }
          if case .failed(let detail) = store.syncPhase {
            Text(detail)
              .font(.footnote.weight(.semibold))
              .foregroundStyle(theme.negative)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }

      Button {
        Task { await store.sync() }
      } label: {
        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
          .font(.headline.weight(.bold))
          .frame(maxWidth: .infinity)
          .frame(height: 48)
      }
      .buttonStyle(.borderedProminent)
      .tint(theme.primary)
      .disabled(store.syncPhase == .syncing)

      Button(role: .destructive) {
        store.signOut()
      } label: {
        Text("Disconnect This Phone")
          .font(.headline.weight(.bold))
          .frame(maxWidth: .infinity)
          .frame(height: 46)
      }
      .buttonStyle(.bordered)
    }
  }

  @ViewBuilder
  private func cloudField(
    _ prompt: String,
    text: Binding<String>,
    symbol: String,
    field: Field,
    secure: Bool = false
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(theme.secondary)
        .frame(width: 22)
      if secure {
        SecureField(prompt, text: text)
          .focused($focusedField, equals: field)
      } else {
        TextField(prompt, text: text)
          .focused($focusedField, equals: field)
      }
    }
    .font(.body.weight(.semibold))
    .padding(.horizontal, 15)
    .frame(height: 54)
    .background(theme.surface)
  }

  private var canSubmit: Bool {
    let common = !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && password.count >= 6
    switch mode {
    case .signIn:
      return common && !companyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .create:
      return common && !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .join:
      return common && !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var submitTitle: String {
    switch mode {
    case .signIn: return "Sign In"
    case .create: return "Create Company"
    case .join: return "Join Company"
    }
  }

  private var syncSymbol: String {
    switch store.syncPhase {
    case .signedOut: return "icloud.slash.fill"
    case .idle: return "checkmark.icloud.fill"
    case .syncing: return "arrow.triangle.2.circlepath.icloud.fill"
    case .failed: return "exclamationmark.icloud.fill"
    }
  }

  private var syncColor: Color {
    switch store.syncPhase {
    case .signedOut: return theme.mutedText
    case .idle: return theme.positive
    case .syncing: return theme.secondary
    case .failed: return theme.negative
    }
  }

  private func submit() {
    focusedField = nil
    message = ""
    isConnecting = true
    let address = server.trimmingCharacters(in: .whitespacesAndNewlines)
    UserDefaults.standard.set(address, forKey: "warehouse.cloudServer")
    Task {
      do {
        switch mode {
        case .signIn:
          try await store.signIn(
            baseURL: address,
            companyCode: companyCode.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
          )
        case .create:
          try await store.createCompany(
            baseURL: address,
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
          )
        case .join:
          try await store.joinCompany(
            baseURL: address,
            companyCode: companyCode.trimmingCharacters(in: .whitespacesAndNewlines),
            inviteCode: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
          )
        }
        password = ""
      } catch {
        message = error.localizedDescription
      }
      isConnecting = false
    }
  }
}
