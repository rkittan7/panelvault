import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    let window = UIWindow(windowScene: windowScene)
    let hostingController = UIHostingController(rootView: PanelVaultAppView())
    hostingController.view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    window.rootViewController = hostingController
    window.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    self.window = window
    window.makeKeyAndVisible()
  }
}

struct PanelVaultAppView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedTab: PanelTab = .dashboard
  @State private var searchQuery = ""
  @State private var archiveQuery = ""
  @State private var archiveBoardTypeFilter = "All"
  @State private var archiveStatusFilter = "All"
  @State private var projects: [ProjectItem] = []
  @State private var createdBoards: [BoardDraft] = []
  @State private var boardTypes: [BoardType] = BoardType.samples
  @State private var contractorCompanies: [ContractorCompany] = []
  @State private var customers: [CustomerItem] = []
  @State private var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  @State private var recentVisits: [RecentVisit] = []
  @State private var archiveMode: ArchiveMode = .projects
  @State private var newHubSelection: NewHubSelection?
  @State private var pendingProjectOpenID: String?
  @AppStorage("panelvault.theme") private var selectedThemeID = PanelTheme.vaultPurple.id
  @AppStorage("panelvault.interfaceSize") private var selectedInterfaceSizeID = InterfaceSize.standard.id
  @AppStorage("panelvault.standardSizeMigration") private var standardSizeMigration = false
  @AppStorage("panelvault.contractorMode") private var contractorMode = false
  @AppStorage("panelvault.activeCompany") private var activeCompanyID = ""
  @AppStorage("panelvault.savedSnapshot") private var savedSnapshot = ""
  @AppStorage("panelvault.profileName") private var profileName = ""
  @AppStorage("panelvault.profileCompany") private var profileCompany = ""
  @AppStorage("panelvault.profilePhone") private var profilePhone = ""
  @State private var loadedSnapshot = false
  @State private var pendingPersistWorkItem: DispatchWorkItem?

  private var selectedTheme: PanelTheme {
    PanelTheme.all.first { $0.id == selectedThemeID } ?? .vaultPurple
  }

  private var activeCompany: Binding<ContractorCompany?> {
    Binding {
      contractorCompanies.first { $0.id == activeCompanyID }
    } set: { company in
      activeCompanyID = company?.id ?? ""
    }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      selectedTheme.background.ignoresSafeArea()
      selectedTabContent

      PanelVaultTabBar(theme: selectedTheme, selectedTab: $selectedTab)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .tint(selectedTheme.primary)
    .preferredColorScheme(.dark)
    .onAppear {
      if !standardSizeMigration {
        selectedInterfaceSizeID = InterfaceSize.standard.id
        standardSizeMigration = true
      }
      loadSnapshotIfNeeded()
    }
    .onChange(of: scenePhase) { phase in
      if phase != .active {
        persistSnapshot()
      }
    }
    .onChange(of: projectPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: boardPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: customerPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: companyPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
    .onChange(of: manufacturerPersistenceSignature) { _ in
      schedulePersistSnapshot()
    }
  }

  @ViewBuilder
  private var selectedTabContent: some View {
    switch selectedTab {
    case .dashboard:
      DashboardView(
        theme: selectedTheme,
        interfaceSize: InterfaceSize.option(for: selectedInterfaceSizeID),
        contractorMode: contractorMode,
        selectedTab: $selectedTab,
        archiveMode: $archiveMode,
        searchQuery: $searchQuery,
        archiveQuery: $archiveQuery,
        archiveBoardTypeFilter: $archiveBoardTypeFilter,
        archiveStatusFilter: $archiveStatusFilter,
        projects: $projects,
        boardCount: createdBoards.count,
        boards: $createdBoards,
        boardTypes: boardTypes,
        customers: customers,
        manufacturers: manufacturers,
        profileName: profileName,
        newHubSelection: $newHubSelection,
        activeCompany: activeCompany,
        companies: $contractorCompanies,
        recentVisits: $recentVisits
      )
    case .projects:
      ProjectsView(
        theme: selectedTheme,
        projects: $projects,
        boards: $createdBoards,
        archiveMode: $archiveMode,
        archiveQuery: $archiveQuery,
        archiveBoardTypeFilter: $archiveBoardTypeFilter,
        archiveStatusFilter: $archiveStatusFilter,
        boardTypes: boardTypes,
        customers: customers,
        manufacturers: manufacturers,
        selectedTab: $selectedTab,
        newHubSelection: $newHubSelection,
        pendingProjectOpenID: $pendingProjectOpenID,
        recentVisits: $recentVisits
      )
    case .newBoard:
      NewHubView(
        theme: selectedTheme,
        projects: $projects,
        boards: $createdBoards,
        customers: customers,
        companies: contractorCompanies,
        manufacturers: manufacturers,
        boardTypes: boardTypes,
        selection: $newHubSelection,
        onCreateBoard: { board in
          createdBoards.insert(board, at: 0)
          let trimmedCustomer = board.customer.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmedCustomer.isEmpty && !customers.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmedCustomer) == .orderedSame }) {
            customers.insert(CustomerItem(name: trimmedCustomer), at: 0)
          }
          persistSnapshot()
        },
        onUpdateBoard: { updatedBoard in
          if let index = createdBoards.firstIndex(where: { $0.id == updatedBoard.id }) {
            createdBoards[index] = updatedBoard
            persistSnapshot()
          }
        },
        onCreateProject: { project in
          projects.insert(project, at: 0)
          pendingProjectOpenID = project.id
          archiveMode = .projects
          archiveStatusFilter = "All"
          archiveBoardTypeFilter = "All"
          selectedTab = .projects
          newHubSelection = nil
          DispatchQueue.main.async {
            persistSnapshot()
          }
        }
      )
    case .search:
      SearchView(theme: selectedTheme, query: $searchQuery, projects: $projects, boards: $createdBoards, boardTypes: boardTypes, manufacturers: manufacturers, recentVisits: $recentVisits)
    case .more:
      MoreView(
        theme: selectedTheme,
        selectedThemeID: $selectedThemeID,
        selectedInterfaceSizeID: $selectedInterfaceSizeID,
        contractorMode: $contractorMode,
        projects: projects,
        boards: $createdBoards,
        customers: $customers,
        manufacturers: $manufacturers,
        boardTypes: $boardTypes,
        profileName: $profileName,
        profileCompany: $profileCompany,
        profilePhone: $profilePhone,
        activeCompany: activeCompany,
        companies: $contractorCompanies
      )
    }
  }

  private func loadSnapshotIfNeeded() {
    guard !loadedSnapshot else { return }
    loadedSnapshot = true
    guard let snapshot = PanelVaultSnapshot.decode(savedSnapshot) else { return }
    projects = snapshot.projects.map(\.project)
    createdBoards = snapshot.boards.map(\.board)
    customers = snapshot.customers.map(\.customer)
    if let savedCompanies = snapshot.companies {
      contractorCompanies = savedCompanies.map(\.company)
    }
    if let savedManufacturers = snapshot.manufacturers {
      manufacturers = savedManufacturers.map(\.manufacturer)
    }
  }

  private func persistSnapshot() {
    pendingPersistWorkItem?.cancel()
    pendingPersistWorkItem = nil
    savedSnapshot = PanelVaultSnapshot(projects: projects, boards: createdBoards, customers: customers, companies: contractorCompanies, manufacturers: manufacturers).encoded()
  }

  private func schedulePersistSnapshot() {
    guard loadedSnapshot else { return }
    pendingPersistWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      persistSnapshot()
    }
    pendingPersistWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
  }

  private var projectPersistenceSignature: String {
    projects.map(\.persistenceSignature).joined(separator: "||")
  }

  private var boardPersistenceSignature: String {
    createdBoards.map(\.persistenceSignature).joined(separator: "||")
  }

  private var customerPersistenceSignature: String {
    customers.map(\.persistenceSignature).joined(separator: "||")
  }

  private var companyPersistenceSignature: String {
    contractorCompanies.map(\.persistenceSignature).joined(separator: "||")
  }

  private var manufacturerPersistenceSignature: String {
    manufacturers.map(\.persistenceSignature).joined(separator: "||")
  }
}

enum PanelTab: String, CaseIterable, Identifiable {
  case dashboard
  case projects
  case newBoard
  case search
  case more

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .dashboard: return "house"
    case .projects: return "folder"
    case .newBoard: return "plus"
    case .search: return "magnifyingglass"
    case .more: return "ellipsis"
    }
  }
}

struct PanelVaultTabBar: View {
  let theme: PanelTheme
  @Binding var selectedTab: PanelTab

  var body: some View {
    HStack {
      HStack(spacing: 4) {
        ForEach(PanelTab.allCases) { tab in
          Button {
            guard selectedTab != tab else { return }
            withAnimation(.easeOut(duration: 0.12)) {
              selectedTab = tab
            }
          } label: {
            ZStack {
              if selectedTab == tab {
                Capsule(style: .continuous)
                  .fill(
                    LinearGradient(
                      colors: [theme.primary.opacity(0.24), theme.secondary.opacity(0.14)],
                      startPoint: .topLeading,
                      endPoint: .bottomTrailing
                    )
                  )
                  .overlay(
                    Capsule(style: .continuous)
                      .stroke(theme.primary.opacity(0.24), lineWidth: 1)
                  )
              }

              Image(systemName: tab.iconName)
                .font(.system(size: tab == .newBoard ? 23 : 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selectedTab == tab ? theme.primary.opacity(1) : Color.white.opacity(0.78))
                .scaleEffect(selectedTab == tab ? 1.03 : 1)
            }
            .frame(width: 62, height: 50)
            .contentShape(Rectangle())
          }
          .buttonStyle(TabBarButtonStyle())
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        Capsule(style: .continuous)
          .fill(.black.opacity(0.76))
          .overlay(
            Capsule(style: .continuous)
              .fill(.black.opacity(0.58))
          )
          .overlay(
            Capsule(style: .continuous)
              .fill(
                LinearGradient(
                  colors: [.black.opacity(0.20), .black.opacity(0.44)],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
          )
          .overlay(
            Capsule(style: .continuous)
              .stroke(.white.opacity(0.08), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 8)
      )
      .frame(maxWidth: 388)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 12)
    .padding(.top, 4)
    .padding(.bottom, 0)
    .offset(y: 18)
  }
}

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

enum DateDisplay {
  static let short: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  static let due: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("d MMM")
    formatter.timeStyle = .none
    return formatter
  }()
}

private func dueDateComesFirst(_ left: Date?, _ right: Date?) -> Bool? {
  switch (left, right) {
  case let (left?, right?):
    guard abs(left.timeIntervalSince1970 - right.timeIntervalSince1970) > 1 else { return nil }
    return left < right
  case (_?, nil):
    return true
  case (nil, _?):
    return false
  default:
    return nil
  }
}

private func activeBoardPrioritySort(_ left: BoardDraft, _ right: BoardDraft) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  if left.completion != right.completion { return left.completion > right.completion }
  return left.name < right.name
}

private func boardPrioritySort(_ left: BoardDraft, _ right: BoardDraft) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  if left.isCompleted != right.isCompleted { return !left.isCompleted && right.isCompleted }
  if left.completion != right.completion { return left.completion > right.completion }
  return left.name < right.name
}

private func projectPrioritySort(_ left: ProjectItem, _ right: ProjectItem) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  return left.name < right.name
}

private func syncedManufacturer(named name: String, in manufacturers: [ManufacturerItem]) -> ManufacturerItem? {
  manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ??
    ManufacturerItem.defaults.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
}

private func dueUrgencyColor(for date: Date) -> Color {
  let hours = date.timeIntervalSince(Date()) / 3600
  if hours <= 0 { return Color(hex: 0xFF453A) }
  let days = min(max(hours / 24, 0), 14)
  let urgency = 1 - (days / 14)
  let red = 0.20 + (urgency * 0.80)
  let green = 0.86 - (urgency * 0.58)
  let blue = 0.34 - (urgency * 0.18)
  return Color(red: red, green: green, blue: blue)
}

struct DashboardView: View {
  let theme: PanelTheme
  let interfaceSize: InterfaceSize
  let contractorMode: Bool
  @Binding var selectedTab: PanelTab
  @Binding var archiveMode: ArchiveMode
  @Binding var searchQuery: String
  @Binding var archiveQuery: String
  @Binding var archiveBoardTypeFilter: String
  @Binding var archiveStatusFilter: String
  @Binding var projects: [ProjectItem]
  let boardCount: Int
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let customers: [CustomerItem]
  let manufacturers: [ManufacturerItem]
  let profileName: String
  @Binding var newHubSelection: NewHubSelection?
  @Binding var activeCompany: ContractorCompany?
  @Binding var companies: [ContractorCompany]
  @Binding var recentVisits: [RecentVisit]
  @State private var companySheetOpen = false
  @State private var dashboardSheet: DashboardSheet?
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoardID: String?

  var title: String {
    guard contractorMode else { return "PanelVault" }
    return activeCompany?.name ?? "All Companies"
  }

  var subtitle: String {
    guard contractorMode else { return "" }
    return activeCompany == nil ? "Every company in PanelVault" : "Contractor workspace"
  }

  private var dashboardStats: [PanelStat] {
    [
      PanelStat(id: "projects", title: "Projects", value: "\(projects.count)", symbol: "folder.fill", color: theme.primary),
      PanelStat(id: "boards", title: "Boards", value: "\(boardCount)", symbol: "rectangle.3.group.fill", color: theme.secondary),
      PanelStat(id: "active-projects", title: "Active Projects", value: "\(activeProjectDashboardCount)", symbol: "clock.fill", color: theme.primary.opacity(0.82)),
      PanelStat(id: "active-boards", title: "Boards Active", value: "\(activeBoardDashboardCount)", symbol: "checklist", color: theme.secondary.opacity(0.9))
    ]
  }

  private var activeProjects: [ProjectItem] {
    projects.filter { ["In Progress", "Design"].contains(projectStatus($0)) }
      .sorted(by: projectPrioritySort)
      .prefix(3)
      .map { $0 }
  }

  private var activeBoards: [BoardDraft] {
    boards
      .filter { !$0.isCompleted }
      .sorted(by: activeBoardPrioritySort)
      .prefix(3)
      .map { $0 }
  }

  private var activeProjectDashboardCount: Int {
    projects.filter { ["In Progress", "Design"].contains(projectStatus($0)) }.count
  }

  private var activeBoardDashboardCount: Int {
    boards.filter { !$0.isCompleted }.count
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    let timeGreeting: String
    switch hour {
    case 5..<12:
      timeGreeting = "good morning"
    case 12..<18:
      timeGreeting = "good afternoon"
    case 18..<22:
      timeGreeting = "good evening"
    default:
      timeGreeting = "good night"
    }
    let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstName = trimmedName.split(separator: " ").first.map(String.init) ?? ""
    return firstName.isEmpty ? timeGreeting.capitalized : "Hey \(firstName), \(timeGreeting)!"
  }

  private var sortedBoardTypes: [BoardType] {
    Array(boardTypes
      .filter { boardCount(for: $0) > 0 }
      .sorted {
        let leftCount = boardCount(for: $0)
        let rightCount = boardCount(for: $1)
        if leftCount == rightCount { return $0.name < $1.name }
        return leftCount > rightCount
      }
      .prefix(6))
  }

  private var visibleRecentVisits: [RecentVisit] {
    recentVisits.filter { visit in
      switch visit.kind {
      case .project:
        return projects.contains { $0.id == visit.itemID }
      case .board:
        return boards.contains { $0.id == visit.itemID }
      }
    }
    .prefix(3)
    .map { $0 }
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(spacing: interfaceSize.dashboardSpacing) {
          header
          statsGrid
          greetingHeader
          sectionHeader("Boards", count: activeBoardDashboardCount) {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .boards
            selectedTab = .projects
          }
          activeBoardsList
          sectionHeader("Projects", count: activeProjectDashboardCount) {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .projects
            selectedTab = .projects
          }
          activeProjectsList
          sectionHeader("Board Types") {
            dashboardSheet = .boardTypes
          }
          boardTypesGrid
          quickSearch
          sectionHeader("Recents") {
            archiveQuery = ""
            selectedTab = .search
          }
          recentsList
          BottomTabClearance()
        }
        .padding(.horizontal, interfaceSize.dashboardPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .sheet(isPresented: $companySheetOpen) {
        CompanySwitcherSheet(
          theme: theme,
          activeCompany: $activeCompany,
          companies: companies
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
      }
      .sheet(item: $dashboardSheet) { sheet in
        switch sheet {
        case .boardTypes:
          BoardTypesSheet(theme: theme, boardTypes: boardTypes)
        case .recentProjects:
          ProjectsListSheet(theme: theme, projects: $projects, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers)
        case .stats:
          DashboardStatsSheet(theme: theme, projects: projects, boardCount: boardCount)
        case .companies:
          CompanyManagerSheet(
            theme: theme,
            companies: $companies,
            activeCompany: $activeCompany,
            projects: projects,
            boards: $boards,
            boardTypes: boardTypes,
            manufacturers: manufacturers
          )
        case .customers:
          SimpleListSheet(
            theme: theme,
            title: "Customers",
            rows: uniqueCustomers.map { SimpleListRow(symbol: "person.crop.circle", title: $0, subtitle: "", color: theme.primary) }
          )
        case .newProject:
          NewProjectSheet(theme: theme, boards: $boards, customers: customers, projectCustomers: uniqueCustomers) { project in
            projects.insert(project, at: 0)
          }
        }
      }
    }
    .sheet(item: $selectedProject) { project in
          ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
        remember(.board, id: board.id)
      } onUpdateProject: { updatedProject, previousName in
        if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
          projects[index] = updatedProject
        }
        for index in boards.indices where boards[index].project == previousName {
          boards[index].project = updatedProject.name
        }
      } onDeleteProject: {
        deleteProject(project)
        selectedProject = nil
      }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .sheet(item: selectedBoardBinding) { boardID in
      if let index = boards.firstIndex(where: { $0.id == boardID.id }) {
        NavigationStack {
          CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
            deleteBoard(id: boardID.id)
            selectedBoardID = nil
          }) {
            selectedBoardID = nil
          }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }

  private func linkedBoards(for project: ProjectItem) -> [BoardDraft] {
    boards.filter { $0.project == project.name }
  }

  private func projectStatus(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    guard !linked.isEmpty else { return project.status }
    return linked.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  private func boardCount(for boardType: BoardType) -> Int {
    boards.filter { $0.type == boardType.name }.count
  }

  private func remember(_ kind: RecentVisit.Kind, id: String) {
    recentVisits.removeAll { $0.kind == kind && $0.itemID == id }
    recentVisits.insert(RecentVisit(kind: kind, id: id), at: 0)
    recentVisits = Array(recentVisits.prefix(12))
  }

  private func deleteProject(_ project: ProjectItem) {
    projects.removeAll { $0.id == project.id }
    for index in boards.indices where boards[index].project == project.name {
      boards[index].project = "No Project"
    }
    recentVisits.removeAll { $0.kind == .project && $0.itemID == project.id }
  }

  private func deleteBoard(id: String) {
    boards.removeAll { $0.id == id }
    recentVisits.removeAll { $0.kind == .board && $0.itemID == id }
  }

  private var selectedBoardBinding: Binding<RecentBoardSelection?> {
    Binding {
      selectedBoardID.map(RecentBoardSelection.init(id:))
    } set: { selection in
      selectedBoardID = selection?.id
    }
  }

  var header: some View {
    HStack(spacing: 14) {
      if contractorMode {
        Button {
          companySheetOpen = true
        } label: {
          Image(systemName: "line.3.horizontal")
            .font(.system(size: 19, weight: .semibold))
            .frame(width: 38, height: 38)
            .background(theme.surface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
      }

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 10) {
          PanelVaultLogoMark(theme: theme, size: interfaceSize.logoSize)
          Text(title)
            .font(.system(size: interfaceSize.titleSize, weight: .heavy))
            .lineLimit(1)
        }

        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      Menu {
        Button {
          newHubSelection = .board
          selectedTab = .newBoard
        } label: {
          Label("New Board", systemImage: "rectangle.3.group.fill")
        }

        Button {
          newHubSelection = .project
          selectedTab = .newBoard
        } label: {
          Label("New Project", systemImage: "folder.badge.plus")
        }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "plus")
            .font(.system(size: 12, weight: .black))
          Text("New")
            .font(.system(size: 13, weight: .heavy))
          Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .black))
            .opacity(0.9)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(theme.primary)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: theme.primary.opacity(0.28), radius: 12, y: 5)
      }
      .buttonStyle(PanelPressButtonStyle())
    }
  }

  var greetingHeader: some View {
    HStack {
      Text(greeting)
        .font(.system(size: 30, weight: .heavy))
        .foregroundStyle(.primary)
        .minimumScaleFactor(0.78)
      Spacer()
    }
    .padding(.top, 2)
  }

  var statsGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
      ForEach(dashboardStats) { stat in
        Button {
          if stat.id == "projects" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "All"
            archiveMode = .projects
            selectedTab = .projects
          } else if stat.id == "boards" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "All"
            archiveMode = .boards
            selectedTab = .projects
          } else if stat.id == "active-projects" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .projects
            selectedTab = .projects
          } else if stat.id == "active-boards" {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .boards
            selectedTab = .projects
          } else {
            dashboardSheet = .stats
          }
        } label: {
          GlassCard(theme: theme) {
            VStack(spacing: 7) {
              Image(systemName: stat.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(stat.color)
                .frame(width: 34, height: 34)
                .background(stat.color.opacity(0.14))
                .clipShape(Circle())
              Text(stat.value)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(stat.color)
                .minimumScaleFactor(0.75)
                .frame(height: 26)
              Text(stat.title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: interfaceSize.statHeight)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  var boardTypesGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: interfaceSize.boardTypeColumns), spacing: 8) {
      if sortedBoardTypes.isEmpty {
        EmptyStateCard(theme: theme, title: "No board types yet", subtitle: "Create boards and their types will appear here by quantity.")
      }
      ForEach(sortedBoardTypes) { board in
        Button {
          archiveQuery = ""
          archiveBoardTypeFilter = board.name
          archiveStatusFilter = "All"
          archiveMode = .boards
          selectedTab = .projects
        } label: {
          GlassCard(theme: theme) {
            HStack(spacing: interfaceSize.boardTypeColumns == 3 ? 7 : 10) {
              BoardTypeIcon(board: board, size: interfaceSize.boardTypeIconSize)

              VStack(alignment: .leading, spacing: 3) {
                Text(board.name)
                  .font(.system(size: interfaceSize.boardTypeTitleSize, weight: .heavy))
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
                Text(board.subtitle)
                  .font(.system(size: interfaceSize.boardTypeSubtitleSize, weight: .semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.65)
              }

              Spacer()
              Text("\(boardCount(for: board))")
                .font(.system(size: interfaceSize.boardTypeColumns == 3 ? 10 : 12, weight: .bold))
                .foregroundStyle(board.color)
                .padding(.horizontal, interfaceSize.boardTypeColumns == 3 ? 6 : 9)
                .padding(.vertical, interfaceSize.boardTypeColumns == 3 ? 4 : 5)
                .background(board.color.opacity(0.14))
                .clipShape(Capsule())
            }
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  var activeProjectsList: some View {
    VStack(spacing: 10) {
      if activeProjects.isEmpty {
        EmptyStateCard(theme: theme, title: "No active projects", subtitle: "Design and in-progress projects will show here.")
      }
      ForEach(Array(activeProjects.prefix(3).enumerated()), id: \.element.id) { _, project in
        Button {
          remember(.project, id: project.id)
          selectedProject = project
        } label: {
          ProjectDashboardRow(
            theme: theme,
            project: project,
            boardCount: linkedBoards(for: project).count,
            displayedStatus: projectStatus(project),
            glow: true
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  var activeBoardsList: some View {
    VStack(spacing: 10) {
      if activeBoards.isEmpty {
        EmptyStateCard(theme: theme, title: "No in-progress boards", subtitle: "Boards with open checklist items will show here.")
      }
      ForEach(Array(activeBoards.prefix(3).enumerated()), id: \.element.id) { _, board in
        Button {
          remember(.board, id: board.id)
          selectedBoardID = board.id
        } label: {
          DashboardBoardProgressRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
        }
        .buttonStyle(PanelPressButtonStyle())
      }
    }
  }

  var quickSearch: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Quick Search")
            .font(.system(size: 19, weight: .heavy))
          Spacer()
          Label("Filters", systemImage: "slider.horizontal.3")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.primary)
        }

        Button {
          searchQuery = ""
          selectedTab = .search
        } label: {
          HStack {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            Text("Search 630A, ABB, project #...")
              .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
              .foregroundStyle(theme.primary)
          }
          .font(.system(size: 15, weight: .semibold))
          .padding(14)
          .background(theme.surface.opacity(0.72))
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }

  var recentsList: some View {
    VStack(spacing: 14) {
      if visibleRecentVisits.isEmpty {
        EmptyStateCard(theme: theme, title: "No recents yet", subtitle: "Open a project or board and it will stay here.")
      }
      ForEach(visibleRecentVisits) { visit in
        Button {
          openRecent(visit)
        } label: {
          recentRow(for: visit)
        }
        .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func recentRow(for visit: RecentVisit) -> some View {
    switch visit.kind {
    case .project:
      if let project = projects.first(where: { $0.id == visit.itemID }) {
        DashboardProjectRecentRow(
          theme: theme,
          project: project,
          boardCount: linkedBoards(for: project).count,
          displayedStatus: projectStatus(project)
        )
      }
    case .board:
      if let board = boards.first(where: { $0.id == visit.itemID }) {
        DashboardBoardRecentRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
      }
    }
  }

  private func openRecent(_ visit: RecentVisit) {
    remember(visit.kind, id: visit.itemID)
    switch visit.kind {
    case .project:
      selectedProject = projects.first { $0.id == visit.itemID }
    case .board:
      selectedBoardID = visit.itemID
    }
  }

  func sectionHeader(_ title: String, count: Int? = nil, action: @escaping () -> Void) -> some View {
    HStack {
      Text(title)
        .font(.system(size: 22, weight: .heavy))
      if let count {
        Text(count > 3 ? "3+" : "\(count)")
          .font(.system(size: 12, weight: .heavy))
          .foregroundStyle(theme.primary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(theme.primary.opacity(0.14))
          .clipShape(Capsule())
          .overlay(
            Capsule()
              .stroke(theme.primary.opacity(0.18), lineWidth: 1)
          )
      }
      Spacer()
      Button(action: action) {
        Image(systemName: "arrow.right")
          .font(.system(size: 14, weight: .heavy))
          .foregroundStyle(theme.primary)
          .frame(width: 34, height: 28)
          .background(theme.primary.opacity(0.13))
          .clipShape(Capsule())
          .overlay(
            Capsule()
              .stroke(theme.primary.opacity(0.18), lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
    }
  }
}

enum DashboardSheet: String, Identifiable {
  case boardTypes
  case recentProjects
  case stats
  case companies
  case customers
  case newProject

  var id: String { rawValue }
}

struct ProjectsView: View {
  let theme: PanelTheme
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  @Binding var archiveMode: ArchiveMode
  @Binding var archiveQuery: String
  @Binding var archiveBoardTypeFilter: String
  @Binding var archiveStatusFilter: String
  let boardTypes: [BoardType]
  let customers: [CustomerItem]
  let manufacturers: [ManufacturerItem]
  @Binding var selectedTab: PanelTab
  @Binding var newHubSelection: NewHubSelection?
  @Binding var pendingProjectOpenID: String?
  @Binding var recentVisits: [RecentVisit]
  @State private var newProjectOpen = false
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoardID: String?

  private var statuses: [String] {
    archiveMode == .projects ? ["All", "In Progress", "Completed", "Design"] : ["All", "In Progress", "Finished"]
  }

  private var filteredProjects: [ProjectItem] {
    projects.filter { project in
      let statusMatches = archiveStatusFilter == "All" || projectStatus(project) == archiveStatusFilter
      return statusMatches && matchesArchive(projectArchiveText(project))
    }
    .sorted {
      let leftStatus = projectStatus($0)
      let rightStatus = projectStatus($1)
      if projectSortRank(leftStatus) != projectSortRank(rightStatus) {
        return projectSortRank(leftStatus) < projectSortRank(rightStatus)
      }
      if let dueSort = dueDateComesFirst($0.dueDate, $1.dueDate) { return dueSort }
      return $0.name < $1.name
    }
  }

  private var filteredBoardIDs: [String] {
    filteredBoardsForType.filter { board in
      let statusMatches = archiveStatusFilter == "All" || board.statusTitle == archiveStatusFilter
      return statusMatches && matchesArchive(board.searchText)
    }
    .sorted(by: boardPrioritySort)
    .map(\.id)
  }

  private var filteredBoardsForType: [BoardDraft] {
    boards.filter { board in
      archiveBoardTypeFilter == "All" || board.type == archiveBoardTypeFilter
    }
  }

  private var activeProjectCount: Int {
    projects.filter { projectStatus($0) == "In Progress" }.count
  }

  private var completedProjectCount: Int {
    projects.filter { projectStatus($0) == "Completed" }.count
  }

  private var activeBoardCount: Int {
    filteredBoardsForType.filter { !$0.isCompleted }.count
  }

  private var completedBoardCount: Int {
    filteredBoardsForType.filter(\.isCompleted).count
  }

  private var boardGroups: [String] {
    Array(Set(boards.filter { filteredBoardIDs.contains($0.id) }.map(\.group).filter { !$0.isEmpty }))
      .sorted {
        let leftPrefix = boardNumberPrefix($0)
        let rightPrefix = boardNumberPrefix($1)
        if leftPrefix != rightPrefix { return leftPrefix > rightPrefix }
        return $0 > $1
      }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }

  private var ungroupedBoardIDs: [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.group.isEmpty == true
    }
  }

  private var inProgressFilteredBoardIDs: [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.isCompleted == false
    }
  }

  private var completedFilteredBoardIDs: [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.isCompleted == true
    }
  }

  private func boardIDs(in group: String) -> [String] {
    filteredBoardIDs.filter { id in
      boards.first { $0.id == id }?.group == group
    }
  }

  private func linkedBoards(for project: ProjectItem) -> [BoardDraft] {
    boards.filter { $0.project == project.name }
  }

  private func projectStatus(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    guard !linked.isEmpty else { return project.status }
    return linked.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  private func projectSortRank(_ status: String) -> Int {
    switch status {
    case "In Progress": return 0
    case "Design": return 1
    case "Completed": return 2
    default: return 3
    }
  }

  private func projectArchiveText(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    let boardText = linked.map(\.searchText).joined(separator: " ")
    return "\(project.searchText) \(projectStatus(project)) \(boardText)"
  }

  private func matchesArchive(_ text: String) -> Bool {
    let trimmedQuery = archiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedQuery.isEmpty || text.localizedCaseInsensitiveContains(trimmedQuery)
  }

  private func statusTitle(_ status: String) -> String {
    "\(status) \(statusCount(status))"
  }

  private func statusCount(_ status: String) -> Int {
    if status == "All" {
      return archiveMode == .projects ? projects.count : boards.count
    }
    if archiveMode == .projects {
      return projects.filter { projectStatus($0) == status }.count
    }
    return boards.filter { $0.statusTitle == status }.count
  }

  var body: some View {
    NavigationStack {
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 12) {
            Image(systemName: "folder")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(theme.primary)
              .frame(width: 40, height: 40)
              .background(theme.surface.opacity(0.78))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
              Text("Archive")
                .font(.system(size: 28, weight: .heavy))
              Text("Projects and boards")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          Picker("Archive", selection: $archiveMode) {
            ForEach(ArchiveMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .animation(.easeOut(duration: 0.14), value: archiveMode)

          archiveSearchField

          if archiveMode == .boards {
            boardTypeFilterButton
          }

          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            Button {
              archiveStatusFilter = "In Progress"
            } label: {
              ProjectMetricCard(theme: theme, title: archiveMode == .projects ? "Active" : "In Progress", value: "\(archiveMode == .projects ? activeProjectCount : activeBoardCount)", symbol: "clock.fill", color: Color(hex: 0x5E78FF))
            }
            .buttonStyle(.plain)

            Button {
              archiveStatusFilter = archiveMode == .projects ? "Completed" : "Finished"
            } label: {
              ProjectMetricCard(theme: theme, title: archiveMode == .projects ? "Completed" : "Finished", value: "\(archiveMode == .projects ? completedProjectCount : completedBoardCount)", symbol: "checkmark.circle.fill", color: Color(hex: 0x35E177))
            }
            .buttonStyle(.plain)

            Button {
              archiveMode = archiveMode == .projects ? .boards : .projects
              archiveStatusFilter = "All"
              archiveBoardTypeFilter = "All"
            } label: {
              ProjectMetricCard(theme: theme, title: archiveMode == .projects ? "Projects" : "Boards", value: "\(archiveMode == .projects ? projects.count : filteredBoardsForType.count)", symbol: archiveMode == .projects ? "folder.fill" : "rectangle.3.group.fill", color: theme.primary)
            }
            .buttonStyle(.plain)
          }

          HStack {
            Text("Status")
              .font(.headline)
            Spacer()
          }

          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: statuses.count), spacing: 8) {
            ForEach(statuses, id: \.self) { status in
              SearchFilterChip(
                theme: theme,
                title: status,
                selected: archiveStatusFilter == status,
                fillsWidth: true
              ) {
                archiveStatusFilter = status
              }
            }
          }

          HStack {
            Button {
              archiveMode = archiveMode == .projects ? .boards : .projects
              archiveStatusFilter = "All"
              archiveBoardTypeFilter = "All"
            } label: {
              HStack(spacing: 9) {
                Text(archiveMode == .projects ? "Projects" : "Boards")
                  .font(.system(size: 22, weight: .heavy))
                Image(systemName: "arrow.left.arrow.right")
                  .font(.caption.bold())
                  .foregroundStyle(theme.primary)
              }
            }
            .buttonStyle(.plain)
            Spacer()
            if archiveMode == .projects {
            Button {
              newHubSelection = .project
              selectedTab = .newBoard
            } label: {
              Label("New Project", systemImage: "plus")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(theme.primary)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            }
          }

          VStack(spacing: archiveMode == .boards ? 16 : 10) {
            if archiveMode == .boards {
              if boards.isEmpty {
                EmptyStateCard(theme: theme, title: "No boards yet", subtitle: "Create a board from the New Board tab. Unattached boards will show here too.")
              } else if filteredBoardIDs.isEmpty {
                EmptyStateCard(theme: theme, title: "No boards here", subtitle: archiveQuery.isEmpty && archiveBoardTypeFilter == "All" ? "Switch the status filter to see another board stage." : "Clear the board filters or try another board type.")
              } else if archiveStatusFilter == "All" {
                groupedBoardSections
              } else {
                groupedBoardSections
              }
            } else {
            if filteredProjects.isEmpty {
              EmptyStateCard(theme: theme, title: projects.isEmpty ? "No projects yet" : "No projects here", subtitle: projects.isEmpty ? "Tap New Project to create your first project." : "Clear the Archive search or try another customer, board, or project name.")
            }
            ForEach(filteredProjects) { project in
              Button {
                remember(.project, id: project.id)
                selectedProject = project
              } label: {
                ProjectDashboardRow(
                  theme: theme,
                  project: project,
                  boardCount: linkedBoards(for: project).count,
                  displayedStatus: projectStatus(project)
                ) {
                  deleteProject(project)
                }
              }
              .buttonStyle(.plain)
            }
            }
          }
          .animation(.easeOut(duration: 0.14), value: archiveMode)
          .animation(.easeOut(duration: 0.14), value: archiveStatusFilter)
          BottomTabClearance()
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $newProjectOpen) {
        NewProjectSheet(theme: theme, boards: $boards, customers: customers, projectCustomers: uniqueCustomers) { project in
          projects.insert(project, at: 0)
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedProject) { project in
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
          remember(.board, id: board.id)
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        } onDeleteProject: {
          deleteProject(project)
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: selectedBoardBinding) { boardSelection in
        NavigationStack {
          if let index = boards.firstIndex(where: { $0.id == boardSelection.id }) {
            CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
              deleteBoard(boards[index])
              selectedBoardID = nil
            }) {
              selectedBoardID = nil
            }
          } else {
            EmptyStateCard(theme: theme, title: "Board no longer exists", subtitle: "It may have been deleted from Archive.")
              .padding(18)
              .background(theme.background.ignoresSafeArea())
          }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      .onChange(of: archiveMode) { _ in
        if !statuses.contains(archiveStatusFilter) {
          archiveStatusFilter = "All"
        }
        if archiveMode == .projects {
          archiveBoardTypeFilter = "All"
        }
      }
      .onChange(of: pendingProjectOpenID) { projectID in
        openPendingProject(projectID)
      }
      .onAppear {
        openPendingProject(pendingProjectOpenID)
      }
    }
  }

  private func openPendingProject(_ projectID: String?) {
    guard archiveMode == .projects,
          let projectID,
          let project = projects.first(where: { $0.id == projectID }) else { return }
    remember(.project, id: project.id)
    selectedProject = project
    pendingProjectOpenID = nil
  }

  private func deleteProject(_ project: ProjectItem) {
    projects.removeAll { $0.id == project.id }
    for index in boards.indices where boards[index].project == project.name {
      boards[index].project = "No Project"
    }
  }

  private func deleteBoard(_ board: BoardDraft) {
    boards.removeAll { $0.id == board.id }
  }

  private func remember(_ kind: RecentVisit.Kind, id: String) {
    recentVisits.removeAll { $0.kind == kind && $0.itemID == id }
    recentVisits.insert(RecentVisit(kind: kind, id: id), at: 0)
    recentVisits = Array(recentVisits.prefix(12))
  }

  private var archiveSearchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(archiveMode == .projects ? "Search projects, customers, boards..." : "Search boards, type, ampere, project...", text: $archiveQuery)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !archiveQuery.isEmpty {
        Button {
          archiveQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .padding(14)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.07), lineWidth: 1)
    )
  }

  private var boardTypeFilterButton: some View {
    HStack(spacing: 10) {
      Menu {
        Button("All Board Types") {
          archiveBoardTypeFilter = "All"
        }
        ForEach(boardTypes) { type in
          Button(type.name) {
            archiveBoardTypeFilter = type.name
          }
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "slider.horizontal.3")
          Text(archiveBoardTypeFilter == "All" ? "All Board Types" : archiveBoardTypeFilter)
          Image(systemName: "chevron.down")
            .font(.caption.bold())
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(archiveBoardTypeFilter == "All" ? .primary : theme.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background((archiveBoardTypeFilter == "All" ? theme.surface : theme.primary).opacity(archiveBoardTypeFilter == "All" ? 0.78 : 0.18))
        .clipShape(Capsule())
      }

      if archiveBoardTypeFilter != "All" {
        Button {
          archiveBoardTypeFilter = "All"
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .font(.system(size: 18, weight: .semibold))
        }
        .buttonStyle(.plain)
      }

      Spacer()
    }
  }

  private var groupedBoardSections: some View {
    VStack(alignment: .leading, spacing: 16) {
      if archiveStatusFilter == "All" {
        if !inProgressFilteredBoardIDs.isEmpty {
          BoardStageDivider(theme: theme, title: "In Progress", color: theme.primary)
          ForEach(activeBoardGroups, id: \.self) { group in
            boardGroupSection(title: group, ids: sortedInProgressBoardIDs(from: boardIDs(in: group)))
          }
          if !activeUngroupedBoardIDs.isEmpty {
            boardGroupSection(title: "Ungrouped", ids: activeUngroupedBoardIDs)
          }
        }
        if !completedFilteredBoardIDs.isEmpty {
          BoardStageDivider(theme: theme, title: "Finished", color: Color(hex: 0x35E177))
          ForEach(finishedBoardGroups, id: \.self) { group in
            boardGroupSection(title: group, ids: sortedFinishedBoardIDs(from: boardIDs(in: group)))
          }
          if !finishedUngroupedBoardIDs.isEmpty {
            boardGroupSection(title: "Ungrouped", ids: finishedUngroupedBoardIDs)
          }
        }
      } else {
        ForEach(boardGroups, id: \.self) { group in
          boardGroupSection(title: group, ids: boardIDs(in: group))
        }
        if !ungroupedBoardIDs.isEmpty {
          boardGroupSection(title: "Ungrouped", ids: ungroupedBoardIDs)
        }
      }
    }
  }

  private var activeBoardGroups: [String] {
    sortedGroups(for: inProgressFilteredBoardIDs)
  }

  private var finishedBoardGroups: [String] {
    sortedGroups(for: completedFilteredBoardIDs)
  }

  private var activeUngroupedBoardIDs: [String] {
    sortedInProgressBoardIDs(from: ungroupedBoardIDs)
  }

  private var finishedUngroupedBoardIDs: [String] {
    sortedFinishedBoardIDs(from: ungroupedBoardIDs)
  }

  private func sortedGroups(for ids: [String]) -> [String] {
    Array(Set(ids.compactMap { id in
      boards.first { $0.id == id }?.group
    }.filter { !$0.isEmpty }))
    .sorted {
      let leftPrefix = boardNumberPrefix($0)
      let rightPrefix = boardNumberPrefix($1)
      if leftPrefix != rightPrefix { return leftPrefix > rightPrefix }
      return $0 > $1
    }
  }

  private func boardGroupSection(title: String, ids: [String]) -> some View {
    let inProgressIDs = sortedInProgressBoardIDs(from: ids)
    let finishedIDs = sortedFinishedBoardIDs(from: ids)

    return VStack(alignment: .leading, spacing: 12) {
      ArchiveSectionDivider(theme: theme, title: title, prominent: true)
      if !inProgressIDs.isEmpty {
        boardRows(for: inProgressIDs)
      }
      if !inProgressIDs.isEmpty && !finishedIDs.isEmpty {
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.clear, theme.primary.opacity(0.22), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(height: 1)
          .padding(.vertical, 2)
      }
      if !finishedIDs.isEmpty {
        boardRows(for: finishedIDs)
      }
    }
  }

  private func boardRows(for ids: [String]) -> some View {
    ForEach(ids, id: \.self) { boardID in
      if let index = boards.firstIndex(where: { $0.id == boardID }) {
        BoardGalleryRow(theme: theme, board: $boards[index], projects: projects, boardTypes: boardTypes, manufacturers: manufacturers) {
          remember(.board, id: boards[index].id)
          selectedBoardID = boards[index].id
        } onDelete: {
          deleteBoard(boards[index])
        }
      }
    }
  }

  private func sortedInProgressBoardIDs(from ids: [String]) -> [String] {
    ids
      .compactMap { id in boards.first { $0.id == id } }
      .filter { !$0.isCompleted }
      .sorted(by: activeBoardPrioritySort)
      .map(\.id)
  }

  private func sortedFinishedBoardIDs(from ids: [String]) -> [String] {
    ids
      .compactMap { id in boards.first { $0.id == id } }
      .filter(\.isCompleted)
      .sorted {
        let leftPrefix = boardNumberPrefix($0.number)
        let rightPrefix = boardNumberPrefix($1.number)
        if leftPrefix != rightPrefix { return leftPrefix > rightPrefix }
        if $0.number != $1.number { return $0.number > $1.number }
        return $0.name < $1.name
      }
      .map(\.id)
  }

  private func boardNumberPrefix(_ number: String) -> Int {
    let digits = number.prefix { $0.isNumber }.prefix(4)
    return Int(digits) ?? 0
  }

  private func boardStatusSection(title: String, ids: [String]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if !title.isEmpty {
        ArchiveSectionDivider(theme: theme, title: title, prominent: true)
      }
      ForEach(ids, id: \.self) { boardID in
        if let index = boards.firstIndex(where: { $0.id == boardID }) {
          BoardGalleryRow(theme: theme, board: $boards[index], projects: projects, boardTypes: boardTypes, manufacturers: manufacturers) {
            remember(.board, id: boards[index].id)
            selectedBoardID = boards[index].id
          } onDelete: {
            deleteBoard(boards[index])
          }
        }
      }
    }
  }

  private var selectedBoardBinding: Binding<RecentBoardSelection?> {
    Binding {
      selectedBoardID.map(RecentBoardSelection.init(id:))
    } set: { selection in
      selectedBoardID = selection?.id
    }
  }
}

struct ArchiveSectionDivider: View {
  let theme: PanelTheme
  let title: String
  var prominent = false

  var body: some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(.white.opacity(prominent ? 0.16 : 0.10))
        .frame(height: prominent ? 2 : 1)
      Text(title)
        .font(.system(size: prominent ? 24 : 12, weight: .heavy))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.78)
      Rectangle()
        .fill(.white.opacity(prominent ? 0.16 : 0.10))
        .frame(height: prominent ? 2 : 1)
    }
    .padding(.vertical, prominent ? 8 : 4)
  }
}

struct BoardStageDivider: View {
  let theme: PanelTheme
  let title: String
  let color: Color

  var body: some View {
    HStack(spacing: 10) {
      Capsule()
        .fill(
          LinearGradient(
            colors: [color.opacity(0.26), color],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(height: 5)
      Text(title)
        .font(.system(size: 13, weight: .heavy))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
    .padding(.top, 2)
  }
}

enum ArchiveMode: String, CaseIterable, Identifiable {
  case projects
  case boards

  var id: String { rawValue }

  var title: String {
    switch self {
    case .projects: "Projects"
    case .boards: "Boards"
    }
  }
}

struct ProjectMetricCard: View {
  let theme: PanelTheme
  let title: String
  let value: String
  let symbol: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 19, weight: .bold))
          .foregroundStyle(color)
        Text(value)
          .font(.system(size: 24, weight: .heavy))
          .foregroundStyle(color)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
        Text(title)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 86)
    }
  }
}

struct BoardGalleryRow: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  let projects: [ProjectItem]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onOpen: () -> Void = {}
  let onDelete: () -> Void

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverImage, completed: board.isCompleted)

          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(board.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              if let dueDate = board.dueDate {
                DueDateBadge(date: dueDate, compact: true)
              }
            }
            Text(board.number)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text("Out \(DateDisplay.short.string(from: board.dateOut))")
              .font(.caption2.bold())
              .foregroundStyle(board.color)
            if let finishDate = board.finishDate {
              Text("Finished \(DateDisplay.short.string(from: finishDate))")
                .font(.caption2.bold())
                .foregroundStyle(Color(hex: 0x35E177))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
          }

          Spacer()

          VStack(alignment: .trailing, spacing: 6) {
            BoardProgressStatusBadge(board: board)
            DeleteIconButton(theme: theme, action: onDelete)
          }
        }

        HStack {
          Text("\(board.manufacturer) • \(board.displayType) • \(board.ampere) • \(board.cabinetCount) cabinets • \(board.buildFormat)" + (board.group.isEmpty ? "" : " • Group \(board.group)"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Spacer()
        }

        Picker("Project", selection: $board.project) {
          Text("No Project").tag("No Project")
          ForEach(projects.map(\.name), id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)

        Button {
          onOpen()
        } label: {
          Label("Open Board", systemImage: "arrow.right.circle.fill")
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(board.color)
      }
    }
    .background(board.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(0.26), lineWidth: 1)
    )
    .shadow(color: board.color.opacity(0.10), radius: 14, y: 5)
  }
}

struct ProjectDashboardRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  var boardCount: Int? = nil
  var displayedStatus: String? = nil
  var onDelete: (() -> Void)? = nil
  var glow = false

  private var detailText: String {
    let cleanedDetail = project.detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
    let boardText = boardCount.map { "\($0) board\($0 == 1 ? "" : "s")" }
    return [boardText, cleanedDetail.isEmpty ? nil : cleanedDetail]
      .compactMap { $0 }
      .joined(separator: " • ")
  }

  private var statusText: String {
    displayedStatus ?? project.status
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(project.color.gradient)
          if let image = project.coverImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 58, height: 58)
              .clipped()
          } else {
            Image(systemName: "building.2.crop.circle.fill")
              .font(.title3)
              .foregroundStyle(.white)
          }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            Text(project.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = project.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
            StatusBadge(status: statusText)
              .scaleEffect(0.86)
          }
          Text(project.customer)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.primary.opacity(0.86))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(detailText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        Spacer()

        HStack(spacing: 6) {
          if let onDelete {
            DeleteIconButton(theme: theme, action: onDelete)
          }
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
      }
    }
    .background(project.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(project.color.opacity(0.28), lineWidth: 1)
    )
    .shadow(color: project.color.opacity(glow ? 0.28 : 0.14), radius: glow ? 22 : 15, x: 0, y: glow ? 9 : 5)
  }
}

struct DashboardProjectRecentRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  let boardCount: Int
  let displayedStatus: String

  private var cleanedDetail: String {
    project.detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(project.color.gradient)
          if let image = project.coverImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 58, height: 58)
              .clipped()
          } else {
            Image(systemName: "folder.fill")
              .font(.title3)
              .foregroundStyle(.white)
          }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 7) {
            RecentKindBadge(title: "Project", color: Color(hex: 0x64D2FF))
            RecentStatusBadge(status: displayedStatus)
          }

          HStack(spacing: 6) {
            Text(project.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = project.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text("\(project.customer) • \(boardCount) board\(boardCount == 1 ? "" : "s")")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          if !cleanedDetail.isEmpty {
            Text(cleanedDetail)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary.opacity(0.82))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }

        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
    .background(project.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(project.color.opacity(0.28), lineWidth: 1)
    )
  }
}

struct DashboardBoardProgressRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  private var progress: CGFloat {
    min(max(CGFloat(board.completion) / 100, 0), 1)
  }

  private var progressColor: Color {
    let value = min(max(Double(board.completion) / 100, 0), 1)
    let red = 1.0 - (value * 0.78)
    let green = 0.22 + (value * 0.66)
    let blue = 0.20 + (value * 0.08)
    return Color(red: red, green: green, blue: blue)
  }

  private var glowOpacity: Double {
    0.10 + (Double(progress) * 0.42)
  }

  private var glowRadius: CGFloat {
    8 + (progress * 20)
  }

  private var timingText: String {
    "\(board.number) • \(board.type) • \(board.manufacturer)"
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverImage, completed: board.isCompleted)

        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Text(board.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = board.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text(timingText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(theme.surface.opacity(0.82))
              Capsule()
                .fill(
                  LinearGradient(
                    colors: [progressColor.opacity(0.70), progressColor],
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )
                .frame(width: max(proxy.size.width * progress, progress > 0 ? 12 : 0))
                .shadow(color: progressColor.opacity(0.28), radius: 5, y: 1)
            }
          }
          .frame(height: 7)
        }

        Spacer()

        HStack(spacing: 8) {
          Text("\(board.completion)%")
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(progressColor)
            .monospacedDigit()
          Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
        }
        .frame(width: 76, alignment: .trailing)
      }
      .frame(minHeight: 74)
    }
    .background(progressColor.opacity(0.06 + Double(progress) * 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(progressColor.opacity(0.18 + Double(progress) * 0.18), lineWidth: 1)
    )
    .shadow(color: progressColor.opacity(glowOpacity), radius: glowRadius, y: 8)
    .shadow(color: progressColor.opacity(0.10 + Double(progress) * 0.14), radius: 5, y: 2)
  }
}

struct BoardCardThumbnail: View {
  let theme: PanelTheme
  let boardType: BoardType
  let color: Color
  let image: UIImage?
  let completed: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(
          LinearGradient(
            colors: [color.opacity(0.30), theme.surface.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 58, height: 58)
          .clipped()
      } else {
        BoardTypeIcon(board: boardType, size: 34, overrideColor: color)
      }
    }
      .frame(width: 58, height: 58)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        if completed || image == nil {
          Image(systemName: completed ? "checkmark.circle.fill" : "camera.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(completed ? Color(hex: 0x35E177) : color)
            .padding(5)
        }
      }
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(.white.opacity(0.08), lineWidth: 1)
      )
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

struct DashboardBoardRecentRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverImage, completed: board.isCompleted)
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 7) {
            RecentKindBadge(title: "Board", color: Color(hex: 0xFF4E5F))
            RecentStatusBadge(status: board.statusTitle)
          }
          Text(board.name)
            .font(.system(size: 17, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
          Text("\(board.number) • \(board.type) • \(board.ampere)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(board.manufacturer)
            .font(.caption2.bold())
            .foregroundStyle(board.color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
    .background(board.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(0.24), lineWidth: 1)
    )
    .shadow(color: board.color.opacity(0.22), radius: 18, y: 7)
  }
}

struct RecentKindBadge: View {
  let title: String
  let color: Color

  var body: some View {
    Text(title)
      .font(.system(size: 10, weight: .heavy))
      .foregroundStyle(color)
      .frame(width: 64, height: 24)
      .background(color.opacity(0.16))
      .clipShape(Capsule())
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
      .minimumScaleFactor(0.7)
      .frame(width: 88, height: 24)
      .background(color.opacity(0.18))
      .clipShape(Capsule())
      .shadow(color: color.opacity(0.24), radius: 8, y: 2)
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

struct DeleteRecordButton: View {
  let title: String
  let itemName: String
  let action: () -> Void
  @State private var confirmingDelete = false

  var body: some View {
    Button(role: .destructive) {
      confirmingDelete = true
    } label: {
      Label(title, systemImage: "trash.fill")
        .font(.system(size: 16, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(Color(hex: 0xFF6B6B))
        .background(Color(hex: 0xD94B4B).opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(hex: 0xFF6B6B).opacity(0.32), lineWidth: 1)
        )
    }
    .buttonStyle(PanelPressButtonStyle())
    .confirmationDialog("Delete \(itemName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(title, role: .destructive, action: action)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This action cannot be undone.")
    }
  }
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
            .fill(configuration.isOn ? theme.primary.opacity(0.95) : Color.white.opacity(0.14))
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

struct ProjectDetailSheet: View {
  let theme: PanelTheme
  let project: ProjectItem
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onVisitBoard: (BoardDraft) -> Void = { _ in }
  var onUpdateProject: ((ProjectItem, String) -> Void)? = nil
  var onDeleteProject: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var selectedBoard: BoardDraft?
  @State private var projectName: String
  @State private var lastSavedName: String
  @State private var customer: String
  @State private var detail: String
  @State private var projectColor: Color
  @State private var coverImage: UIImage?
  @State private var projectPhotos: [UIImage] = []
  @State private var projectSchemes: [SchemeAttachment]
  @State private var hasDueDate: Bool
  @State private var dueDate: Date
  @State private var editOpen = false
  @State private var attachBoardsOpen = false

  init(
    theme: PanelTheme,
    project: ProjectItem,
    boards: Binding<[BoardDraft]>,
    boardTypes: [BoardType],
    manufacturers: [ManufacturerItem],
    onVisitBoard: @escaping (BoardDraft) -> Void = { _ in },
    onUpdateProject: ((ProjectItem, String) -> Void)? = nil,
    onDeleteProject: (() -> Void)? = nil
  ) {
    self.theme = theme
    self.project = project
    self._boards = boards
    self.boardTypes = boardTypes
    self.manufacturers = manufacturers
    self.onVisitBoard = onVisitBoard
    self.onUpdateProject = onUpdateProject
    self.onDeleteProject = onDeleteProject
    _projectName = State(initialValue: project.name)
    _lastSavedName = State(initialValue: project.name)
    _customer = State(initialValue: project.customer)
    _detail = State(initialValue: project.detail)
    _projectColor = State(initialValue: project.color)
    _coverImage = State(initialValue: project.coverImage)
    _projectPhotos = State(initialValue: project.photoImages)
    _projectSchemes = State(initialValue: project.schemeAttachments)
    _hasDueDate = State(initialValue: project.dueDate != nil)
    _dueDate = State(initialValue: project.dueDate ?? Date())
  }

  private var linkedBoards: [BoardDraft] {
    boards
      .filter { $0.project == projectName }
      .sorted(by: boardPrioritySort)
  }

  private var projectDetailWithoutBoardCount: String {
    detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
  }

  private var projectStatus: String {
    guard !linkedBoards.isEmpty else { return project.status }
    return linkedBoards.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ProjectCoverPhotoSection(theme: theme, selectedImage: $coverImage) {
            saveProjectChanges()
          }

          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              Label("Project Properties", systemImage: "folder.fill")
                .font(.headline)
                .foregroundStyle(projectColor)

              VStack(alignment: .leading, spacing: 4) {
                Text(projectName)
                  .font(.title2.bold())
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
                Text(customer.isEmpty ? "No customer selected" : customer)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
              }

              ProjectPropertiesOverview(
                theme: theme,
                color: projectColor,
                boardCount: linkedBoards.count,
                status: projectStatus,
                customer: customer,
                detail: projectDetailWithoutBoardCount,
                dueDate: hasDueDate ? dueDate : nil
              )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          SchemeAttachmentSection(theme: theme, title: "Project PDFs & Schemes", attachments: $projectSchemes)
            .onChange(of: projectSchemes) { _ in
              saveProjectChanges()
            }

          HStack {
            Text("Boards")
              .font(.headline)
            Spacer()
            Button {
              attachBoardsOpen = true
            } label: {
              Label("Attach", systemImage: "plus.circle.fill")
                .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(projectColor)
          }

          if linkedBoards.isEmpty {
            EmptyStateCard(theme: theme, title: "No boards attached", subtitle: "Tap Attach to add boards to this project.")
          }

          ForEach(linkedBoards) { board in
            Button {
              onVisitBoard(board)
              selectedBoard = board
            } label: {
              GlassCard(theme: theme) {
                HStack {
                  let boardType = boardTypes.first { $0.name == board.type } ?? .fallback
                  BoardTypeIcon(board: boardType, size: 36, overrideColor: board.color)
                  VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                      Text(board.name).font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                      if let dueDate = board.dueDate {
                        DueDateBadge(date: dueDate, compact: true)
                      }
                    }
                    Text("\(board.number) • \(board.type) • Out \(DateDisplay.short.string(from: board.dateOut))").font(.caption).foregroundStyle(.secondary)
                      .lineLimit(1)
                      .minimumScaleFactor(0.7)
                  }
                  Spacer()
                  StatusBadge(status: board.statusTitle)
                  Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
              }
            }
            .buttonStyle(.plain)
          }

          PhotoPickerSection(theme: theme, title: "Project Photos", selectedImages: $projectPhotos, coverImage: $coverImage)
            .onChange(of: projectPhotos.map { ImageArchive.signature(for: $0) }) { _ in
              saveProjectChanges()
            }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .navigationTitle(projectName)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Edit") {
            withAnimation(.easeInOut(duration: 0.24)) {
              editOpen = true
            }
          }
          .fontWeight(.bold)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedBoard) { board in
        NavigationStack {
          if let index = boards.firstIndex(where: { $0.id == board.id }) {
            CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
              boards.removeAll { $0.id == board.id }
              selectedBoard = nil
            }) {
              selectedBoard = nil
            }
          } else {
            EmptyStateCard(theme: theme, title: "Board no longer exists", subtitle: "It may have been deleted from Archive.")
              .padding(18)
              .background(theme.background.ignoresSafeArea())
          }
        }
      }
      .sheet(isPresented: $attachBoardsOpen) {
        BoardAttachPickerSheet(theme: theme, projectName: projectName, projectCustomer: customer, boards: $boards)
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $editOpen) {
        ProjectEditSheet(
          theme: theme,
          projectName: $projectName,
          customer: $customer,
          detail: $detail,
          projectColor: $projectColor,
          hasDueDate: $hasDueDate,
          dueDate: $dueDate,
          onSave: saveProjectChanges,
          onDelete: onDeleteProject.map { deleteProject in
            {
              deleteProject()
              dismiss()
            }
          }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
      }
    }
  }

  private func saveProjectChanges() {
    let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    let previousName = lastSavedName
    onUpdateProject?(
      ProjectItem(
        id: project.id,
        name: trimmedName,
        customer: customer.trimmingCharacters(in: .whitespacesAndNewlines),
        detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
        status: project.status,
        color: projectColor,
        coverImage: coverImage,
        photoImages: projectPhotos,
        dueDate: hasDueDate ? dueDate : nil,
        schemeAttachments: projectSchemes
      ),
      previousName
    )
    lastSavedName = trimmedName
  }
}

struct ProjectPropertiesOverview: View {
  let theme: PanelTheme
  let color: Color
  let boardCount: Int
  let status: String
  let customer: String
  let detail: String
  let dueDate: Date?

  private var boardText: String {
    if boardCount == 0 { return "No boards attached" }
    return "\(boardCount) board\(boardCount == 1 ? "" : "s")"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        ProjectPropertyPill(symbol: "person.crop.circle.fill", title: "Customer", value: customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No customer" : customer, color: color)
        ProjectPropertyPill(symbol: "rectangle.3.group.fill", title: "Boards", value: boardText, color: color)
        ProjectPropertyPill(symbol: "checkmark.seal.fill", title: "Status", value: status, color: statusColor)
        if let dueDate {
          DueDatePropertyPill(date: dueDate)
        }
      }

      let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleanedDetail.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Notes")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Text(cleanedDetail)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(4)
            .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
    }
  }

  private var statusColor: Color {
    switch status {
    case "Completed", "Finished":
      return Color(hex: 0x35E177)
    case "Design":
      return Color(hex: 0xFF4FD8)
    default:
      return Color(hex: 0x64D2FF)
    }
  }
}

struct ProjectPropertyPill: View {
  let symbol: String
  let title: String
  let value: String
  let color: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 28, height: 28)
        .background(color.opacity(0.14))
        .clipShape(Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption2.bold())
          .foregroundStyle(.secondary)
        Text(value)
          .font(.caption.bold())
          .lineLimit(2)
          .minimumScaleFactor(0.7)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .background(color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(color.opacity(0.13), lineWidth: 1)
    )
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

struct ManufacturerPropertyPill: View {
  let manufacturer: ManufacturerItem?
  let fallbackName: String

  private var name: String {
    manufacturer?.name ?? fallbackName
  }

  private var color: Color {
    manufacturer?.color ?? Color(hex: 0xAEB4BC)
  }

  var body: some View {
    HStack(spacing: 8) {
      ManufacturerMarkView(manufacturer: manufacturer, fallbackName: fallbackName, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text("Manufacturer")
          .font(.caption2.bold())
          .foregroundStyle(.secondary)
        Text(name)
          .font(.caption.bold())
          .lineLimit(2)
          .minimumScaleFactor(0.7)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .background(color.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(color.opacity(0.13), lineWidth: 1)
    )
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

struct DueDatePropertyPill: View {
  let date: Date

  private var color: Color {
    dueUrgencyColor(for: date)
  }

  var body: some View {
    ProjectPropertyPill(
      symbol: "clock.badge.exclamationmark.fill",
      title: "Due",
      value: DateDisplay.due.string(from: date),
      color: color
    )
    .shadow(color: color.opacity(0.24), radius: 10, y: 2)
  }
}

struct AddablePropertyPill: View {
  let title: String
  let value: String
  let isEmpty: Bool
  let isEnabled: Bool
  let action: () -> Void

  private var color: Color {
    if !isEnabled && isEmpty { return Color.gray.opacity(0.46) }
    return isEmpty ? Color(hex: 0x64D2FF) : Color(hex: 0x64D2FF)
  }

  var body: some View {
    Button(action: action) {
      ProjectPropertyPill(
        symbol: isEmpty ? "plus" : "timer",
        title: title,
        value: isEmpty ? (isEnabled ? "Add time" : "Complete checklist first") : value,
        color: color
      )
    }
    .buttonStyle(PanelPressButtonStyle())
    .disabled(!isEnabled && isEmpty)
    .opacity(!isEnabled && isEmpty ? 0.68 : 1)
  }
}

struct FinishStatusPropertyPill: View {
  let board: BoardDraft
  let action: () -> Void

  private var value: String {
    let finishDate = board.finishDate.map { DateDisplay.short.string(from: $0) }
    let finishTime = board.finishTimeHours.trimmingCharacters(in: .whitespacesAndNewlines)

    if !board.isCompleted {
      return "Complete checklist first"
    }
    if let finishDate, !finishTime.isEmpty {
      return "\(finishDate) • \(finishTime) h"
    }
    if let finishDate {
      return "\(finishDate) • Add time"
    }
    return finishTime.isEmpty ? "Add finish time" : "\(finishTime) h"
  }

  private var color: Color {
    board.isCompleted ? Color(hex: 0x35E177) : Color.gray.opacity(0.46)
  }

  var body: some View {
    Button(action: action) {
      ProjectPropertyPill(
        symbol: board.isCompleted ? "checkmark.circle.fill" : "lock.fill",
        title: "Finished",
        value: value,
        color: color
      )
    }
    .buttonStyle(PanelPressButtonStyle())
    .disabled(!board.isCompleted)
    .opacity(board.isCompleted ? 1 : 0.68)
  }
}

struct BoardPropertiesOverview: View {
  let theme: PanelTheme
  let board: BoardDraft
  let manufacturers: [ManufacturerItem]
  let onEditFinishTime: () -> Void

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Board Properties", systemImage: "rectangle.3.group.fill")
            .font(.headline)
          Spacer()
          BoardProgressStatusBadge(board: board)
        }

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
          ProjectPropertyPill(symbol: "person.crop.circle.fill", title: "Customer", value: board.customer.isEmpty ? "No customer" : board.customer, color: board.color)
          if !board.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ProjectPropertyPill(symbol: "building.2.fill", title: "Company", value: board.company, color: board.color)
          }
          ProjectPropertyPill(symbol: "folder.fill", title: "Project", value: board.project.isEmpty ? "No Project" : board.project, color: board.color)
          ProjectPropertyPill(symbol: "square.grid.2x2.fill", title: "Type", value: board.type, color: board.color)
          if BoardSubtypeCatalog.isVisible(board.subtype) {
            ProjectPropertyPill(symbol: "rectangle.grid.1x2.fill", title: "Subtype", value: board.subtype, color: board.color)
          }
          ManufacturerPropertyPill(manufacturer: manufacturer, fallbackName: board.manufacturer)
          ProjectPropertyPill(symbol: "bolt.fill", title: "Ampere", value: board.ampere, color: board.color)
          ProjectPropertyPill(symbol: "rectangle.split.3x1.fill", title: "Cabinets", value: "\(board.cabinetCount) • \(board.buildFormat)", color: board.color)
          ProjectPropertyPill(symbol: "calendar", title: "Out Date", value: DateDisplay.short.string(from: board.dateOut), color: board.color)
          if let dueDate = board.dueDate {
            DueDatePropertyPill(date: dueDate)
          }
          FinishStatusPropertyPill(board: board, action: onEditFinishTime)
          ProjectPropertyPill(symbol: "bolt.shield.fill", title: "Breaker Type", value: board.mainBreakerType, color: board.color)
          ProjectPropertyPill(symbol: "tag.fill", title: "Breaker", value: board.mainBreakerLabel.isEmpty ? board.mainBreakerModel : board.mainBreakerLabel, color: board.color)
          if !board.group.isEmpty {
            ProjectPropertyPill(symbol: "rectangle.stack.fill", title: "Group", value: board.group, color: board.color)
          }
        }
      }
    }
  }
}

struct ProjectEditPanel: View {
  let theme: PanelTheme
  @Binding var projectColor: Color
  let onChange: () -> Void
  var onDelete: (() -> Void)? = nil

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Edit Project", systemImage: "slider.horizontal.3")
            .font(.headline)
          Spacer()
          Text("Color")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
        }

        BoardColorEditPicker(title: "Project color", color: $projectColor)
          .onChange(of: projectColor) { _ in
            onChange()
          }

        if let onDelete {
          DeleteIconButton(theme: theme, action: onDelete)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
  }
}

struct ProjectEditSheet: View {
  let theme: PanelTheme
  @Binding var projectName: String
  @Binding var customer: String
  @Binding var detail: String
  @Binding var projectColor: Color
  @Binding var hasDueDate: Bool
  @Binding var dueDate: Date
  let onSave: () -> Void
  var onDelete: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          CreationFormSection(theme: theme, title: "Project Details", symbol: "folder.fill", subtitle: "Identity and customer") {
            CreationTextInput(theme: theme, title: "Project name", placeholder: "Project name", symbol: "folder.fill", text: $projectName, capitalization: .words)
            CreationTextInput(theme: theme, title: "Customer", placeholder: "Customer", symbol: "person.crop.circle.fill", text: $customer, capitalization: .words)
            CreationTextInput(theme: theme, title: "Project detail", placeholder: "Site or notes", symbol: "mappin.and.ellipse", text: $detail, capitalization: .words)
          }

          CreationFormSection(theme: theme, title: "Schedule & Appearance", symbol: "slider.horizontal.3") {
            CreationToggleInput(theme: theme, title: "Expected finish date", symbol: "clock.badge.exclamationmark.fill", isOn: $hasDueDate)
            if hasDueDate {
              CreationDateInput(theme: theme, title: "Due", symbol: "calendar.badge.clock", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
            }
            BoardColorEditPicker(title: "Project color", color: $projectColor)
          }

          if let onDelete {
            DeleteRecordButton(title: "Delete Project", itemName: projectName, action: onDelete)
              .padding(.top, 8)
          }
          BottomTabClearance(height: 72)
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Edit Project")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            onSave()
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
      .onDisappear {
        onSave()
      }
    }
  }
}

struct BoardTypesSheet: View {
  let theme: PanelTheme
  let boardTypes: [BoardType]
  @Environment(\.dismiss) private var dismiss
  @State private var selectedBoardType: BoardType?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(boardTypes) { board in
            Button {
              selectedBoardType = board
            } label: {
              GlassCard(theme: theme) {
                HStack(spacing: 12) {
                  BoardTypeIcon(board: board, size: 42)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(board.name)
                      .font(.headline)
                      .lineLimit(2)
                      .minimumScaleFactor(0.75)
                    Text([board.localName, board.subtitle].compactMap { $0 }.joined(separator: " • "))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                      .minimumScaleFactor(0.75)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Board Types")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedBoardType) { board in
        BoardTypeDetailSheet(theme: theme, board: board)
      }
    }
  }
}

struct BoardTypeDetailSheet: View {
  let theme: PanelTheme
  let board: BoardType
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 14) {
            BoardTypeIcon(board: board, size: 70)
            VStack(alignment: .leading, spacing: 5) {
              Text(board.name)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
              if let localName = board.localName {
                Text(localName)
                  .font(.headline)
                  .foregroundStyle(board.color)
              }
              Text(board.subtitle)
                .foregroundStyle(.secondary)
            }
          }

          BoardReferenceSection(theme: theme, title: "Description", symbol: "text.alignleft", color: board.color) {
            Text(board.overview ?? "\(board.name) is a custom board type. Add notes, photos and schemes to each board record to document how this category is used in your projects.")
              .font(.body)
              .foregroundStyle(.primary.opacity(0.9))
              .fixedSize(horizontal: false, vertical: true)
          }

          BoardReferenceSection(theme: theme, title: "Typical Uses", symbol: "building.2.fill", color: board.color) {
            BoardBulletList(items: board.typicalUses.isEmpty ? ["Project-specific use", "Custom distribution or control category"] : board.typicalUses)
          }

          BoardReferenceSection(theme: theme, title: "Common Equipment", symbol: "shippingbox.fill", color: board.color) {
            BoardBulletList(items: board.typicalComponents.isEmpty ? ["Main switch or breaker", "Protection devices", "Terminals", "Labels and documentation"] : board.typicalComponents)
          }

          BoardReferenceSection(theme: theme, title: "Checks Before Build", symbol: "checklist.checked", color: board.color) {
            BoardBulletList(items: board.designChecks.isEmpty ? ["Rated current", "Short-circuit rating", "IP rating", "Cable entry space", "Labeling"] : board.designChecks)
          }

          if !board.notes.isEmpty {
            BoardReferenceSection(theme: theme, title: "Israel Notes", symbol: "mappin.and.ellipse", color: board.color) {
              BoardBulletList(items: board.notes)
            }
          }

          BoardReferenceSection(theme: theme, title: "Default Units", symbol: "ruler.fill", color: board.color) {
            BoardBulletList(items: ["Current: A", "Fault level: kA", "Cable and copper dimensions: mm, cm, m", "Motor and PV power: kW / kVAr where relevant"])
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(board.name)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
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

struct ProjectsListSheet: View {
  let theme: PanelTheme
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var selectedProject: ProjectItem?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          if projects.isEmpty {
            EmptyStateCard(theme: theme, title: "No projects yet", subtitle: "Create your first project from the Projects tab.")
          }
          ForEach(projects) { project in
            Button {
              selectedProject = project
            } label: {
              ProjectDashboardRow(theme: theme, project: project)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Recent Projects")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: $selectedProject) { project in
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { _ in
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        } onDeleteProject: {
          projects.removeAll { $0.id == project.id }
          for index in boards.indices where boards[index].project == project.name {
            boards[index].project = "No Project"
          }
          selectedProject = nil
        }
      }
    }
  }
}

struct DashboardStatsSheet: View {
  let theme: PanelTheme
  let projects: [ProjectItem]
  let boardCount: Int
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        ProjectMetricCard(theme: theme, title: "Projects", value: "\(projects.count)", symbol: "folder.fill", color: theme.primary)
        ProjectMetricCard(theme: theme, title: "Boards", value: "\(boardCount)", symbol: "rectangle.3.group.fill", color: Color(hex: 0xAEB4BC))
        ProjectMetricCard(theme: theme, title: "Customers", value: "\(Set(projects.map(\.customer)).count)", symbol: "person.2.fill", color: Color(hex: 0x7D8791))
        Spacer()
      }
      .padding(18)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Statistics")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
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

enum NewHubSelection {
  case project
  case board
}

struct NewHubView: View {
  let theme: PanelTheme
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let customers: [CustomerItem]
  let companies: [ContractorCompany]
  let manufacturers: [ManufacturerItem]
  let boardTypes: [BoardType]
  @Binding var selection: NewHubSelection?
  let onCreateBoard: (BoardDraft) -> Void
  let onUpdateBoard: (BoardDraft) -> Void
  let onCreateProject: (ProjectItem) -> Void

  private var projectCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }

  var body: some View {
    Group {
      switch selection {
      case .board:
        NewBoardView(
          theme: theme,
          projects: projects,
          customers: customers,
          companies: companies,
          manufacturers: manufacturers,
          boardTypes: boardTypes,
          onCreate: onCreateBoard,
          onUpdate: onUpdateBoard,
          onBackToHub: {
            withAnimation(.easeOut(duration: 0.16)) {
              selection = nil
            }
          }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
      case .project:
        NewProjectSheet(theme: theme, boards: $boards, customers: customers, projectCustomers: projectCustomers, onDone: {
          selection = nil
        }) { project in
          onCreateProject(project)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
      case nil:
        NavigationStack {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              Text("New")
                .font(.largeTitle.bold())
              Text("Create a project or start a board.")
                .foregroundStyle(.secondary)

              Button {
                selection = .project
              } label: {
                NewBoardModeCard(
                  theme: theme,
                  symbol: "folder.badge.plus",
                  title: "New Project",
                  subtitle: "Create the customer/project container first, then attach boards.",
                  color: Color(hex: 0x35E177)
                )
              }
              .buttonStyle(PanelPressButtonStyle())

              Button {
                selection = .board
              } label: {
                NewBoardModeCard(
                  theme: theme,
                  symbol: "rectangle.3.group.fill",
                  title: "New Board",
                  subtitle: "Scan a scheme with AI or enter the board manually.",
                  color: Color(hex: 0x5E78FF)
                )
              }
              .buttonStyle(PanelPressButtonStyle())
              BottomTabClearance()
            }
            .padding(18)
          }
          .background(theme.background.ignoresSafeArea())
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
      }
    }
    .animation(.easeOut(duration: 0.16), value: selection)
  }
}

struct CreationFormSection<Content: View>: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  var subtitle: String? = nil
  @ViewBuilder let content: Content

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.primary)
            .frame(width: 28, height: 28)
            .background(theme.primary.opacity(0.14))
            .clipShape(Circle())
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 16, weight: .heavy))
            if let subtitle {
              Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 0)
        }

        VStack(spacing: 8) {
          content
        }
      }
    }
  }
}

struct CreationTextInput: View {
  let theme: PanelTheme
  let title: String
  let placeholder: String
  let symbol: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default
  var capitalization: TextInputAutocapitalization = .sentences

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      TextField(placeholder, text: $text)
        .font(.system(size: 15, weight: .semibold))
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(capitalization)
        .keyboardType(keyboardType)
        .autocorrectionDisabled(keyboardType != .default)
    }
  }
}

struct CreationMenuInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let value: String
  let options: [String]
  @Binding var selection: String

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      Menu {
        ForEach(options, id: \.self) { option in
          Button(option) {
            selection = option
          }
        }
      } label: {
        HStack(spacing: 6) {
          Text(value.isEmpty ? "Select" : value)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Image(systemName: "chevron.down")
            .font(.caption2.bold())
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primary)
      }
    }
  }
}

struct CreationPickerInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let value: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      CreationFieldShell(theme: theme, title: title, symbol: symbol) {
        HStack(spacing: 6) {
          Text(value.isEmpty ? "Choose" : value)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Image(systemName: "chevron.right")
            .font(.caption2.bold())
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.primary)
      }
    }
    .buttonStyle(PanelPressButtonStyle())
  }
}

struct CreationDateInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  @Binding var selection: Date
  let displayedComponents: DatePickerComponents

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      DatePicker("", selection: $selection, displayedComponents: displayedComponents)
        .labelsHidden()
        .font(.system(size: 15, weight: .bold))
    }
  }
}

struct CreationToggleInput: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  @Binding var isOn: Bool

  var body: some View {
    CreationFieldShell(theme: theme, title: title, symbol: symbol) {
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(theme.primary)
    }
  }
}

struct CreationFieldShell<Accessory: View>: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  @ViewBuilder let accessory: Accessory

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(theme.primary)
        .frame(width: 26, height: 26)
        .background(theme.primary.opacity(0.12))
        .clipShape(Circle())
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.72)
      Spacer(minLength: 10)
      accessory
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .background(theme.surface.opacity(0.56))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.07), lineWidth: 1)
    )
  }
}

struct CreationOptionPickerSheet: View {
  let theme: PanelTheme
  let title: String
  let symbol: String
  let options: [String]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredOptions: [String] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return options }
    return options.filter { $0.localizedCaseInsensitiveContains(trimmed) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search \(title.lowercased())")

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredOptions, id: \.self) { option in
              Button {
                onSelect(option)
                dismiss()
              } label: {
                CreationOptionCard(theme: theme, title: option, subtitle: option == selected ? "Selected" : nil, symbol: symbol, selected: option == selected)
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }

          if filteredOptions.isEmpty {
            EmptyStateCard(theme: theme, title: "No matches", subtitle: "Try a different search.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct ManufacturerCreationPickerSheet: View {
  let theme: PanelTheme
  let manufacturers: [ManufacturerItem]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var mergedManufacturers: [ManufacturerItem] {
    var seen: Set<String> = []
    return (manufacturers + ManufacturerItem.defaults).filter { manufacturer in
      let key = manufacturer.name.lowercased()
      guard !manufacturer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var filteredManufacturers: [ManufacturerItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return mergedManufacturers }
    return mergedManufacturers.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search manufacturers")

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredManufacturers) { manufacturer in
              Button {
                onSelect(manufacturer.name)
                dismiss()
              } label: {
                GlassCard(theme: theme) {
                  VStack(alignment: .leading, spacing: 10) {
                    HStack {
                      ManufacturerMarkView(manufacturer: manufacturer, fallbackName: manufacturer.name, size: 42)
                      Spacer()
                      if selected.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame {
                        Image(systemName: "checkmark.circle.fill")
                          .font(.system(size: 18, weight: .bold))
                          .foregroundStyle(manufacturer.color)
                      }
                    }

                    Text(manufacturer.name)
                      .font(.system(size: 15, weight: .heavy))
                      .lineLimit(2)
                      .minimumScaleFactor(0.72)

                    Text("Uses logo and color from Manufacturers")
                      .font(.caption2.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                  .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                }
                .overlay(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                      selected.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame ? manufacturer.color : .white.opacity(0.07),
                      lineWidth: selected.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame ? 1.4 : 1
                    )
                )
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }

          if filteredManufacturers.isEmpty {
            EmptyStateCard(theme: theme, title: "No manufacturers", subtitle: "Add it from More, then it will show here.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Manufacturer")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct BoardTypeCreationPickerSheet: View {
  let theme: PanelTheme
  let boardTypes: [BoardType]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredTypes: [BoardType] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return boardTypes }
    return boardTypes.filter {
      $0.name.localizedCaseInsensitiveContains(trimmed) ||
        $0.subtitle.localizedCaseInsensitiveContains(trimmed) ||
        ($0.localName?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search board types")

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(filteredTypes) { board in
              Button {
                onSelect(board.name)
                dismiss()
              } label: {
                GlassCard(theme: theme) {
                  VStack(alignment: .leading, spacing: 10) {
                    HStack {
                      BoardTypeIcon(board: board, size: 38)
                      Spacer()
                      if selected == board.name {
                        Image(systemName: "checkmark.circle.fill")
                          .font(.system(size: 18, weight: .bold))
                          .foregroundStyle(board.color)
                      }
                    }
                    Text(board.name)
                      .font(.system(size: 15, weight: .heavy))
                      .lineLimit(2)
                      .minimumScaleFactor(0.72)
                    Text(board.subtitle)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                      .minimumScaleFactor(0.72)
                  }
                  .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
                }
                .overlay(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke((selected == board.name ? board.color : .white.opacity(0.07)), lineWidth: selected == board.name ? 1.4 : 1)
                )
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }

          if filteredTypes.isEmpty {
            EmptyStateCard(theme: theme, title: "No board types", subtitle: "Try a different search.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Board Type")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct ProjectCreationPickerSheet: View {
  let theme: PanelTheme
  let projects: [ProjectItem]
  let selected: String
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredProjects: [ProjectItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return projects }
    return projects.filter {
      $0.name.localizedCaseInsensitiveContains(trimmed) ||
        $0.customer.localizedCaseInsensitiveContains(trimmed) ||
        $0.detail.localizedCaseInsensitiveContains(trimmed)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          CreationPickerSearch(theme: theme, query: $query, placeholder: "Search projects or customers")

          Button {
            onSelect("No Project")
            dismiss()
          } label: {
            CreationOptionCard(theme: theme, title: "No Project", subtitle: "Leave this board unattached", symbol: "tray", selected: selected == "No Project")
          }
          .buttonStyle(PanelPressButtonStyle())

          ForEach(filteredProjects) { project in
            Button {
              onSelect(project.name)
              dismiss()
            } label: {
              GlassCard(theme: theme) {
                HStack(spacing: 12) {
                  Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(project.color)
                    .frame(width: 42, height: 42)
                    .background(project.color.opacity(0.14))
                    .clipShape(Circle())
                  VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                      .font(.headline)
                      .lineLimit(1)
                      .minimumScaleFactor(0.7)
                    Text(project.customer.isEmpty ? "No customer" : project.customer)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  Spacer()
                  if selected == project.name {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(project.color)
                  }
                }
              }
            }
            .buttonStyle(PanelPressButtonStyle())
          }

          if filteredProjects.isEmpty && !query.isEmpty {
            EmptyStateCard(theme: theme, title: "No projects", subtitle: "Try another customer or project name.")
          }
          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Project")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }
}

struct CreationPickerSearch: View {
  let theme: PanelTheme
  @Binding var query: String
  let placeholder: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(theme.primary)
      TextField(placeholder, text: $query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .padding(13)
    .background(theme.surface.opacity(0.70))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(0.08), lineWidth: 1)
    )
  }
}

struct CreationOptionCard: View {
  let theme: PanelTheme
  let title: String
  var subtitle: String? = nil
  let symbol: String
  let selected: Bool

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.primary)
            .frame(width: 38, height: 38)
            .background(theme.primary.opacity(0.14))
            .clipShape(Circle())
          Spacer()
          if selected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(theme.primary)
          }
        }
        Text(title)
          .font(.system(size: 15, weight: .heavy))
          .lineLimit(2)
          .minimumScaleFactor(0.72)
        if let subtitle {
          Text(subtitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
        }
      }
      .frame(maxWidth: .infinity, minHeight: subtitle == nil ? 96 : 112, alignment: .leading)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(selected ? theme.primary.opacity(0.75) : .white.opacity(0.07), lineWidth: selected ? 1.4 : 1)
    )
  }
}

struct SuggestionChips: View {
  let theme: PanelTheme
  let values: [String]
  let selectedValue: String
  let onSelect: (String) -> Void

  var body: some View {
    if !values.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(values, id: \.self) { value in
            Button {
              onSelect(value)
            } label: {
              Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(selectedValue == value ? theme.primary : theme.primary.opacity(0.14))
                .foregroundStyle(selectedValue == value ? .white : theme.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(PanelPressButtonStyle())
          }
        }
      }
    }
  }
}

enum NewBoardPickerSheet: String, Identifiable {
  case boardType
  case subtype
  case manufacturer
  case project

  var id: String { rawValue }
}

struct NewBoardView: View {
  let theme: PanelTheme
  let projects: [ProjectItem]
  let customers: [CustomerItem]
  let companies: [ContractorCompany]
  let manufacturers: [ManufacturerItem]
  let boardTypes: [BoardType]
  let onCreate: (BoardDraft) -> Void
  let onUpdate: (BoardDraft) -> Void
  var onBackToHub: (() -> Void)? = nil
  @State private var boardNumber = ""
  @State private var boardGroup = ""
  @State private var boardName = ""
  @State private var customerName = ""
  @State private var companyName = ""
  @State private var project = "No Project"
  @State private var boardType = BoardType.samples.first?.name ?? "MDB"
  @State private var boardSubtype = BoardSubtypeCatalog.defaultSubtype
  @State private var boardManufacturer = ManufacturerItem.defaults.first?.name ?? "Generic"
  @State private var cabinetCount = "1"
  @State private var buildFormat = "Panels"
  @State private var boardDate = Date()
  @State private var hasDueDate = false
  @State private var boardDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
  @State private var hasFinishDate = false
  @State private var boardFinishDate = Date()
  @State private var mainBreakerType = "Main Breaker"
  @State private var mainBreakerModel = ManufacturerItem.defaults.first?.name ?? "ABB"
  @State private var mainBreakerAmpere = "630A"
  @State private var selectedBoardColorHex: UInt32 = 0x5E78FF
  @State private var createdBoard: BoardDraft?
  @State private var mainBreakerOpen = false
  @State private var createdMessage = false
  @State private var entryMode: NewBoardEntryMode?
  @State private var pendingSchemeAttachments: [SchemeAttachment] = []
  @State private var aiScanComplete = false
  @State private var aiScanning = false
  @State private var pickerSheet: NewBoardPickerSheet?

  private var canCreate: Bool {
    !boardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !boardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var recentCustomers: [String] {
    Array(Set(projects.map(\.customer) + customers.map(\.name))).filter { !$0.isEmpty }.sorted()
  }

  private var matchingRecentCustomers: [String] {
    let query = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return recentCustomers }
    return recentCustomers.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var companyNames: [String] {
    Array(Set(companies.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var matchingCompanyNames: [String] {
    let query = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return companyNames }
    return companyNames.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var subtypeOptions: [String] {
    BoardSubtypeCatalog.options(for: boardType)
  }

  private var manufacturerNames: [String] {
    let names = manufacturers.map(\.name) + ManufacturerItem.defaults.map(\.name)
    return Array(Set(names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var suggestedGroup: String {
    guard let dashIndex = boardNumber.lastIndex(of: "-") else { return "" }
    return String(boardNumber[..<dashIndex])
  }

  var body: some View {
    NavigationStack {
      if let createdBoard {
        CreatedBoardScreen(
          theme: theme,
          board: Binding(
            get: { createdBoard },
            set: {
              self.createdBoard = $0
              onUpdate($0)
            }
          ),
          boardTypes: boardTypes,
          manufacturers: manufacturers,
          showsCreationFlow: true
        ) {
          self.createdBoard = nil
          entryMode = nil
          pendingSchemeAttachments = []
          aiScanComplete = false
        }
      } else if entryMode == nil {
        NewBoardEntryChoiceView(theme: theme, back: onBackToHub) { mode in
          withAnimation(.easeOut(duration: 0.16)) {
            entryMode = mode
          }
        }
      } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if entryMode == .aiScan {
            NewBoardAIAssistantCard(
              theme: theme,
              attachments: $pendingSchemeAttachments,
              scanComplete: aiScanComplete,
              isScanning: aiScanning
            ) {
              runSchemeScan()
            }
          }

          CreationFormSection(theme: theme, title: "Progress", symbol: "point.3.connected.trianglepath.dotted") {
          NewBoardStepIndicator(theme: theme, currentStep: 1)
              .frame(height: 72)
          }

          if createdMessage {
            Label("Board draft created", systemImage: "checkmark.circle.fill")
              .font(.callout.bold())
              .foregroundStyle(Color(hex: 0x7FAE9A))
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color(hex: 0x7FAE9A).opacity(0.12))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          }

          CreationFormSection(theme: theme, title: "Board Identity", symbol: "rectangle.3.group.fill", subtitle: "Number, name and type") {
            CreationTextInput(theme: theme, title: "Board number", placeholder: "3918.24-1", symbol: "number", text: $boardNumber, keyboardType: .numbersAndPunctuation, capitalization: .characters)
            CreationTextInput(theme: theme, title: "Board group", placeholder: suggestedGroup.isEmpty ? "Optional group" : suggestedGroup, symbol: "rectangle.stack.fill", text: $boardGroup, keyboardType: .numbersAndPunctuation, capitalization: .characters)
          if !suggestedGroup.isEmpty && boardGroup != suggestedGroup {
              Button {
                boardGroup = suggestedGroup
              } label: {
                Label("Use group \(suggestedGroup)", systemImage: "wand.and.stars")
                  .font(.caption.bold())
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
              .foregroundStyle(theme.primary)
            }
            CreationTextInput(theme: theme, title: "Board name", placeholder: "Main LV Board", symbol: "textformat", text: $boardName, capitalization: .words)
            CreationPickerInput(theme: theme, title: "Board type", symbol: "square.grid.2x2.fill", value: boardType) {
              pickerSheet = .boardType
            }
            CreationPickerInput(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", value: boardSubtype) {
              pickerSheet = .subtype
            }
            CreationPickerInput(theme: theme, title: "Board manufacturer", symbol: "building.2.fill", value: boardManufacturer) {
              pickerSheet = .manufacturer
            }
            HStack(spacing: 10) {
              CreationMenuInput(theme: theme, title: "Cabinets", symbol: "cabinet.fill", value: cabinetCount, options: (1...12).map(String.init), selection: $cabinetCount)
              CreationMenuInput(theme: theme, title: "Build", symbol: "rectangle.split.2x1.fill", value: buildFormat, options: ["Panels", "Plate"], selection: $buildFormat)
            }
            CreationDateInput(theme: theme, title: "Out date", symbol: "calendar", selection: $boardDate, displayedComponents: .date)
            CreationToggleInput(theme: theme, title: "Add due date/time", symbol: "clock.badge.exclamationmark.fill", isOn: $hasDueDate)
            if hasDueDate {
              CreationDateInput(theme: theme, title: "Due", symbol: "clock.fill", selection: $boardDueDate, displayedComponents: [.date, .hourAndMinute])
            }
            CreationToggleInput(theme: theme, title: "Add finished date", symbol: "flag.checkered", isOn: $hasFinishDate)
            if hasFinishDate {
              CreationDateInput(theme: theme, title: "Finished date", symbol: "checkmark.seal.fill", selection: $boardFinishDate, displayedComponents: .date)
            }
            ColorSwatchPicker(title: "Board card color", selectedHex: $selectedBoardColorHex)
          }

          CreationFormSection(theme: theme, title: "Project & Customer", symbol: "folder.badge.person.crop") {
            CreationPickerInput(theme: theme, title: "Project", symbol: "folder.fill", value: project) {
              pickerSheet = .project
            }
            if project == "No Project" {
              CreationTextInput(theme: theme, title: "Customer name", placeholder: "Search or type customer", symbol: "person.crop.circle.fill", text: $customerName, capitalization: .words)
            } else {
              InfoLine(title: "Customer", value: customerName.isEmpty ? "From selected project" : customerName)
                .padding(12)
                .background(theme.surface.opacity(0.56))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            SuggestionChips(theme: theme, values: matchingRecentCustomers, selectedValue: customerName) { customerName = $0 }
          }

          CreationFormSection(theme: theme, title: "Company", symbol: "building.2.crop.circle") {
            CreationTextInput(theme: theme, title: "Company you are doing it for", placeholder: "Optional company", symbol: "building.2.fill", text: $companyName, capitalization: .words)
            SuggestionChips(theme: theme, values: matchingCompanyNames, selectedValue: companyName) { companyName = $0 }
          }
          BottomTabClearance(height: 118)
            }
      }
      .padding(18)
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .ignoresSafeArea(.keyboard, edges: .bottom)
      .navigationTitle("New Board")
      .sheet(item: $pickerSheet) { sheet in
        switch sheet {
        case .boardType:
          BoardTypeCreationPickerSheet(theme: theme, boardTypes: boardTypes, selected: boardType) { selected in
            boardType = selected
            if !BoardSubtypeCatalog.options(for: selected).contains(boardSubtype) {
              boardSubtype = BoardSubtypeCatalog.defaultSubtype
            }
          }
        case .subtype:
          CreationOptionPickerSheet(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", options: subtypeOptions, selected: boardSubtype) {
            boardSubtype = $0
          }
        case .manufacturer:
          ManufacturerCreationPickerSheet(theme: theme, manufacturers: manufacturers, selected: boardManufacturer) {
            boardManufacturer = $0
          }
        case .project:
          ProjectCreationPickerSheet(theme: theme, projects: projects, selected: project) { selected in
            project = selected
            if let selectedProject = projects.first(where: { $0.name == selected }) {
              customerName = selectedProject.customer
            } else if selected == "No Project" {
              customerName = ""
            }
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back") {
            if entryMode == nil {
              onBackToHub?()
            } else {
              entryMode = nil
              pendingSchemeAttachments = []
              aiScanComplete = false
              aiScanning = false
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Next") {
            mainBreakerOpen = true
          }
          .disabled(!canCreate)
          .fontWeight(.bold)
        }
      }
      .navigationDestination(isPresented: $mainBreakerOpen) {
        MainBreakerStepView(
          theme: theme,
          actionColor: Color(hex: selectedBoardColorHex),
          mainBreakerType: $mainBreakerType,
          mainBreakerModel: $mainBreakerModel,
          mainBreakerAmpere: $mainBreakerAmpere,
          manufacturerNames: manufacturerNames,
          manufacturers: manufacturers
        ) {
              let normalizedAmpere = mainBreakerAmpere.uppercased().hasSuffix("A") ? mainBreakerAmpere : "\(mainBreakerAmpere)A"
              let board = BoardDraft(
                id: "board-\(UUID().uuidString)",
                number: boardNumber,
                group: boardGroup,
                name: boardName,
                customer: customerName,
                company: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
                project: project,
                type: boardType,
                subtype: boardSubtype,
                manufacturer: boardManufacturer,
                ampere: normalizedAmpere,
                cabinetCount: cabinetCount,
                buildFormat: buildFormat,
                dateOut: boardDate,
                dueDate: hasDueDate ? boardDueDate : nil,
                finishDate: hasFinishDate ? boardFinishDate : nil,
                mainBreakerType: mainBreakerType,
                mainBreakerModel: mainBreakerModel.trimmingCharacters(in: .whitespacesAndNewlines),
                mainBreakerAmpere: normalizedAmpere,
                componentTypes: inferredComponentTypes(),
                color: Color(hex: selectedBoardColorHex),
                schemeAttachments: pendingSchemeAttachments
              )
              onCreate(board)
              mainBreakerOpen = false
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                createdBoard = board
              }
              boardNumber = ""
              boardGroup = ""
              boardName = ""
              customerName = ""
              companyName = ""
              project = "No Project"
              boardType = boardTypes.first?.name ?? "MDB"
              boardSubtype = BoardSubtypeCatalog.defaultSubtype
              boardManufacturer = manufacturerNames.first ?? "Generic"
              cabinetCount = "1"
              buildFormat = "Panels"
              boardDate = Date()
              hasDueDate = false
              boardDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
              hasFinishDate = false
              boardFinishDate = Date()
              mainBreakerType = "Main Breaker"
              mainBreakerModel = manufacturerNames.first ?? "ABB"
              mainBreakerAmpere = "630A"
              selectedBoardColorHex = 0x5E78FF
              pendingSchemeAttachments = []
              aiScanComplete = false
              createdMessage = true
          }
      }
      .onChange(of: boardNumber) { _ in
        if boardGroup.isEmpty {
          boardGroup = suggestedGroup
        }
        createdMessage = false
      }
      .onChange(of: boardName) { _ in
        createdMessage = false
      }
      .onChange(of: customerName) { _ in
        createdMessage = false
      }
      .onChange(of: companyName) { _ in
        createdMessage = false
      }
      .onChange(of: boardType) { _ in
        if !subtypeOptions.contains(boardSubtype) {
          boardSubtype = subtypeOptions.first ?? BoardSubtypeCatalog.defaultSubtype
        }
        createdMessage = false
      }
      .onChange(of: project) { newProject in
        if let selectedProject = projects.first(where: { $0.name == newProject }) {
          customerName = selectedProject.customer
        } else if newProject == "No Project" {
          customerName = ""
        }
      }
      }
    }
    .animation(.easeOut(duration: 0.16), value: entryMode)
    .animation(.easeOut(duration: 0.16), value: createdBoard?.id)
  }

  private func inferredComponentTypes() -> [String] {
    aiScanComplete ? ["Main Breaker", "MCB", "MCCB", "Contactor", "SPD", "Terminal Block", "Busbar", "Meter"] : []
  }

  private func applySchemeScan() {
    let schemeText = pendingSchemeAttachments.map(\.name).joined(separator: " ").lowercased()
    let projectMatch = projects.first { project in
      schemeText.localizedCaseInsensitiveContains(project.name) ||
      schemeText.localizedCaseInsensitiveContains(project.customer)
    }

    if let projectMatch {
      project = projectMatch.name
      customerName = projectMatch.customer
    } else if customerName.isEmpty, let customer = recentCustomers.first {
      customerName = customer
    }

    if boardNumber.isEmpty {
      boardNumber = normalizedBoardNumberFromSchemes()
    }
    if boardGroup.isEmpty {
      boardGroup = projectGroup(from: boardNumber)
    }
    if boardName.isEmpty {
      if schemeText.contains("ats") {
        boardName = "ATS Board"
        boardType = boardTypes.first { $0.name.localizedCaseInsensitiveContains("ATS") }?.name ?? boardType
      } else if schemeText.contains("mcc") || schemeText.contains("motor") {
        boardName = "MCC Board"
        boardType = boardTypes.first { $0.name.localizedCaseInsensitiveContains("MCC") }?.name ?? boardType
      } else if schemeText.contains("lighting") || schemeText.contains("light") {
        boardName = "Lighting Board"
        boardType = boardTypes.first { $0.name.localizedCaseInsensitiveContains("Lighting") }?.name ?? boardType
      } else {
        boardName = "Scanned Distribution Board"
        boardType = boardTypes.first?.name ?? boardType
      }
    }
    if schemeText.contains("abb") {
      boardManufacturer = manufacturerNames.first { $0.localizedCaseInsensitiveContains("ABB") } ?? boardManufacturer
      mainBreakerModel = boardManufacturer
    } else if schemeText.contains("schneider") {
      boardManufacturer = manufacturerNames.first { $0.localizedCaseInsensitiveContains("Schneider") } ?? boardManufacturer
      mainBreakerModel = boardManufacturer
    } else if schemeText.contains("hager") {
      boardManufacturer = manufacturerNames.first { $0.localizedCaseInsensitiveContains("HAGER") } ?? boardManufacturer
      mainBreakerModel = boardManufacturer
    }
    if schemeText.contains("1600") {
      mainBreakerAmpere = "1600A"
    } else if schemeText.contains("1250") {
      mainBreakerAmpere = "1250A"
    } else if schemeText.contains("800") {
      mainBreakerAmpere = "800A"
    } else if schemeText.contains("400") {
      mainBreakerAmpere = "400A"
    } else if schemeText.contains("250") {
      mainBreakerAmpere = "250A"
    } else if schemeText.contains("125") {
      mainBreakerAmpere = "125A"
    }
    mainBreakerType = mainBreakerAmpere.dropLast().compactMap(\.wholeNumberValue).count >= 3 ? "MCCB" : "MCB"
    aiScanComplete = true
  }

  private func runSchemeScan() {
    guard !aiScanning else { return }
    aiScanning = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
      applySchemeScan()
      aiScanning = false
      mainBreakerOpen = true
    }
  }

  private func normalizedBoardNumberFromSchemes() -> String {
    let source = pendingSchemeAttachments
      .map(\.name)
      .joined(separator: " ")
      .replacingOccurrences(of: "_", with: "-")
      .replacingOccurrences(of: "/", with: "-")

    if let match = source.range(of: #"\d{4}\.\d{2}-\d+"#, options: .regularExpression) {
      return String(source[match]).uppercased()
    }

    let cleaned = pendingSchemeAttachments.first?.name
      .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: ".jpg", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "_", with: "-")
      .replacingOccurrences(of: "/", with: "-") ?? "AI-\(Int(Date().timeIntervalSince1970))"
    return String(cleaned.prefix(18)).uppercased()
  }

  private func projectGroup(from boardNumber: String) -> String {
    guard let dashIndex = boardNumber.lastIndex(of: "-") else { return "" }
    return String(boardNumber[..<dashIndex])
  }
}

enum NewBoardEntryMode {
  case aiScan
  case manual
}

struct NewBoardEntryChoiceView: View {
  let theme: PanelTheme
  var back: (() -> Void)? = nil
  let choose: (NewBoardEntryMode) -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Create New Board")
              .font(.largeTitle.bold())
            Text("Start from a scheme, or enter the board manually.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Button {
            choose(.aiScan)
          } label: {
            NewBoardModeCard(
              theme: theme,
              symbol: "sparkles",
              title: "Scan Scheme with AI",
              subtitle: "Attach a PDF or photos. PanelVault builds the draft, components and scheme files for review.",
              color: theme.primary
            )
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            choose(.manual)
          } label: {
            NewBoardModeCard(
              theme: theme,
              symbol: "square.and.pencil",
              title: "Enter Manually",
              subtitle: "Use the normal board form when the scheme is not ready yet.",
              color: Color(hex: 0xAEB4BC)
            )
          }
          .buttonStyle(PanelPressButtonStyle())
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("New Board")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Back") {
            back?()
          }
        }
      }
    }
  }
}

struct NewBoardModeCard: View {
  let theme: PanelTheme
  let symbol: String
  let title: String
  let subtitle: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.system(size: 24, weight: .heavy))
          .foregroundStyle(color)
          .frame(width: 54, height: 54)
          .background(color.opacity(0.16))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        VStack(alignment: .leading, spacing: 5) {
          Text(title)
            .font(.title3.bold())
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct NewBoardAIAssistantCard: View {
  let theme: PanelTheme
  @Binding var attachments: [SchemeAttachment]
  let scanComplete: Bool
  let isScanning: Bool
  let scan: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles")
          .foregroundStyle(theme.primary)
        VStack(alignment: .leading, spacing: 3) {
          Text("AI Scheme Intake")
            .font(.headline)
          Text(scanComplete ? "Draft filled. Review the fields below before creating." : "Attach the scheme, then let PanelVault prepare the board draft.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }

      SchemeAttachmentSection(theme: theme, title: "Scheme Files", attachments: $attachments)

      Button(action: scan) {
        HStack {
          if isScanning {
            ProgressView()
              .tint(.white)
          } else {
            Image(systemName: scanComplete ? "arrow.clockwise" : "sparkles")
          }
          Text(isScanning ? "Scanning Scheme..." : (scanComplete ? "Scan Again" : "Scan and Fill Board"))
        }
        .font(.system(size: 16, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
      }
      .background(attachments.isEmpty || isScanning ? theme.surface.opacity(0.72) : theme.primary)
      .foregroundStyle(attachments.isEmpty ? Color.secondary : Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
      .disabled(attachments.isEmpty || isScanning)
      .buttonStyle(PanelPressButtonStyle())
    }
  }
}

struct MainBreakerStepView: View {
  let theme: PanelTheme
  let actionColor: Color
  @Binding var mainBreakerType: String
  @Binding var mainBreakerModel: String
  @Binding var mainBreakerAmpere: String
  let manufacturerNames: [String]
  let manufacturers: [ManufacturerItem]
  let create: () -> Void
  @State private var pickerSheet: MainBreakerPickerSheet?

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          CreationFormSection(theme: theme, title: "Progress", symbol: "point.3.connected.trianglepath.dotted") {
          NewBoardStepIndicator(theme: theme, currentStep: 2)
              .frame(height: 72)
          }

          CreationFormSection(theme: theme, title: "Main Breaker", symbol: "bolt.shield.fill", subtitle: "Choose the breaker details") {
            CreationMenuInput(theme: theme, title: "Breaker type", symbol: "bolt.fill", value: mainBreakerType, options: ["MCB", "RCBO", "MCCB", "ACB", "Switch Disconnector", "Fuse Switch"], selection: $mainBreakerType)
            CreationPickerInput(theme: theme, title: "Manufacturer", symbol: "building.2.fill", value: mainBreakerModel) {
              pickerSheet = .manufacturer
            }
            CreationPickerInput(theme: theme, title: "Ampere", symbol: "gauge.with.dots.needle.67percent", value: mainBreakerAmpere) {
              pickerSheet = .ampere
            }
          }
          BottomTabClearance(height: 24)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())

      Button(action: create) {
        HStack {
          Image(systemName: "checkmark.circle.fill")
          Text("Create Board")
        }
        .font(.system(size: 17, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      .background(actionColor)
      .foregroundStyle(.white)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .shadow(color: actionColor.opacity(0.24), radius: 14, y: 6)
      .padding(.horizontal, 18)
      .padding(.top, 10)
      .padding(.bottom, 108)
    }
    .background(theme.background.ignoresSafeArea())
    .navigationTitle("Main Breaker")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $pickerSheet) { sheet in
      switch sheet {
      case .manufacturer:
        ManufacturerCreationPickerSheet(theme: theme, manufacturers: manufacturers, selected: mainBreakerModel) {
          mainBreakerModel = $0
        }
      case .ampere:
        CreationOptionPickerSheet(theme: theme, title: "Ampere", symbol: "gauge.with.dots.needle.67percent", options: AmpereRating.all, selected: mainBreakerAmpere) {
          mainBreakerAmpere = $0
        }
      }
    }
  }
}

enum MainBreakerPickerSheet: String, Identifiable {
  case manufacturer
  case ampere

  var id: String { rawValue }
}

struct NewBoardStepIndicator: View {
  let theme: PanelTheme
  let currentStep: Int

  private let steps = [
    (number: 1, title: "Board", symbol: "rectangle.3.group.fill"),
    (number: 2, title: "Breaker", symbol: "bolt.shield.fill"),
    (number: 3, title: "Finish", symbol: "checkmark.circle.fill")
  ]

  var body: some View {
    GeometryReader { proxy in
      let sideInset: CGFloat = 34
      let availableWidth = max(proxy.size.width - sideInset * 2, 1)
      let gap = availableWidth / CGFloat(max(steps.count - 1, 1))

      ZStack(alignment: .topLeading) {
        ForEach(0..<(steps.count - 1), id: \.self) { index in
          Capsule()
            .fill(index + 1 < currentStep ? theme.primary : theme.surface.opacity(0.82))
            .frame(width: max(gap - 42, 1), height: 4)
            .offset(x: sideInset + CGFloat(index) * gap + 21, y: 17)
        }

        ForEach(Array(steps.enumerated()), id: \.element.number) { index, step in
          VStack(spacing: 7) {
            ZStack {
              Circle()
                .fill(step.number <= currentStep ? theme.primary : theme.surface.opacity(0.92))
                .frame(width: 34, height: 34)
              Text("\(step.number)")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(step.number <= currentStep ? .white : .secondary)
            }
            Text(step.title)
              .font(.system(size: 11, weight: .heavy))
              .foregroundStyle(step.number <= currentStep ? .primary : .secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(width: 68)
          .offset(x: sideInset + CGFloat(index) * gap - 34, y: 0)
        }
      }
    }
    .frame(height: 58)
    .padding(.vertical, 8)
    .animation(.easeOut(duration: 0.16), value: currentStep)
  }
}

struct CreatedBoardScreen: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  var boardTypes: [BoardType] = BoardType.samples
  var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  var showsCreationFlow = false
  var onDeleteBoard: (() -> Void)? = nil
  let createAnother: () -> Void
  @State private var catalogOpen = false
  @State private var componentTypes: [String] = []
  @State private var addedComponentsByType: [String: [PanelComponent]] = [:]
  @State private var completedChecklistItems: Set<String> = []
  @State private var personalChecklistItems: [PersonalChecklistItem] = []
  @State private var localBoardLoaded = false
  @State private var pendingBoardSyncWorkItem: DispatchWorkItem?
  @State private var selectedComponentType: String?
  @State private var editOpen = false

  private var displayBoard: BoardDraft {
    var copy = board
    copy.componentTypes = componentTypes
    copy.completedChecklistItems = completedChecklistItems
    copy.personalChecklistItems = personalChecklistItems
    return copy
  }

  private var visibleComponentTypes: [String] {
    let types = Set(componentTypes).union(addedComponentsByType.keys)
    return types.isEmpty ? board.componentTypes : Array(types).sorted()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if showsCreationFlow {
          NewBoardStepIndicator(theme: theme, currentStep: 3)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(board.name)
            .font(.largeTitle.bold())
          Text(board.number)
            .font(.headline)
            .foregroundStyle(.secondary)
        }

        BoardCoverPhotoSection(theme: theme, selectedImage: $board.coverImage)

        BoardPropertiesOverview(theme: theme, board: displayBoard, manufacturers: manufacturers) {
          editOpen = true
        }

        ChecklistProgressSection(theme: theme, title: "Completion Progress", items: ChecklistTemplate.items(for: board.cabinetCount), checkedItems: $completedChecklistItems)
          .onChange(of: completedChecklistItems) { _ in
            scheduleBoardSync()
          }
        PersonalChecklistSection(theme: theme, items: $personalChecklistItems)
          .onChange(of: personalChecklistItems) { _ in
            scheduleBoardSync()
          }
        SchemeAttachmentSection(theme: theme, attachments: $board.schemeAttachments)
        PhotoPickerSection(theme: theme, title: "Board Photos", selectedImages: $board.photoImages, coverImage: $board.coverImage)
        componentsSection

        if showsCreationFlow {
          Button(action: createAnother) {
            HStack(spacing: 12) {
              Image(systemName: "plus.circle.fill")
                .font(.system(size: 26, weight: .bold))
              VStack(alignment: .leading, spacing: 3) {
                Text("Create Another Board")
                  .font(.system(size: 17, weight: .heavy))
                Text("Start a clean board draft")
                  .font(.caption)
                  .foregroundStyle(.white.opacity(0.78))
              }
              Spacer()
              Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .heavy))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
              LinearGradient(
                colors: [theme.primary, theme.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: theme.primary.opacity(0.24), radius: 16, y: 8)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(18)
    }
    .background(theme.background.ignoresSafeArea())
    .overlay(alignment: .top) {
      TopScrollBlur(theme: theme)
    }
    .navigationTitle(board.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        if showsCreationFlow {
          Button("Done") {
            createAnother()
          }
          .fontWeight(.bold)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") {
          withAnimation(.easeInOut(duration: 0.24)) {
            editOpen = true
          }
        }
        .fontWeight(.bold)
      }
    }
    .sheet(isPresented: $editOpen) {
      BoardEditSheet(theme: theme, board: $board, boardTypes: boardTypes, manufacturers: manufacturers, onDelete: onDeleteBoard)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
    .fullScreenCover(isPresented: $catalogOpen) {
      NavigationStack {
        ScrollView {
          ComponentCatalogView(theme: theme, groups: ComponentGroup.samples, manufacturers: manufacturers, onAddComponent: { component in
            if !componentTypes.contains(component.type) {
              componentTypes.append(component.type)
            }
            var components = addedComponentsByType[component.type] ?? []
            if !components.contains(where: { $0.id == component.id }) {
              components.append(component)
              addedComponentsByType[component.type] = components
            }
            scheduleBoardSync()
          })
            .padding(18)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Add Components")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
              catalogOpen = false
            }
            .fontWeight(.bold)
          }
        }
      }
    }
    .sheet(item: Binding(
      get: { selectedComponentType.map(ComponentTypeSelection.init(type:)) },
      set: { selectedComponentType = $0?.type }
    )) { selection in
      ComponentTypeCatalogSheet(
        theme: theme,
        type: selection.type,
        components: components(for: selection.type),
        manufacturers: manufacturers
      )
    }
    .onAppear {
      loadLocalBoardIfNeeded()
    }
    .onDisappear {
      flushBoardSync()
    }
  }

  private var componentsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Components")
          .font(.headline)
        Spacer()
        Button {
          catalogOpen = true
        } label: {
          Label("Add", systemImage: "plus")
            .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
      }

      if visibleComponentTypes.isEmpty {
        EmptyStateCard(theme: theme, title: "No components yet", subtitle: "Add MCBs, contactors, VFDs, PSUs, busbars and more from the catalog.")
      } else {
        ForEach(visibleComponentTypes, id: \.self) { type in
          GlassCard(theme: theme) {
            HStack {
              Image(systemName: "shippingbox.fill")
                .foregroundStyle(theme.primary)
              VStack(alignment: .leading, spacing: 3) {
                Text(type)
                  .font(.headline)
                Text(componentCountText(for: type))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              HStack(spacing: 8) {
                DeleteIconButton(theme: theme) {
                  componentTypes.removeAll { $0 == type }
                  addedComponentsByType.removeValue(forKey: type)
                  scheduleBoardSync()
                }
                Button {
                  selectedComponentType = type
                } label: {
                  Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
    }
  }

  private func components(for type: String) -> [PanelComponent] {
    if let components = addedComponentsByType[type], !components.isEmpty {
      return components
    }
    return ComponentGroup.samples
      .flatMap(\.items)
      .filter { $0.type.localizedCaseInsensitiveCompare(type) == .orderedSame }
  }

  private func componentCountText(for type: String) -> String {
    let count = addedComponentsByType[type]?.count ?? (board.componentTypes.contains(type) ? 1 : 0)
    return "\(count) catalog item\(count == 1 ? "" : "s")"
  }

  private func loadLocalBoardIfNeeded() {
    guard !localBoardLoaded else { return }
    localBoardLoaded = true
    componentTypes = board.componentTypes
    completedChecklistItems = board.completedChecklistItems
    personalChecklistItems = board.personalChecklistItems
  }

  private func scheduleBoardSync() {
    pendingBoardSyncWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      flushBoardSync()
    }
    pendingBoardSyncWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: workItem)
  }

  private func flushBoardSync() {
    pendingBoardSyncWorkItem?.cancel()
    pendingBoardSyncWorkItem = nil
    board.componentTypes = componentTypes
    board.completedChecklistItems = completedChecklistItems
    board.personalChecklistItems = personalChecklistItems
  }
}

struct ComponentTypeSelection: Identifiable {
  let type: String
  var id: String { type }
}

struct BoardEditSheet: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  var onDelete: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          CreationFormSection(theme: theme, title: "Board Details", symbol: "rectangle.3.group.fill", subtitle: "Identity and customer") {
            CreationTextInput(theme: theme, title: "Board name", placeholder: "Board name", symbol: "textformat", text: $board.name, capitalization: .words)
            CreationTextInput(theme: theme, title: "Board number", placeholder: "3918.24-1", symbol: "number", text: $board.number, keyboardType: .numbersAndPunctuation, capitalization: .characters)
            CreationTextInput(theme: theme, title: "Customer", placeholder: "Customer", symbol: "person.crop.circle.fill", text: $board.customer, capitalization: .words)
            CreationTextInput(theme: theme, title: "Company", placeholder: "Company", symbol: "building.2.fill", text: $board.company, capitalization: .words)
          }

          CreationFormSection(theme: theme, title: "Board Setup", symbol: "slider.horizontal.3") {
            CreationMenuInput(theme: theme, title: "Board type", symbol: "square.grid.2x2.fill", value: board.type, options: boardTypeNames, selection: boardTypeBinding)
            CreationMenuInput(theme: theme, title: "Subtype", symbol: "rectangle.grid.1x2.fill", value: board.subtype, options: BoardSubtypeCatalog.options(for: board.type), selection: subtypeBinding)
            CreationMenuInput(theme: theme, title: "Manufacturer", symbol: "building.2.fill", value: board.manufacturer, options: manufacturerNames, selection: manufacturerBinding)
            HStack(spacing: 10) {
              CreationMenuInput(theme: theme, title: "Cabinets", symbol: "cabinet.fill", value: board.cabinetCount, options: (1...12).map(String.init), selection: $board.cabinetCount)
              CreationMenuInput(theme: theme, title: "Build", symbol: "rectangle.split.2x1.fill", value: board.buildFormat, options: ["Panels", "Plate"], selection: $board.buildFormat)
            }
            CreationDateInput(theme: theme, title: "Out date", symbol: "calendar", selection: $board.dateOut, displayedComponents: .date)
            CreationToggleInput(theme: theme, title: "Has due date/time", symbol: "clock.badge.exclamationmark.fill", isOn: dueDateEnabled)
            if board.dueDate != nil {
              CreationDateInput(theme: theme, title: "Due", symbol: "clock.fill", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
            }
            CreationToggleInput(theme: theme, title: "Has finished date", symbol: "flag.checkered", isOn: finishDateEnabled)
            if board.finishDate != nil {
              CreationDateInput(theme: theme, title: "Finished date", symbol: "checkmark.seal.fill", selection: finishDateBinding, displayedComponents: .date)
            }
            CreationTextInput(theme: theme, title: "Finish time", placeholder: "Hours", symbol: "timer", text: $board.finishTimeHours, keyboardType: .decimalPad)
            BoardColorEditPicker(title: "Card color", color: $board.color)
          }

          CreationFormSection(theme: theme, title: "Main Breaker", symbol: "bolt.shield.fill") {
            CreationMenuInput(theme: theme, title: "Main breaker", symbol: "bolt.fill", value: board.mainBreakerType, options: ["MCB", "RCBO", "MCCB", "ACB", "Switch Disconnector", "Fuse Switch"], selection: $board.mainBreakerType)
            CreationMenuInput(theme: theme, title: "Model or family", symbol: "building.2.fill", value: board.mainBreakerModel, options: manufacturerNames, selection: $board.mainBreakerModel)
            CreationMenuInput(theme: theme, title: "Ampere", symbol: "gauge.with.dots.needle.67percent", value: board.mainBreakerAmpere, options: AmpereRating.all, selection: ampereBinding)
          }

          if let onDelete {
            DeleteRecordButton(title: "Delete Board", itemName: board.name) {
              onDelete()
              dismiss()
            }
            .padding(.top, 8)
          }
          BottomTabClearance(height: 84)
        }
        .padding(18)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Edit Board")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }

  private var ampereBinding: Binding<String> {
    Binding {
      board.mainBreakerAmpere
    } set: { value in
      board.mainBreakerAmpere = value
      board.ampere = value.uppercased().hasSuffix("A") ? value : "\(value)A"
    }
  }

  private var manufacturerBinding: Binding<String> {
    Binding {
      manufacturerNames.contains(board.manufacturer) ? board.manufacturer : board.manufacturer
    } set: { value in
      board.manufacturer = value
    }
  }

  private var manufacturerNames: [String] {
    let names = manufacturers.map(\.name) + ManufacturerItem.defaults.map(\.name) + EquipmentCompany.all + [board.manufacturer, board.mainBreakerModel]
    return Array(Set(names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var boardTypeNames: [String] {
    let names = boardTypes.map(\.name) + BoardType.samples.map(\.name) + [board.type]
    return Array(Set(names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
  }

  private var boardTypeBinding: Binding<String> {
    Binding {
      board.type
    } set: { value in
      board.type = value
      if !BoardSubtypeCatalog.options(for: value).contains(board.subtype) {
        board.subtype = BoardSubtypeCatalog.defaultSubtype
      }
    }
  }

  private var subtypeBinding: Binding<String> {
    Binding {
      let options = BoardSubtypeCatalog.options(for: board.type)
      return options.contains(board.subtype) ? board.subtype : BoardSubtypeCatalog.defaultSubtype
    } set: { value in
      board.subtype = value
    }
  }

  private var finishDateEnabled: Binding<Bool> {
    Binding {
      board.finishDate != nil
    } set: { enabled in
      board.finishDate = enabled ? (board.finishDate ?? Date()) : nil
    }
  }

  private var finishDateBinding: Binding<Date> {
    Binding {
      board.finishDate ?? Date()
    } set: { value in
      board.finishDate = value
    }
  }

  private var dueDateEnabled: Binding<Bool> {
    Binding {
      board.dueDate != nil
    } set: { enabled in
      board.dueDate = enabled ? (board.dueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()) : nil
    }
  }

  private var dueDateBinding: Binding<Date> {
    Binding {
      board.dueDate ?? Date()
    } set: { value in
      board.dueDate = value
    }
  }
}

struct BoardColorEditPicker: View {
  let title: String
  @Binding var color: Color
  @State private var selectedHex: UInt32 = 0x5E78FF

  var body: some View {
    ColorSwatchPicker(title: title, selectedHex: Binding(
      get: { selectedHex },
      set: { newValue in
        selectedHex = newValue
        color = Color(hex: newValue)
      }
    ))
    .onAppear {
      selectedHex = color.archiveHex
    }
  }
}

struct BoardCoverPhotoSection: View {
  let theme: PanelTheme
  @State private var selectedItem: PhotosPickerItem?
  @State private var displayMode = "Fill"
  @State private var previewImage: ImagePreviewItem?
  @State private var editorImage: ImagePreviewItem?
  @Binding var selectedImage: UIImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if selectedImage == nil {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          CoverPhotoView(
            theme: theme,
            image: selectedImage,
            displayMode: displayMode,
            title: "Add Board Picture",
            subtitle: "Tap to choose the board cover photo"
          )
        }
        .buttonStyle(.plain)
      } else {
        CoverPhotoView(
          theme: theme,
          image: selectedImage,
          displayMode: displayMode,
          title: "Board Picture Added",
          subtitle: "View, adjust or replace below"
        )
        .onTapGesture {
          if let selectedImage {
            previewImage = ImagePreviewItem(image: selectedImage)
          }
        }
      }

      if selectedImage != nil {
        Picker("Photo view", selection: $displayMode) {
          ForEach(["Fill", "Fit"], id: \.self) { Text($0) }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 14) {
          Button {
            if let selectedImage {
              previewImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("View", systemImage: "photo.fill")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Button {
            if let selectedImage {
              editorImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("Adjust", systemImage: "crop")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(theme.primary)

        Button {
          selectedImage = nil
        } label: {
          Label("Remove Board Picture", systemImage: "xmark.circle.fill")
            .font(.caption.bold())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: 0xD66A6A))
      }
    }
    .onChange(of: selectedItem) { item in
      loadImage(from: item)
    }
    .sheet(item: $previewImage) { item in
      ImagePreviewSheet(image: item.image)
    }
    .sheet(item: $editorImage) { item in
      CoverPhotoEditorSheet(theme: theme, image: item.image) { adjustedImage in
        selectedImage = adjustedImage
      }
    }
  }

  private func loadImage(from item: PhotosPickerItem?) {
    Task {
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else { return }
      await MainActor.run {
        selectedImage = image
        selectedItem = nil
      }
    }
  }
}

struct ProjectCoverPhotoSection: View {
  let theme: PanelTheme
  @State private var selectedItem: PhotosPickerItem?
  @State private var displayMode = "Fill"
  @State private var previewImage: ImagePreviewItem?
  @State private var editorImage: ImagePreviewItem?
  @Binding var selectedImage: UIImage?
  var onImageChange: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if selectedImage == nil {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          CoverPhotoView(
            theme: theme,
            image: selectedImage,
            displayMode: displayMode,
            title: "Add Project Picture",
            subtitle: "Tap to choose the project cover photo"
          )
        }
        .buttonStyle(.plain)
      } else {
        CoverPhotoView(
          theme: theme,
          image: selectedImage,
          displayMode: displayMode,
          title: "Project Picture Added",
          subtitle: "View, adjust or replace below"
        )
        .onTapGesture {
          if let selectedImage {
            previewImage = ImagePreviewItem(image: selectedImage)
          }
        }
      }

      if selectedImage != nil {
        Picker("Photo view", selection: $displayMode) {
          ForEach(["Fill", "Fit"], id: \.self) { Text($0) }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 14) {
          Button {
            if let selectedImage {
              previewImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("View", systemImage: "photo.fill")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Button {
            if let selectedImage {
              editorImage = ImagePreviewItem(image: selectedImage)
            }
          } label: {
            Label("Adjust", systemImage: "crop")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(theme.primary)

        Button {
          selectedImage = nil
          onImageChange()
        } label: {
          Label("Remove Project Picture", systemImage: "xmark.circle.fill")
            .font(.caption.bold())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: 0xD66A6A))
      }
    }
    .onChange(of: selectedItem) { item in
      loadImage(from: item)
    }
    .sheet(item: $previewImage) { item in
      ImagePreviewSheet(image: item.image)
    }
    .sheet(item: $editorImage) { item in
      CoverPhotoEditorSheet(theme: theme, image: item.image) { adjustedImage in
        selectedImage = adjustedImage
        onImageChange()
      }
    }
  }

  private func loadImage(from item: PhotosPickerItem?) {
    Task {
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else { return }
      await MainActor.run {
        selectedImage = image
        selectedItem = nil
        onImageChange()
      }
    }
  }
}

struct CoverPhotoView: View {
  let theme: PanelTheme
  let image: UIImage?
  var displayMode = "Fill"
  let title: String
  let subtitle: String

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(image == nil ? theme.surface.opacity(0.78) : theme.primary.opacity(0.18))

      if let image {
        Group {
          if displayMode == "Fit" {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
          } else {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipped()

        Label(displayMode, systemImage: displayMode == "Fit" ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
          .font(.caption.bold())
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(.black.opacity(0.48))
          .clipShape(Capsule())
          .padding(10)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "camera.fill")
            .font(.title2)
          Text(title)
            .font(.headline)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(height: 150)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

struct CoverPhotoEditorSheet: View {
  let theme: PanelTheme
  let image: UIImage
  let onApply: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var zoom = 1.0
  @State private var horizontalOffset = 0.0
  @State private var verticalOffset = 0.0

  var body: some View {
    NavigationStack {
      VStack(spacing: 18) {
        Text("Adjust Cover")
          .font(.title2.bold())
          .frame(maxWidth: .infinity, alignment: .leading)

        ZStack {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(theme.surface.opacity(0.84))
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(zoom)
            .offset(x: horizontalOffset * 90, y: verticalOffset * 55)
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipped()
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(theme.primary.opacity(0.24), lineWidth: 1)
        )

        VStack(spacing: 14) {
          sliderRow(title: "Zoom", value: $zoom, range: 1...2.6, systemImage: "plus.magnifyingglass")
          sliderRow(title: "Left / Right", value: $horizontalOffset, range: -1...1, systemImage: "arrow.left.and.right")
          sliderRow(title: "Up / Down", value: $verticalOffset, range: -1...1, systemImage: "arrow.up.and.down")
        }

        Button {
          onApply(renderAdjustedImage())
          dismiss()
        } label: {
          Label("Use This Crop", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .background(theme.primary)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .buttonStyle(PanelPressButtonStyle())

        Spacer()
      }
      .padding(18)
      .background(theme.background.ignoresSafeArea())
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, systemImage: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: systemImage)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Slider(value: value, in: range)
        .tint(theme.primary)
    }
  }

  private func renderAdjustedImage() -> UIImage {
    let canvasSize = CGSize(width: 1200, height: 675)
    let imageSize = image.size
    let baseScale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
    let drawSize = CGSize(width: imageSize.width * baseScale * zoom, height: imageSize.height * baseScale * zoom)
    let origin = CGPoint(
      x: (canvasSize.width - drawSize.width) / 2 + horizontalOffset * canvasSize.width * 0.18,
      y: (canvasSize.height - drawSize.height) / 2 + verticalOffset * canvasSize.height * 0.18
    )

    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    return renderer.image { _ in
      UIColor.black.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
      image.draw(in: CGRect(origin: origin, size: drawSize))
    }
  }
}

struct ComponentTypeCatalogSheet: View {
  let theme: PanelTheme
  let type: String
  let components: [PanelComponent]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @AppStorage("panelvault.componentImages") private var savedComponentImages = ""
  @State private var componentImages: [String: UIImage] = [:]
  @State private var selectedComponent: PanelComponent?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if components.isEmpty {
            EmptyStateCard(theme: theme, title: "No \(type) items yet", subtitle: "Add exact \(type) items from the equipment catalog.")
          }

          ForEach(components) { component in
            let image = storedImage(for: component)
            ComponentRow(
              theme: theme,
              component: component,
              manufacturer: manufacturer(for: component.manufacturer),
              storedImage: image,
              isAdded: true,
              hasPhoto: image != nil
            ) {
            } togglePhoto: {
            } savePhoto: { image in
              componentImages[component.imageStorageID] = image
              persistComponentImages()
            } showDetails: {
              selectedComponent = component
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(type)
      .onAppear {
        if componentImages.isEmpty {
          componentImages = ComponentImageArchive.decode(savedComponentImages)
        }
      }
      .sheet(item: $selectedComponent) { component in
        ComponentDetailSheet(
          theme: theme,
          component: component,
          manufacturer: manufacturer(for: component.manufacturer),
          image: storedImage(for: component),
          onSaveImage: { image in
            componentImages[component.imageStorageID] = image
            persistComponentImages()
          },
          onRemoveImage: {
            component.imageLookupIDs.forEach { componentImages.removeValue(forKey: $0) }
            persistComponentImages()
          }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func manufacturer(for name: String) -> ManufacturerItem? {
    manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
  }

  private func storedImage(for component: PanelComponent) -> UIImage? {
    component.imageLookupIDs.lazy.compactMap { componentImages[$0] }.first
  }

  private func persistComponentImages() {
    savedComponentImages = ComponentImageArchive.encode(componentImages)
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

enum ChecklistTemplate {
  static let singleCabinet = [
    ChecklistItem(title: "Cable holders", weight: 5),
    ChecklistItem(title: "DIN rails", weight: 5),
    ChecklistItem(title: "Components", weight: 5),
    ChecklistItem(title: "Wiring", weight: 30),
    ChecklistItem(title: "N + PE bars", weight: 20),
    ChecklistItem(title: "Mask busbars", weight: 5),
    ChecklistItem(title: "Ground door", weight: 10),
    ChecklistItem(title: "Naming", weight: 10),
    ChecklistItem(title: "Tray ears and cylinder", weight: 5),
    ChecklistItem(title: "Scheme holder", weight: 5)
  ]

  static let multiCabinet = [
    ChecklistItem(title: "Building - Busbars", weight: 10),
    ChecklistItem(title: "Building - Components", weight: 10),
    ChecklistItem(title: "Building - DIN and cable holders", weight: 10),
    ChecklistItem(title: "Wiring", weight: 30),
    ChecklistItem(title: "Naming and finishing", weight: 10),
    ChecklistItem(title: "Stickers", weight: 5),
    ChecklistItem(title: "Scheme holder", weight: 5),
    ChecklistItem(title: "N + PE bars", weight: 20),
  ]

  static func items(for cabinetCount: String) -> [ChecklistItem] {
    (Int(cabinetCount) ?? 1) > 1 ? multiCabinet : singleCabinet
  }
}

struct ChecklistItem: Identifiable, Hashable {
  let title: String
  let weight: Int

  var id: String { title }
}

struct ChecklistProgressSection: View {
  let theme: PanelTheme
  let title: String
  let items: [ChecklistItem]
  @Binding var checkedItems: Set<String>

  private var sortedItems: [ChecklistItem] {
    items
  }

  private var totalWeight: Int {
    max(items.map(\.weight).reduce(0, +), 1)
  }

  private var completedWeight: Int {
    items
      .filter { checkedItems.contains($0.id) }
      .map(\.weight)
      .reduce(0, +)
  }

  private var completion: Int {
    Int((Double(completedWeight) / Double(totalWeight) * 100).rounded())
  }

  private var progress: CGFloat {
    min(max(CGFloat(completion) / 100, 0), 1)
  }

  private var progressColor: Color {
    let value = min(max(Double(completion) / 100, 0), 1)
    return Color(red: 1.0 - value * 0.78, green: 0.22 + value * 0.66, blue: 0.20 + value * 0.08)
  }

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(title, systemImage: "checklist.checked")
            .font(.headline)
          Spacer()
          Text("\(completion)%")
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(progressColor)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.22), value: completion)
        }

        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(theme.background.opacity(0.72))
            Capsule()
              .fill(
                LinearGradient(
                  colors: [progressColor.opacity(0.72), progressColor],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: max(proxy.size.width * progress, progress > 0 ? 14 : 0))
              .shadow(color: progressColor.opacity(0.32), radius: 8, y: 2)
              .animation(.easeOut(duration: 0.22), value: progress)
              .animation(.easeOut(duration: 0.22), value: completion)
          }
        }
        .frame(height: 10)

        VStack(spacing: 8) {
          ForEach(sortedItems) { item in
            Button {
              withAnimation(.easeOut(duration: 0.16)) {
                if checkedItems.contains(item.id) {
                  checkedItems.remove(item.id)
                } else {
                  checkedItems.insert(item.id)
                }
              }
            } label: {
              HStack {
                Image(systemName: checkedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(checkedItems.contains(item.id) ? progressColor : .secondary)
                  .scaleEffect(checkedItems.contains(item.id) ? 1.08 : 1)
                Text(item.title)
                  .foregroundStyle(.primary)
                Spacer()
              }
              .padding(12)
              .background(theme.surface.opacity(0.78))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PanelPressButtonStyle())
          }
        }
      }
      .animation(.easeOut(duration: 0.22), value: completion)
    }
  }
}

struct PersonalChecklistSection: View {
  let theme: PanelTheme
  @Binding var items: [PersonalChecklistItem]
  @State private var newItemTitle = ""

  private var canAdd: Bool {
    !newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Personal Checklist")
          .font(.headline)
        Spacer()
        Text("\(items.filter(\.isDone).count)/\(items.count)")
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }

      GlassCard(theme: theme) {
        HStack(spacing: 10) {
          TextField("Add reminder item", text: $newItemTitle)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit(addItem)
          Button {
            addItem()
          } label: {
            Image(systemName: "plus.circle.fill")
              .font(.title3)
              .foregroundStyle(canAdd ? theme.primary : .secondary)
          }
          .buttonStyle(.plain)
          .disabled(!canAdd)
        }
      }

      if items.isEmpty {
        EmptyStateCard(theme: theme, title: "Nothing to remember yet", subtitle: "Add your own reminders for this board.")
      } else {
        VStack(spacing: 8) {
          ForEach($items) { $item in
            HStack(spacing: 10) {
              Button {
                item.isDone.toggle()
              } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(item.isDone ? theme.primary : .secondary)
                  .font(.system(size: 18, weight: .semibold))
              }
              .buttonStyle(.plain)

              Text(item.title)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .strikethrough(item.isDone, color: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

              DeleteIconButton(theme: theme) {
                items.removeAll { $0.id == item.id }
              }
            }
            .padding(12)
            .background(theme.surface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
      }
    }
  }

  private func addItem() {
    let trimmedTitle = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }
    items.append(PersonalChecklistItem(title: trimmedTitle))
    newItemTitle = ""
  }
}

struct SchemeAttachmentSection: View {
  let theme: PanelTheme
  var title = "Schemes"
  @Binding var attachments: [SchemeAttachment]
  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var pdfImporterOpen = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        HStack(spacing: 8) {
          PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
            Image(systemName: "photo.on.rectangle")
              .font(.system(size: 15, weight: .bold))
              .frame(width: 34, height: 34)
              .background(theme.primary.opacity(0.14))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)

          Button {
            pdfImporterOpen = true
          } label: {
            Image(systemName: "doc.badge.plus")
              .font(.system(size: 15, weight: .bold))
              .frame(width: 34, height: 34)
              .background(theme.primary.opacity(0.14))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(theme.primary)
      }

      if attachments.isEmpty {
        EmptyStateCard(theme: theme, title: "No schemes yet", subtitle: "Add a PDF or choose photos. Photos are saved here as scheme files.")
      } else {
        VStack(spacing: 8) {
          ForEach(attachments) { attachment in
            SchemeAttachmentRow(theme: theme, attachment: attachment) {
              attachments.removeAll { $0.id == attachment.id }
            }
          }
        }
      }
    }
    .onChange(of: selectedPhotos) { items in
      loadSchemePhotos(items)
    }
    .fileImporter(
      isPresented: $pdfImporterOpen,
      allowedContentTypes: [.pdf],
      allowsMultipleSelection: true
    ) { result in
      if case .success(let urls) = result {
        let newItems = urls.map { url in
          let savedURL = Self.persistPDF(url)
          return SchemeAttachment(kind: .pdf, name: url.lastPathComponent, image: nil, url: savedURL ?? url)
        }
        attachments.append(contentsOf: newItems)
      }
    }
  }

  private static func persistPDF(_ url: URL) -> URL? {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let folder = documents.appendingPathComponent("PanelVault Schemes", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = folder.appendingPathComponent(url.lastPathComponent)
    if FileManager.default.fileExists(atPath: destination.path) {
      try? FileManager.default.removeItem(at: destination)
    }
    do {
      try FileManager.default.copyItem(at: url, to: destination)
      return destination
    } catch {
      return nil
    }
  }

  private func loadSchemePhotos(_ items: [PhotosPickerItem]) {
    Task {
      var newItems: [SchemeAttachment] = []
      for (index, item) in items.enumerated() {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
          newItems.append(
            SchemeAttachment(
              kind: .photo,
              name: "Scheme photo \(attachments.count + index + 1).jpg",
              image: image,
              url: nil
            )
          )
        }
      }
      await MainActor.run {
        attachments.append(contentsOf: newItems)
        selectedPhotos = []
      }
    }
  }
}

struct SchemeAttachmentRow: View {
  let theme: PanelTheme
  let attachment: SchemeAttachment
  let onDelete: () -> Void
  @Environment(\.openURL) private var openURL

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(attachment.kind == .pdf ? Color(hex: 0xFF4E5F).opacity(0.18) : theme.primary.opacity(0.18))
          if let image = attachment.image {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 44, height: 54)
              .clipped()
          } else {
            Image(systemName: "doc.richtext.fill")
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(Color(hex: 0xFF4E5F))
          }
        }
        .frame(width: 44, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text(attachment.name)
            .font(.headline)
            .lineLimit(1)
          Text(attachment.kind == .pdf ? "PDF scheme" : "Photo scheme file")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let url = attachment.url {
          Button {
            let didAccess = url.startAccessingSecurityScopedResource()
            openURL(url)
            if didAccess {
              DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                url.stopAccessingSecurityScopedResource()
              }
            }
          } label: {
            Image(systemName: "arrow.up.forward.app.fill")
              .foregroundStyle(theme.primary)
              .frame(width: 32, height: 32)
          }
          .buttonStyle(.plain)
        }
        DeleteIconButton(theme: theme, action: onDelete)
      }
    }
  }
}

struct PhotoPickerSection: View {
  let theme: PanelTheme
  let title: String
  @Binding var selectedImages: [UIImage]
  @Binding var coverImage: UIImage?
  @State private var selectedItems: [PhotosPickerItem] = []
  @State private var previewImage: ImagePreviewItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        PhotosPicker(selection: $selectedItems, maxSelectionCount: 30, matching: .images) {
          Label("Add Photos", systemImage: "camera.fill")
            .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
      }

      if selectedImages.isEmpty {
        EmptyStateCard(theme: theme, title: "No photos yet", subtitle: "Tap Add Photos to choose pictures from your phone.")
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
          ForEach(selectedImages.indices, id: \.self) { index in
            ZStack(alignment: .topTrailing) {
              GeometryReader { proxy in
                Button {
                  if selectedImages.indices.contains(index) {
                    previewImage = ImagePreviewItem(image: selectedImages[index])
                  }
                } label: {
                  Image(uiImage: selectedImages[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .clipped()
                }
                .buttonStyle(.plain)
              }
              Button {
                if selectedImages.indices.contains(index) {
                  selectedImages.remove(at: index)
                }
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 18, weight: .bold))
                  .foregroundStyle(.white, Color(hex: 0xD66A6A))
                  .padding(5)
              }
              .buttonStyle(.plain)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
      }
    }
    .onChange(of: selectedItems) { items in
      loadImages(from: items)
    }
    .sheet(item: $previewImage) { item in
      ImagePreviewSheet(image: item.image)
    }
  }

  private func loadImages(from items: [PhotosPickerItem]) {
    Task {
      var images: [UIImage] = []
      for item in items {
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = await Task.detached(priority: .userInitiated, operation: {
             guard let decodedImage = UIImage(data: data) else { return nil as UIImage? }
             let preparedImage = ImageArchive.preparedForStorage(decodedImage)
             ImageArchive.warmCache(for: preparedImage)
             return preparedImage
           }).value {
          images.append(image)
        }
      }
      await MainActor.run {
        if coverImage == nil {
          coverImage = images.first
        }
        selectedImages.append(contentsOf: images)
        selectedItems = []
      }
    }
  }
}

struct NewProjectSheet: View {
  let theme: PanelTheme
  @Binding var boards: [BoardDraft]
  let customers: [CustomerItem]
  let projectCustomers: [String]
  var onDone: (() -> Void)? = nil
  let onCreate: (ProjectItem) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var projectName = ""
  @State private var customer = ""
  @State private var site = ""
  @State private var hasDueDate = false
  @State private var dueDate = Date()
  @State private var selectedColorHex: UInt32 = 0x5E78FF
  @State private var createdProjectName: String?

  private var canCreate: Bool {
    !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var knownCustomers: [String] {
    Array(Set(customers.map(\.name) + projectCustomers))
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .sorted()
  }

  private var matchingKnownCustomers: [String] {
    let query = customer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return knownCustomers }
    return knownCustomers.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    NavigationStack {
      if let createdProjectName {
        BoardAttachPickerContent(theme: theme, projectName: createdProjectName, projectCustomer: customer, boards: $boards, headerTitle: "Project Created", headerSubtitle: "Pick matching-customer boards now, or add more later from the project screen.")
          .background(theme.background.ignoresSafeArea())
          .navigationTitle("Attach Boards")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
              onDone?()
            }
            .fontWeight(.bold)
          }
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            CreationFormSection(theme: theme, title: "Project Details", symbol: "folder.fill", subtitle: "Create the container first") {
              CreationTextInput(theme: theme, title: "Project name", placeholder: "Azrieli Office Tower", symbol: "folder.fill", text: $projectName, capitalization: .words)
              CreationTextInput(theme: theme, title: "Customer", placeholder: "Search or type customer", symbol: "person.crop.circle.fill", text: $customer, capitalization: .words)
              SuggestionChips(theme: theme, values: matchingKnownCustomers, selectedValue: customer) { customer = $0 }
              CreationTextInput(theme: theme, title: "Site or building", placeholder: "Optional location", symbol: "mappin.and.ellipse", text: $site, capitalization: .words)
            }

            CreationFormSection(theme: theme, title: "Schedule & Look", symbol: "paintpalette.fill") {
              CreationToggleInput(theme: theme, title: "Add expected finish date", symbol: "clock.badge.exclamationmark.fill", isOn: $hasDueDate)
              if hasDueDate {
                CreationDateInput(theme: theme, title: "Expected finish", symbol: "calendar.badge.clock", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
              }
            ColorSwatchPicker(title: "Project color", selectedHex: $selectedColorHex)
            }
            BottomTabClearance(height: 118)
          }
          .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("New Project")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
              onDone?()
              dismiss()
            }
          }

          ToolbarItem(placement: .topBarTrailing) {
            Button("Create") {
              let project = ProjectItem(
                id: "project-\(UUID().uuidString)",
                name: projectName,
                customer: customer,
                detail: site.isEmpty ? "0 boards" : "0 boards • \(site)",
                status: "Design",
                color: Color(hex: selectedColorHex),
                dueDate: hasDueDate ? dueDate : nil
              )
              onCreate(project)
              createdProjectName = project.name
            }
            .disabled(!canCreate)
            .fontWeight(.bold)
          }
        }
      }
    }
  }
}

struct BoardAttachPickerSheet: View {
  let theme: PanelTheme
  let projectName: String
  let projectCustomer: String
  @Binding var boards: [BoardDraft]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      BoardAttachPickerContent(theme: theme, projectName: projectName, projectCustomer: projectCustomer, boards: $boards, headerTitle: "Attach Boards", headerSubtitle: "Only boards for this customer can be attached here. Change a board customer from the board itself.")
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Attach Boards")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
              .fontWeight(.bold)
          }
        }
    }
  }
}

struct BoardAttachPickerContent: View {
  let theme: PanelTheme
  let projectName: String
  let projectCustomer: String
  @Binding var boards: [BoardDraft]
  let headerTitle: String
  let headerSubtitle: String

  private var attachableBoardIDs: [String] {
    let trimmedCustomer = projectCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
    return boards
      .filter { board in
        if board.project == projectName { return true }
        let isLoose = board.project == "No Project" || board.project.isEmpty
        guard isLoose else { return false }
        guard !trimmedCustomer.isEmpty else { return true }
        return board.customer.localizedCaseInsensitiveCompare(trimmedCustomer) == .orderedSame
      }
      .map(\.id)
  }

  private var inProgressBoardIDs: [String] {
    boards
      .filter { attachableBoardIDs.contains($0.id) && !$0.isCompleted }
      .sorted(by: activeBoardPrioritySort)
      .map(\.id)
  }

  private var finishedBoardIDs: [String] {
    boards
      .filter { attachableBoardIDs.contains($0.id) && $0.isCompleted }
      .sorted { $0.name < $1.name }
      .map(\.id)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        GlassCard(theme: theme) {
          VStack(alignment: .leading, spacing: 6) {
            Label(headerTitle, systemImage: "rectangle.stack.badge.plus")
              .font(.headline)
              .foregroundStyle(theme.primary)
            Text(projectName)
              .font(.title2.bold())
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text(headerSubtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        boardSection(title: "In Progress Boards", ids: inProgressBoardIDs, empty: "No in-progress boards available.")
        boardSection(title: "Finished Boards", ids: finishedBoardIDs, empty: "No finished boards available.")
      }
      .padding(18)
    }
  }

  private func boardSection(title: String, ids: [String], empty: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        Text("\(ids.count)")
          .font(.caption.bold())
          .foregroundStyle(.secondary)
      }

      if ids.isEmpty {
        EmptyStateCard(theme: theme, title: empty, subtitle: "Create or finish boards and they will appear here.")
      }

      ForEach($boards.filter { ids.contains($0.wrappedValue.id) }) { $board in
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            board.project = board.project == projectName ? "No Project" : projectName
          }
        } label: {
          BoardAttachRow(theme: theme, board: board, selected: board.project == projectName)
        }
        .buttonStyle(PanelPressButtonStyle())
      }
    }
  }
}

struct BoardAttachRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let selected: Bool

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(selected ? board.color : .secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(board.name)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text("\(board.number) • \(board.type) • \(board.customer)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        Spacer()
        StatusBadge(status: board.statusTitle)
      }
    }
    .background(board.color.opacity(selected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(selected ? 0.34 : 0.16), lineWidth: 1)
    )
  }
}

struct SearchView: View {
  let theme: PanelTheme
  @Binding var query: String
  @Binding var projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Binding var recentVisits: [RecentVisit]
  @State private var scope: SearchScope = .all
  @State private var activeFilters: Set<String> = []
  @State private var filtersExpanded = false
  @State private var selectedProject: ProjectItem?
  @State private var selectedBoard: BoardDraft?

  private var filteredProjects: [ProjectItem] {
    guard scope.includesProjects else { return [] }
    return projects.filter { project in
      matches(projectSearchText(project))
    }
    .sorted {
      let leftStatus = projectStatus($0)
      let rightStatus = projectStatus($1)
      if leftStatus != rightStatus {
        return projectSearchRank(leftStatus) < projectSearchRank(rightStatus)
      }
      if let dueSort = dueDateComesFirst($0.dueDate, $1.dueDate) { return dueSort }
      return $0.name < $1.name
    }
  }

  private var filteredBoards: [BoardDraft] {
    guard scope.includesBoards else { return [] }
    return boards.filter { board in
      matches(boardSearchText(board))
    }
    .sorted(by: boardPrioritySort)
  }

  private var filteredGroups: [ComponentGroup] {
    guard scope.includesComponents else { return [] }
    return ComponentGroup.samples.compactMap { group in
      let items = group.items.filter { item in
        matches("\(group.name) \(item.searchText)")
      }
      return items.isEmpty ? nil : ComponentGroup(id: group.id, name: group.name, items: items)
    }
  }

  private var hasResults: Bool {
    !filteredProjects.isEmpty || !filteredBoards.isEmpty || !filteredGroups.isEmpty
  }

  private var filterSections: [SearchFilterSection] {
    [
      SearchFilterSection(title: "Ampere", symbol: "bolt.fill", options: AmpereRating.all),
      SearchFilterSection(title: "Main Breaker", symbol: "bolt.shield.fill", options: ["MCB", "RCBO", "MCCB", "ACB", "Switch Disconnector", "Fuse Switch", "XT1", "XT2", "XT3", "XT4", "XT5", "XT6", "XT7", "XT7 M", "NSX", "S203"]),
      SearchFilterSection(title: "Brand", symbol: "tag.fill", options: ["ABB", "Schneider", "Siemens", "Eaton"]),
      SearchFilterSection(title: "Build Format", symbol: "square.grid.2x2.fill", options: ["Panels", "Plate"]),
      SearchFilterSection(title: "Component Type", symbol: "shippingbox.fill", options: EquipmentTypeCatalog.all),
      SearchFilterSection(title: "Board Type", symbol: "rectangle.3.group.fill", options: boardTypes.map(\.name)),
      SearchFilterSection(title: "Project", symbol: "folder.fill", options: projects.map(\.name)),
      SearchFilterSection(title: "Customer", symbol: "person.crop.circle.fill", options: Array(Set((projects.map(\.customer) + boards.map(\.customer)).filter { !$0.isEmpty })).sorted())
    ]
  }

  private var visibleFilterSections: [SearchFilterSection] {
    filtersExpanded ? filterSections : Array(filterSections.prefix(3))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(theme.primary)
              .frame(width: 40, height: 40)
              .background(theme.surface.opacity(0.78))
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
              Text("Search")
                .font(.system(size: 28, weight: .heavy))
              Text("Boards, projects and components")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          HStack {
            Image(systemName: "magnifyingglass")
              .font(.headline)
              .foregroundStyle(.secondary)
            TextField("Search board, main breaker, project, component...", text: $query)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            if !query.isEmpty {
              Button {
                query = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(14)
          .background(theme.surface.opacity(0.78))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

          searchFilters

          Picker("Search scope", selection: $scope) {
            ForEach(SearchScope.allCases) { option in
              Text(option.title).tag(option)
            }
          }
          .pickerStyle(.segmented)

          if hasResults {
            if !filteredProjects.isEmpty {
              Text("Projects")
                .font(.headline)
              ForEach(filteredProjects) { project in
                Button {
                  remember(.project, id: project.id)
                  selectedProject = project
                } label: {
                  ProjectSearchRow(
                    theme: theme,
                    project: project,
                    boardCount: linkedBoards(for: project).count,
                    displayedStatus: projectStatus(project)
                  )
                }
                .buttonStyle(.plain)
              }
            }

            if !filteredBoards.isEmpty {
              Text("Boards")
                .font(.headline)
              ForEach(filteredBoards) { board in
                Button {
                  remember(.board, id: board.id)
                  selectedBoard = board
                } label: {
                  BoardSearchRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
                }
                .buttonStyle(.plain)
              }
            }

            if !filteredGroups.isEmpty {
              ComponentCatalogView(theme: theme, groups: filteredGroups, manufacturers: manufacturers, boardStore: $boards)
            }
          } else {
            VStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
                .font(.system(size: 38, weight: .semibold))
              Text("No Matches")
                .font(.headline)
              Text("Try a board type, main breaker model, ABB family, rating or project name.")
                .font(.caption)
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 34)
          }
          BottomTabClearance()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.36), value: filtersExpanded)
      }
      .background(theme.background.ignoresSafeArea())
      .overlay(alignment: .top) {
        TopScrollBlur(theme: theme)
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(item: $selectedProject) { project in
        ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
          remember(.board, id: board.id)
        } onUpdateProject: { updatedProject, previousName in
          if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
          }
          for index in boards.indices where boards[index].project == previousName {
            boards[index].project = updatedProject.name
          }
        } onDeleteProject: {
          projects.removeAll { $0.id == project.id }
          for index in boards.indices where boards[index].project == project.name {
            boards[index].project = "No Project"
          }
          recentVisits.removeAll { $0.kind == .project && $0.itemID == project.id }
          selectedProject = nil
        }
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .sheet(item: $selectedBoard) { board in
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
          CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers, onDeleteBoard: {
            boards.removeAll { $0.id == board.id }
            recentVisits.removeAll { $0.kind == .board && $0.itemID == board.id }
            selectedBoard = nil
          }) {
            selectedBoard = nil
          }
        } else {
          EmptyStateCard(theme: theme, title: "Board no longer exists", subtitle: "It may have been deleted from Archive.")
            .padding(18)
            .background(theme.background.ignoresSafeArea())
        }
      }
      .onChange(of: query) { newValue in
        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filtersExpanded {
          withAnimation(.easeInOut(duration: 0.24)) {
            filtersExpanded = false
          }
        }
      }
    }
  }

  private var searchFilters: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Filters")
          .font(.headline)
        Spacer()
        Button {
          if !activeFilters.isEmpty {
            activeFilters.removeAll()
          }
        } label: {
          Text("Clear")
            .font(.caption.bold())
            .foregroundStyle(activeFilters.isEmpty ? .secondary.opacity(0.55) : Color(hex: 0xD66A6A))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(activeFilters.isEmpty ? .clear : Color(hex: 0xD66A6A).opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(activeFilters.isEmpty)
      }

      ForEach(Array(filterSections.prefix(3))) { section in
        searchFilterSection(section)
      }

      if filtersExpanded {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(filterSections.dropFirst(3))) { section in
            searchFilterSection(section)
          }
        }
        .padding(.top, 2)
        .clipped()
        .transition(.asymmetric(
          insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
          removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        ))
      }

      if filterSections.count > 3 {
        moreFiltersButton
      }
    }
    .padding(14)
    .background(theme.surface.opacity(0.58))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.easeInOut(duration: 0.36), value: filtersExpanded)
  }

  private var moreFiltersButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.36)) {
        filtersExpanded.toggle()
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "chevron.down")
          .font(.system(size: 11, weight: .heavy))
          .rotationEffect(.degrees(filtersExpanded ? 180 : 0))
        Text(filtersExpanded ? "Show Less" : "More Filters")
        Spacer()
        Text(filtersExpanded ? "\(filterSections.count) filters" : "+\(filterSections.count - 3)")
          .foregroundStyle(.secondary)
      }
      .font(.caption.bold())
      .foregroundStyle(theme.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(theme.primary.opacity(0.10))
      .overlay(
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .stroke(theme.primary.opacity(0.16), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
    .buttonStyle(TabBarButtonStyle())
  }

  private func searchFilterSection(_ section: SearchFilterSection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(section.title, systemImage: section.symbol)
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(section.options, id: \.self) { option in
            SearchFilterChip(
              theme: theme,
              title: option,
              selected: activeFilters.contains(option)
            ) {
              if activeFilters.contains(option) {
                activeFilters.remove(option)
              } else {
                activeFilters.insert(option)
              }
            }
          }
        }
      }
    }
  }

  private func remember(_ kind: RecentVisit.Kind, id: String) {
    recentVisits.removeAll { $0.kind == kind && $0.itemID == id }
    recentVisits.insert(RecentVisit(kind: kind, id: id), at: 0)
    recentVisits = Array(recentVisits.prefix(12))
  }

  private func matches(_ text: String) -> Bool {
    let queryMatches = query.isEmpty || text.localizedCaseInsensitiveContains(query)
    return queryMatches && groupedFiltersMatch(text)
  }

  private func groupedFiltersMatch(_ text: String) -> Bool {
    filterSections.allSatisfy { section in
      let selectedOptions = section.options.filter { activeFilters.contains($0) }
      guard !selectedOptions.isEmpty else { return true }
      return selectedOptions.contains { option in
        text.localizedCaseInsensitiveContains(option)
      }
    }
  }

  private func linkedBoards(for project: ProjectItem) -> [BoardDraft] {
    boards.filter { $0.project == project.name }
  }

  private func linkedProject(for board: BoardDraft) -> ProjectItem? {
    projects.first { $0.name == board.project }
  }

  private func projectSearchText(_ project: ProjectItem) -> String {
    "\(project.searchText) \(linkedBoards(for: project).map(\.searchText).joined(separator: " "))"
  }

  private func boardSearchText(_ board: BoardDraft) -> String {
    guard let project = linkedProject(for: board) else { return board.searchText }
    return "\(board.searchText) \(project.searchText) \(project.customer) \(project.name)"
  }

  private func projectStatus(_ project: ProjectItem) -> String {
    let linked = linkedBoards(for: project)
    guard !linked.isEmpty else { return project.status }
    return linked.allSatisfy(\.isCompleted) ? "Completed" : "In Progress"
  }

  private func projectSearchRank(_ status: String) -> Int {
    switch status {
    case "In Progress": return 0
    case "Design": return 1
    case "Completed": return 2
    default: return 3
    }
  }
}

struct SearchFilterSection: Identifiable {
  var id: String { title }
  let title: String
  let symbol: String
  let options: [String]
}

struct SearchFilterChip: View {
  let theme: PanelTheme
  let title: String
  let selected: Bool
  var fillsWidth = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .heavy))
        }
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.55)
      }
      .frame(maxWidth: fillsWidth ? .infinity : nil)
      .foregroundStyle(selected ? .white : .primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(selected ? theme.primary : theme.surface.opacity(0.9))
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(selected ? .clear : .white.opacity(0.08), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

enum SearchScope: String, CaseIterable, Identifiable {
  case all
  case projects
  case boards
  case components

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: "All"
    case .projects: "Projects"
    case .boards: "Boards"
    case .components: "Parts"
    }
  }

  var includesProjects: Bool {
    self == .all || self == .projects
  }

  var includesBoards: Bool {
    self == .all || self == .boards
  }

  var includesComponents: Bool {
    self == .all || self == .components
  }
}

struct ProjectSearchRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  let boardCount: Int
  let displayedStatus: String

  private var detailText: String {
    let cleanedDetail = project.detail.replacingOccurrences(
      of: #"^\d+ boards?( • )?"#,
      with: "",
      options: .regularExpression
    )
    return [
      "\(boardCount) board\(boardCount == 1 ? "" : "s")",
      cleanedDetail.isEmpty ? nil : cleanedDetail
    ]
      .compactMap { $0 }
      .joined(separator: " • ")
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(project.color.opacity(0.14))
          if let image = project.coverImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 42, height: 42)
              .clipShape(Circle())
          } else {
            Image(systemName: "rectangle.3.group.fill")
              .foregroundStyle(project.color)
          }
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(project.name)
              .font(.system(size: 16, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = project.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text(detailText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }

        Spacer()

        StatusBadge(status: displayedStatus)
      }
      .frame(minHeight: 58)
    }
  }
}

struct BoardSearchRow: View {
  let theme: PanelTheme
  let board: BoardDraft
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]

  private var boardType: BoardType {
    boardTypes.first { $0.name == board.type } ?? .fallback
  }

  private var manufacturer: ManufacturerItem? {
    syncedManufacturer(named: board.manufacturer, in: manufacturers)
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverImage, completed: board.isCompleted)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(board.name)
              .font(.system(size: 16, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = board.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
          }
          Text("\(board.number) • \(board.displayType) • \(board.manufacturer)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          if let finishDate = board.finishDate {
            Text("Finished \(DateDisplay.short.string(from: finishDate))")
              .font(.caption2.bold())
              .foregroundStyle(Color(hex: 0x35E177))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }

        Spacer()

        Text(board.project == "No Project" ? "Unattached" : board.project)
          .font(.caption.bold())
          .foregroundStyle(board.project == "No Project" ? .secondary : theme.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
          .font(.caption.bold())
      }
      .frame(minHeight: 58)
    }
    .background(board.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(board.color.opacity(0.22), lineWidth: 1)
    )
  }
}

struct MoreView: View {
  let theme: PanelTheme
  @Binding var selectedThemeID: String
  @Binding var selectedInterfaceSizeID: String
  @Binding var contractorMode: Bool
  let projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  @Binding var customers: [CustomerItem]
  @Binding var manufacturers: [ManufacturerItem]
  @Binding var boardTypes: [BoardType]
  @Binding var profileName: String
  @Binding var profileCompany: String
  @Binding var profilePhone: String
  @Binding var activeCompany: ContractorCompany?
  @Binding var companies: [ContractorCompany]
  @State private var componentCatalogOpen = false
  @State private var moreSheet: MoreSheet?
  @State private var themePickerOpen = false
  @State private var displaySizeOpen = false
  @State private var profileOpen = false

  private var selectedThemeOption: PanelTheme {
    PanelTheme.all.first { $0.id == selectedThemeID } ?? theme
  }

  private var selectedInterfaceSize: InterfaceSize {
    InterfaceSize.option(for: selectedInterfaceSizeID)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          GlassCard(theme: theme) {
            HStack(spacing: 14) {
              PanelVaultLogoMark(theme: theme, size: 48)
              VStack(alignment: .leading, spacing: 4) {
                Text("PanelVault")
                  .font(.system(size: 27, weight: .heavy))
                  .lineLimit(1)
              }
              Spacer(minLength: 12)
              Text("Zero clutter")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.primary.opacity(0.12))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          Toggle(isOn: $contractorMode) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Contractor Mode")
                .font(.headline)
              Text("Switch between companies from the dashboard menu.")
                .foregroundStyle(.secondary)
                .font(.caption)
            }
          }
          .toggleStyle(PanelToggleStyle(theme: theme))
          .padding(14)
          .background(theme.surface.opacity(0.78))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

          Button {
            profileOpen = true
          } label: {
            MoreRow(
              theme: theme,
              symbol: "person.crop.circle.fill",
              title: "Profile",
              subtitle: profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add your name, company and phone" : profileName
            )
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            themePickerOpen = true
          } label: {
            ThemePickerRow(theme: theme, selectedTheme: selectedThemeOption)
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            displaySizeOpen = true
          } label: {
            MoreRow(theme: theme, symbol: "textformat.size", title: "Dashboard Size", subtitle: selectedInterfaceSize.name)
          }
          .buttonStyle(PanelPressButtonStyle())

          Text("Archive")
            .font(.title3.bold())

          Button {
            moreSheet = .companies
          } label: {
            MoreRow(theme: theme, symbol: "building.2", title: "All Companies", subtitle: "Contractors, manufacturers and factories")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            moreSheet = .customers
          } label: {
            MoreRow(theme: theme, symbol: "person.2", title: "Customers", subtitle: "Add and manage customer names")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            moreSheet = .manufacturers
          } label: {
            MoreRow(theme: theme, symbol: "tag.fill", title: "Manufacturers", subtitle: "Edit brands, logos and custom makers")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            moreSheet = .boardTypes
          } label: {
            MoreRow(theme: theme, symbol: "rectangle.3.group", title: "Board Types", subtitle: "MDB, MCC, ATS and custom categories")
          }
          .buttonStyle(PanelPressButtonStyle())

          Button {
            componentCatalogOpen = true
          } label: {
            MoreRow(theme: theme, symbol: "shippingbox", title: "Components", subtitle: "MCBs, MCCBs, contactors and more")
          }
          .buttonStyle(PanelPressButtonStyle())
          BottomTabClearance()
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("More")
      .sheet(isPresented: $themePickerOpen) {
        ThemePickerSheet(theme: theme, selectedThemeID: $selectedThemeID)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
      .sheet(isPresented: $displaySizeOpen) {
        DisplaySizePickerSheet(theme: theme, selectedInterfaceSizeID: $selectedInterfaceSizeID)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
      .fullScreenCover(isPresented: $componentCatalogOpen) {
        NavigationStack {
          ScrollView {
            ComponentCatalogView(theme: theme, groups: ComponentGroup.samples, manufacturers: manufacturers, boardStore: $boards)
              .padding(18)
          }
          .background(theme.background.ignoresSafeArea())
          .navigationTitle("Components")
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Done") {
                componentCatalogOpen = false
              }
            }
          }
        }
      }
      .sheet(item: $moreSheet) { sheet in
        switch sheet {
        case .companies:
          CompanyManagerSheet(
            theme: theme,
            companies: $companies,
            activeCompany: $activeCompany,
            projects: projects,
            boards: $boards,
            boardTypes: boardTypes,
            manufacturers: manufacturers
          )
        case .customers:
          CustomerManagerSheet(
            theme: theme,
            customers: $customers,
            projectCustomers: uniqueCustomers,
            projects: projects,
            boards: $boards,
            boardTypes: boardTypes,
            manufacturers: manufacturers
          )
        case .manufacturers:
          ManufacturerManagerSheet(theme: theme, manufacturers: $manufacturers)
        case .boardTypes:
          BoardTypeManagerSheet(theme: theme, boardTypes: $boardTypes)
        }
      }
      .sheet(isPresented: $profileOpen) {
        ProfileEditorSheet(theme: theme, name: $profileName, company: $profileCompany, phone: $profilePhone)
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
    }
  }

  private var uniqueCustomers: [String] {
    Array(Set(projects.map(\.customer).filter { !$0.isEmpty })).sorted()
  }
}

enum MoreSheet: String, Identifiable {
  case companies
  case customers
  case manufacturers
  case boardTypes

  var id: String { rawValue }
}

struct ProfileEditorSheet: View {
  let theme: PanelTheme
  @Binding var name: String
  @Binding var company: String
  @Binding var phone: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Profile") {
          TextField("Full name", text: $name)
            .textInputAutocapitalization(.words)
          TextField("Company", text: $company)
            .textInputAutocapitalization(.words)
          TextField("Phone", text: $phone)
            .keyboardType(.phonePad)
        }
      }
      .scrollContentBackground(.hidden)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        BottomTabClearance()
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Profile")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
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

struct CustomerManagerSheet: View {
  let theme: PanelTheme
  @Binding var customers: [CustomerItem]
  let projectCustomers: [String]
  let projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var customerKind = "Company"
  @State private var contactName = ""
  @State private var phone = ""
  @State private var note = ""
  @State private var selectedCustomer: CustomerItem?

  private var allCustomers: [CustomerItem] {
    let existingNames = Set(customers.map { $0.name.lowercased() })
    let inferred = projectCustomers
      .filter { !existingNames.contains($0.lowercased()) }
      .map { CustomerItem(id: "project-customer-\($0)", name: $0, kind: "Company", contactName: "", phone: "", note: "From projects") }
    return customers + inferred
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Customer name", text: $name)
                .textInputAutocapitalization(.words)
              Picker("Type", selection: $customerKind) {
                ForEach(["Company", "Person"], id: \.self) { Text($0) }
              }
              if customerKind == "Company" {
                TextField("Contact person", text: $contactName)
                  .textInputAutocapitalization(.words)
              }
              TextField("Phone", text: $phone)
                .keyboardType(.phonePad)
              TextField("Note", text: $note)
              Button {
                addCustomer()
              } label: {
                Label("Add Customer", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }

          if allCustomers.isEmpty {
            EmptyStateCard(theme: theme, title: "No customers yet", subtitle: "Add customer names here and they will appear as suggestions.")
          } else {
            ForEach(allCustomers) { customer in
              CustomerManagerRow(
                theme: theme,
                customer: customer,
                summary: customerSummary(customer.name),
                canDelete: customers.contains(where: { $0.id == customer.id }),
                open: {
                  selectedCustomer = customer
                },
                delete: {
                  customers.removeAll { $0.id == customer.id }
                }
              )
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Customers")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $selectedCustomer) { customer in
      CustomerArchiveDetailSheet(
        theme: theme,
        title: customer.name,
        subtitle: [customer.kind, customer.contactName.isEmpty ? nil : customer.contactName, customer.phone.isEmpty ? nil : customer.phone, customer.note.isEmpty ? nil : customer.note].compactMap { $0 }.joined(separator: " • "),
        symbol: "person.fill",
        color: theme.primary,
        projects: projects.filter { $0.customer.localizedCaseInsensitiveCompare(customer.name) == .orderedSame },
        boardIDs: boards.filter { $0.customer.localizedCaseInsensitiveCompare(customer.name) == .orderedSame }.map(\.id),
        boards: $boards,
        boardTypes: boardTypes,
        manufacturers: manufacturers
      )
    }
  }

  private func addCustomer() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    customers.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    customers.insert(CustomerItem(name: trimmedName, kind: customerKind, contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone.trimmingCharacters(in: .whitespacesAndNewlines), note: note.trimmingCharacters(in: .whitespacesAndNewlines)), at: 0)
    name = ""
    customerKind = "Company"
    contactName = ""
    phone = ""
    note = ""
  }

  private func customerSummary(_ customerName: String) -> String {
    let projectCount = projects.filter { $0.customer.localizedCaseInsensitiveCompare(customerName) == .orderedSame }.count
    let boardCount = boards.filter { $0.customer.localizedCaseInsensitiveCompare(customerName) == .orderedSame }.count
    return "\(projectCount) project\(projectCount == 1 ? "" : "s") • \(boardCount) board\(boardCount == 1 ? "" : "s")"
  }
}

struct CustomerManagerRow: View {
  let theme: PanelTheme
  let customer: CustomerItem
  let summary: String
  let canDelete: Bool
  let open: () -> Void
  let delete: () -> Void

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        Button(action: open) {
          HStack(spacing: 12) {
            CompanyColorLogo(color: theme.primary, symbol: "person.fill")
            VStack(alignment: .leading, spacing: 4) {
              Text(customer.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
              Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
              if !customer.phone.isEmpty {
                Label([customer.contactName.isEmpty ? nil : customer.contactName, customer.phone].compactMap { $0 }.joined(separator: " • "), systemImage: "phone.fill")
                  .font(.caption)
                  .foregroundStyle(theme.primary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.72)
              }
              if !customer.note.isEmpty {
                Text(customer.note)
                  .font(.caption)
                  .foregroundStyle(.secondary.opacity(0.78))
                  .lineLimit(2)
                  .minimumScaleFactor(0.72)
              }
            }
            Spacer(minLength: 8)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if canDelete {
          Menu {
            Button(role: .destructive, action: delete) {
              Label("Delete Customer", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 17, weight: .heavy))
              .foregroundStyle(.secondary)
              .frame(width: 34, height: 34)
              .background(theme.surface.opacity(0.72))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
        } else {
          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }
}

struct CustomerArchiveDetailSheet: View {
  let theme: PanelTheme
  let title: String
  let subtitle: String
  let symbol: String
  let color: Color
  let projects: [ProjectItem]
  let boardIDs: [String]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var selectedBoardID: String?

  private var visibleBoards: [BoardDraft] {
    boards.filter { boardIDs.contains($0.id) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 14) {
            CompanyColorLogo(color: color, symbol: symbol)
            VStack(alignment: .leading, spacing: 4) {
              Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              Text("\(projects.count) project\(projects.count == 1 ? "" : "s") • \(visibleBoards.count) board\(visibleBoards.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
              if !subtitle.isEmpty {
                Text(subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Text("Projects")
            .font(.headline)
          if projects.isEmpty {
            EmptyStateCard(theme: theme, title: "No projects", subtitle: "Projects for this name will show here.")
          } else {
            ForEach(projects) { project in
              ProjectDashboardRow(theme: theme, project: project)
            }
          }

          Text("Boards")
            .font(.headline)
          if visibleBoards.isEmpty {
            EmptyStateCard(theme: theme, title: "No boards", subtitle: "Boards for this name will show here.")
          } else {
            ForEach(visibleBoards) { board in
              Button {
                selectedBoardID = board.id
              } label: {
                DashboardBoardRecentRow(theme: theme, board: board, boardTypes: boardTypes, manufacturers: manufacturers)
              }
              .buttonStyle(.plain)
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
      .sheet(item: Binding(
        get: { selectedBoardID.map(BoardIDSelection.init(id:)) },
        set: { selectedBoardID = $0?.id }
      )) { selection in
        if let index = boards.firstIndex(where: { $0.id == selection.id }) {
          CreatedBoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers) {
            selectedBoardID = nil
          }
        }
      }
    }
  }
}

struct BoardIDSelection: Identifiable {
  let id: String
}

struct ManufacturerManagerSheet: View {
  let theme: PanelTheme
  @Binding var manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var selectedColorHex: UInt32 = 0x5E78FF
  @State private var selectedManufacturerID: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Manufacturer name", text: $name)
                .textInputAutocapitalization(.words)
              ColorSwatchPicker(title: "Logo color", selectedHex: $selectedColorHex)
              Button {
                addManufacturer()
              } label: {
                Label("Add Manufacturer", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }

          ForEach($manufacturers) { $manufacturer in
            ManufacturerEditorRow(theme: theme, manufacturer: $manufacturer) {
              manufacturers.removeAll { $0.id == manufacturer.id }
            } showDetails: {
              selectedManufacturerID = manufacturer.id
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Manufacturers")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(item: selectedManufacturerBinding) { selection in
        if let manufacturer = manufacturers.first(where: { $0.id == selection.id }) {
          ManufacturerDetailSheet(theme: theme, manufacturer: manufacturer)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
      }
    }
  }

  private var selectedManufacturerBinding: Binding<ManufacturerSelection?> {
    Binding {
      selectedManufacturerID.map(ManufacturerSelection.init(id:))
    } set: { selection in
      selectedManufacturerID = selection?.id
    }
  }

  private func addManufacturer() {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    manufacturers.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    manufacturers.insert(ManufacturerItem(name: trimmedName, colorHex: selectedColorHex), at: 0)
    name = ""
    selectedColorHex = 0x5E78FF
  }
}

struct ManufacturerEditorRow: View {
  let theme: PanelTheme
  @Binding var manufacturer: ManufacturerItem
  let delete: () -> Void
  let showDetails: () -> Void
  @State private var selectedItem: PhotosPickerItem?

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          ManufacturerLogoView(manufacturer: manufacturer)
        }
        .buttonStyle(.plain)
        .onChange(of: selectedItem) { item in
          loadImage(from: item)
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 7) {
            Image(systemName: "tag.fill")
              .font(.caption.bold())
              .foregroundStyle(manufacturer.color)
            TextField("Manufacturer", text: $manufacturer.name)
              .font(.headline)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          Menu {
            ForEach(AccentPalette.choices) { choice in
              Button(choice.name) {
                manufacturer.colorHex = choice.id
              }
            }
          } label: {
            HStack(spacing: 6) {
              Circle()
                .fill(manufacturer.color)
                .frame(width: 12, height: 12)
              Text("Color")
                .font(.caption.bold())
              Image(systemName: "chevron.down")
                .font(.caption2.bold())
            }
            .foregroundStyle(.secondary)
          }
          if manufacturer.image != nil {
            Button(role: .destructive) {
              removeLogo()
            } label: {
              Label("Remove Logo", systemImage: "trash")
                .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: 0xD66A6A))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: showDetails) {
          Image(systemName: "info.circle.fill")
            .font(.title3)
            .foregroundStyle(theme.primary)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)

        DeleteIconButton(theme: theme, action: delete)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func loadImage(from item: PhotosPickerItem?) {
    Task {
      guard item == selectedItem else { return }
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else { return }
      await MainActor.run {
        if item == selectedItem {
          manufacturer.image = image
        }
      }
    }
  }

  private func removeLogo() {
    selectedItem = nil
    manufacturer.image = nil
  }
}

struct ManufacturerSelection: Identifiable {
  let id: String
}

struct ManufacturerDetailSheet: View {
  let theme: PanelTheme
  let manufacturer: ManufacturerItem
  @Environment(\.dismiss) private var dismiss

  private var components: [PanelComponent] {
    ComponentGroup.samples.flatMap(\.items).filter {
      $0.manufacturer.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame
    }
  }

  private var filteredGroups: [ComponentGroup] {
    ComponentGroup.samples.compactMap { group in
      let items = group.items.filter {
        $0.manufacturer.localizedCaseInsensitiveCompare(manufacturer.name) == .orderedSame
      }
      guard !items.isEmpty else { return nil }
      return ComponentGroup(id: "\(manufacturer.id)-\(group.id)", name: group.name, items: items)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 14) {
            ManufacturerLogoView(manufacturer: manufacturer)
            VStack(alignment: .leading, spacing: 5) {
              Text(manufacturer.name)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              Text("\(components.count) catalog item\(components.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            }
          }

          BoardReferenceSection(theme: theme, title: "Manufacturer", symbol: "tag.fill", color: manufacturer.color) {
            BoardBulletList(items: [
              "Logo/color can be edited from the manufacturer list.",
              "This page shows every built-in catalog item currently assigned to this manufacturer.",
              "Custom components you add can also use this manufacturer name."
            ])
          }

          Text("Catalog Items")
            .font(.headline)

          if filteredGroups.isEmpty {
            EmptyStateCard(theme: theme, title: "No catalog items", subtitle: "Add custom components with this manufacturer name to start filling this section.")
          } else {
            ComponentCatalogView(theme: theme, groups: filteredGroups, manufacturers: [manufacturer])
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(manufacturer.name)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
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

enum ComponentIcon {
  static func symbol(for type: String) -> String {
    let lowered = type.lowercased()
    if lowered.contains("mcb") || lowered.contains("mccb") || lowered.contains("breaker") { return "bolt.shield.fill" }
    if lowered.contains("rcbo") || lowered.contains("rccb") || lowered.contains("rcd") { return "waveform.path.ecg" }
    if lowered.contains("contactor") { return "switch.2" }
    if lowered.contains("vfd") || lowered.contains("starter") { return "speedometer" }
    if lowered.contains("psu") || lowered.contains("power") { return "powerplug.fill" }
    if lowered.contains("busbar") || lowered.contains("bar") { return "rectangle.grid.1x2.fill" }
    if lowered.contains("meter") { return "gauge.with.dots.needle.67percent" }
    if lowered.contains("plc") || lowered.contains("relay") { return "cpu.fill" }
    if lowered.contains("fan") { return "fan.fill" }
    if lowered.contains("button") || lowered.contains("selector") { return "button.programmable" }
    return "shippingbox.fill"
  }

  static func description(for component: PanelComponent) -> String {
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
    if type.contains("psu") {
      return "Power supply for control circuits, sensors, PLCs and relays. Check output voltage, current and spare capacity."
    }
    if type.contains("busbar") {
      return "Copper or distribution bar used to carry current between sections or devices. Check current rating, spacing, supports and insulation."
    }
    return "Catalog component used inside the board. Confirm manufacturer data, model, rating, poles/phase and project-specific installation notes."
  }
}

struct ComponentDetailSheet: View {
  let theme: PanelTheme
  let component: PanelComponent
  let manufacturer: ManufacturerItem?
  let onSaveImage: (UIImage) -> Void
  let onRemoveImage: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var selectedImage: UIImage?
  @State private var selectedItem: PhotosPickerItem?
  @State private var previewImage: ImagePreviewItem?
  @State private var editorImage: ImagePreviewItem?

  init(
    theme: PanelTheme,
    component: PanelComponent,
    manufacturer: ManufacturerItem?,
    image: UIImage? = nil,
    onSaveImage: @escaping (UIImage) -> Void = { _ in },
    onRemoveImage: @escaping () -> Void = {}
  ) {
    self.theme = theme
    self.component = component
    self.manufacturer = manufacturer
    self.onSaveImage = onSaveImage
    self.onRemoveImage = onRemoveImage
    _selectedImage = State(initialValue: image)
  }

  private var manufacturerColor: Color {
    if let manufacturer {
      return manufacturer.color
    }
    switch component.manufacturer {
    case "ABB": return Color(hex: 0xFF3B30)
    case "Schneider": return Color(hex: 0x35E177)
    case "Siemens": return Color(hex: 0x18D4E8)
    case "Eaton": return Color(hex: 0x5E78FF)
    default: return theme.primary
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          componentPhotoSection

          HStack(spacing: 14) {
            Image(systemName: ComponentIcon.symbol(for: component.type))
              .font(.system(size: 30, weight: .bold))
              .foregroundStyle(theme.primary)
              .frame(width: 64, height: 64)
              .background(theme.primary.opacity(0.14))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
              Text(component.model)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
              HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                  .foregroundStyle(manufacturer?.color ?? theme.primary)
                Text(component.manufacturer)
                  .font(.headline)
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
              }
            }
          }

          BoardReferenceSection(theme: theme, title: "Description", symbol: "text.alignleft", color: theme.primary) {
            Text(ComponentIcon.description(for: component))
              .fixedSize(horizontal: false, vertical: true)
          }

          BoardReferenceSection(theme: theme, title: "Specification", symbol: "list.bullet.rectangle.fill", color: theme.primary) {
            VStack(alignment: .leading, spacing: 10) {
              InfoLine(title: "Type", value: component.type)
              InfoLine(title: "Rating", value: component.rating)
              InfoLine(title: "Poles / Phase", value: component.poles)
              if !component.curve.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                InfoLine(title: "Curve / Notes", value: component.curve)
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle(component.type)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .onChange(of: selectedItem) { item in
        loadImage(from: item)
      }
      .sheet(item: $previewImage) { item in
        ImagePreviewSheet(image: item.image)
      }
      .sheet(item: $editorImage) { item in
        CoverPhotoEditorSheet(theme: theme, image: item.image) { adjustedImage in
          selectedImage = adjustedImage
          onSaveImage(adjustedImage)
        }
      }
    }
  }

  private var componentPhotoSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let selectedImage {
        Button {
          previewImage = ImagePreviewItem(image: selectedImage)
        } label: {
          Image(uiImage: selectedImage)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .padding(14)
            .shadow(color: manufacturerColor.opacity(0.32), radius: 16, x: 0, y: 0)
            .shadow(color: manufacturerColor.opacity(0.16), radius: 32, x: 0, y: 0)
        }
        .buttonStyle(.plain)

        HStack(spacing: 14) {
          Button {
            previewImage = ImagePreviewItem(image: selectedImage)
          } label: {
            Label("View", systemImage: "photo.fill")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Button {
            editorImage = ImagePreviewItem(image: selectedImage)
          } label: {
            Label("Edit", systemImage: "crop")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)

          Spacer()

          Button(role: .destructive) {
            self.selectedImage = nil
            selectedItem = nil
            onRemoveImage()
          } label: {
            Label("Delete", systemImage: "trash")
              .font(.caption.bold())
          }
          .buttonStyle(.plain)
        }
        .foregroundStyle(manufacturerColor)
      } else {
        PhotosPicker(selection: $selectedItem, matching: .images) {
          VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
              .font(.system(size: 30, weight: .bold))
            Text("Add Component Picture")
              .font(.headline)
            Text("Tap to attach a photo for this catalog item.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 34)
          .background(theme.surface.opacity(0.58))
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(manufacturerColor.opacity(0.16), lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func loadImage(from item: PhotosPickerItem?) {
    Task {
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else { return }
      await MainActor.run {
        selectedImage = image
        selectedItem = nil
        onSaveImage(image)
      }
    }
  }
}

struct ManufacturerLogoView: View {
  let manufacturer: ManufacturerItem

  var body: some View {
    Group {
      if let image = manufacturer.image {
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

  var body: some View {
    Group {
      if let image = manufacturer?.image {
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

struct BoardTypeManagerSheet: View {
  let theme: PanelTheme
  @Binding var boardTypes: [BoardType]
  @Environment(\.dismiss) private var dismiss
  @State private var newTypeIcon = "⚡"
  @State private var newTypeName = ""
  @State private var newTypeDescription = ""
  @State private var selectedBoardType: BoardType?

  private var canAdd: Bool {
    !newTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              TextField("Icon or emoji", text: $newTypeIcon)
              TextField("Board type name", text: $newTypeName)
              TextField("Description", text: $newTypeDescription)
              Button {
                let trimmedName = newTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = newTypeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let newType = BoardType(
                  id: "custom-\(UUID().uuidString)",
                  name: trimmedName,
                  subtitle: trimmedDescription.isEmpty ? "Custom board type" : trimmedDescription,
                  symbol: "rectangle.3.group.fill",
                  color: theme.primary,
                  emoji: newTypeIcon
                )
                boardTypes.removeAll { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
                boardTypes.insert(newType, at: 0)
                newTypeIcon = "⚡"
                newTypeName = ""
                newTypeDescription = ""
              } label: {
                Label("Add Board Type", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(!canAdd)
            }
          }

          Text("Available Types")
            .font(.headline)

          ForEach(boardTypes) { board in
            HStack(spacing: 8) {
              Button {
                selectedBoardType = board
              } label: {
                SimpleBoardTypeRow(theme: theme, icon: board.emoji, name: board.name, subtitle: board.subtitle, color: board.color)
              }
              .buttonStyle(.plain)
              if board.id.hasPrefix("custom-") {
                DeleteIconButton(theme: theme) {
                  boardTypes.removeAll { $0.id == board.id }
                }
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Board Types")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $selectedBoardType) { board in
      BoardTypeDetailSheet(theme: theme, board: board)
    }
  }
}

struct SimpleBoardTypeRow: View {
  let theme: PanelTheme
  let icon: String?
  let name: String
  let subtitle: String
  let color: Color

  var body: some View {
    GlassCard(theme: theme) {
      HStack {
        if let icon {
          Text(icon)
            .font(.title3)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.14))
            .clipShape(Circle())
        } else {
          Image(systemName: "rectangle.3.group")
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.14))
            .clipShape(Circle())
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(name).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct CompanySwitcherSheet: View {
  let theme: PanelTheme
  @Binding var activeCompany: ContractorCompany?
  let companies: [ContractorCompany]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Companies")
        .font(.title2.bold())
      Text("Choose which contractor workspace is active.")
        .foregroundStyle(.secondary)

      CompanyRow(
        theme: theme,
        title: "All Companies",
        subtitle: "Show every company and project together",
        color: theme.primary,
        selected: activeCompany == nil
      ) {
        activeCompany = nil
        dismiss()
      }

      if companies.isEmpty {
        EmptyStateCard(theme: theme, title: "No companies yet", subtitle: "Add companies from More, then switch between them here.")
      }

      ForEach(companies) { company in
        CompanyRow(
          theme: theme,
          title: company.name,
          subtitle: "\(company.role) • \(company.projectCount)",
          color: company.color,
          selected: activeCompany?.id == company.id
        ) {
          activeCompany = company
          dismiss()
        }
      }
    }
    .padding(18)
    .background(theme.surface.ignoresSafeArea())
  }
}

struct CompanyManagerSheet: View {
  let theme: PanelTheme
  @Binding var companies: [ContractorCompany]
  @Binding var activeCompany: ContractorCompany?
  let projects: [ProjectItem]
  @Binding var boards: [BoardDraft]
  let boardTypes: [BoardType]
  let manufacturers: [ManufacturerItem]
  @Environment(\.dismiss) private var dismiss
  @State private var companyName = ""
  @State private var companyRole = ""
  @State private var selectedColorHex: UInt32 = 0x5E78FF
  @State private var selectedCompany: ContractorCompany?

  private var canAdd: Bool {
    !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
              TextField("Company name", text: $companyName)
                .textInputAutocapitalization(.words)
              TextField("Type or role", text: $companyRole)
                .textInputAutocapitalization(.words)
              ColorSwatchPicker(title: "Company color", selectedHex: $selectedColorHex)
              Button {
                addCompany()
              } label: {
                Label("Add Company", systemImage: "plus")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.borderedProminent)
              .tint(theme.primary)
              .disabled(!canAdd)
            }
          }

          Text("Companies")
            .font(.headline)

          if companies.isEmpty {
            EmptyStateCard(theme: theme, title: "No companies yet", subtitle: "Add factories, contractors or manufacturers you work with.")
          } else {
            ForEach(companies) { company in
              HStack(spacing: 8) {
                Button {
                  selectedCompany = company
                } label: {
                  GlassCard(theme: theme) {
                    HStack(spacing: 12) {
                      CompanyColorLogo(color: company.color, symbol: "building.2.fill")
                      VStack(alignment: .leading, spacing: 4) {
                        Text(company.name)
                          .font(.headline)
                        Text(company.role)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                        Text(companySummary(company.name))
                          .font(.caption)
                          .foregroundStyle(.secondary.opacity(0.78))
                          .lineLimit(1)
                          .minimumScaleFactor(0.7)
                      }
                      Spacer()
                      Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                    }
                  }
                  .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                      .stroke(company.color.opacity(0.24), lineWidth: 1)
                  )
                }
                .buttonStyle(.plain)

                Button {
                  activeCompany = company
                } label: {
                  Image(systemName: activeCompany?.id == company.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(activeCompany?.id == company.id ? company.color : .secondary)
                }
                .buttonStyle(.plain)
                DeleteIconButton(theme: theme) {
                  if activeCompany?.id == company.id {
                    activeCompany = nil
                  }
                  companies.removeAll { $0.id == company.id }
                }
              }
            }
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Companies")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .sheet(item: $selectedCompany) { company in
      CustomerArchiveDetailSheet(
        theme: theme,
        title: company.name,
        subtitle: company.role,
        symbol: "building.2.fill",
        color: company.color,
        projects: projects.filter { $0.customer.localizedCaseInsensitiveCompare(company.name) == .orderedSame },
        boardIDs: boards.filter { $0.company.localizedCaseInsensitiveCompare(company.name) == .orderedSame }.map(\.id),
        boards: $boards,
        boardTypes: boardTypes,
        manufacturers: manufacturers
      )
    }
  }

  private func addCompany() {
    let trimmedName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedRole = companyRole.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }
    let company = ContractorCompany(
      id: "company-\(UUID().uuidString)",
      name: trimmedName,
      role: trimmedRole.isEmpty ? "Company" : trimmedRole,
      projectCount: "0 projects",
      color: Color(hex: selectedColorHex)
    )
    companies.insert(company, at: 0)
    companyName = ""
    companyRole = ""
    selectedColorHex = 0x5E78FF
  }

  private func companySummary(_ companyName: String) -> String {
    let projectCount = projects.filter { $0.customer.localizedCaseInsensitiveCompare(companyName) == .orderedSame }.count
    let boardCount = boards.filter { $0.company.localizedCaseInsensitiveCompare(companyName) == .orderedSame }.count
    return "\(projectCount) project\(projectCount == 1 ? "" : "s") • \(boardCount) board\(boardCount == 1 ? "" : "s")"
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

struct ComponentCatalogView: View {
  let theme: PanelTheme
  let groups: [ComponentGroup]
  var manufacturers: [ManufacturerItem] = ManufacturerItem.defaults
  var boardStore: Binding<[BoardDraft]>? = nil
  var onAddComponent: ((PanelComponent) -> Void)? = nil
  @AppStorage("panelvault.componentImages") private var savedComponentImages = ""
  @State private var addedComponentIDs: Set<String> = []
  @State private var photoComponentIDs: Set<String> = []
  @State private var componentImages: [String: UIImage] = [:]
  @State private var customComponents: [PanelComponent] = []
  @State private var addComponentOpen = false
  @State private var componentToConfigure: PanelComponent?
  @State private var componentToDescribe: PanelComponent?
  @State private var componentToAssign: PanelComponent?

  private var visibleGroups: [ComponentGroup] {
    if customComponents.isEmpty { return groups }
    return [ComponentGroup(id: "custom-components", name: "Custom Components", items: customComponents)] + groups
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        EquipmentBrandBadge(name: groups.first?.items.first?.manufacturer ?? "ABB", image: manufacturerImage(for: groups.first?.items.first?.manufacturer ?? "ABB"))
        VStack(alignment: .leading) {
          Text("Equipment Catalog")
            .font(.headline)
          Text("Add manufacturer parts by type, amp rating, poles and model.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          addComponentOpen = true
        } label: {
          Label("Add", systemImage: "plus")
            .font(.caption.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary)
      }

      ForEach(visibleGroups) { group in
        VStack(alignment: .leading, spacing: 8) {
          Text(group.name)
            .font(.headline)
          ForEach(group.items) { item in
            let image = storedImage(for: item)
            ComponentRow(
              theme: theme,
              component: item,
              manufacturer: manufacturer(for: item.manufacturer),
              storedImage: image,
              isAdded: addedComponentIDs.contains(item.id),
              hasPhoto: photoComponentIDs.contains(item.id) || image != nil,
              toggleAdded: {
                if addedComponentIDs.contains(item.id) {
                  addedComponentIDs.remove(item.id)
                } else {
                  componentToConfigure = item
                }
              },
              togglePhoto: {
                if photoComponentIDs.contains(item.id) {
                  photoComponentIDs.remove(item.id)
                } else {
                  photoComponentIDs.insert(item.id)
                }
              },
              savePhoto: { image in
                componentImages[item.imageStorageID] = image
                photoComponentIDs.insert(item.id)
                persistComponentImages()
              },
              showDetails: {
                componentToDescribe = item
              },
              deleteComponent: group.id == "custom-components" ? {
                customComponents.removeAll { $0.id == item.id }
                addedComponentIDs.remove(item.id)
                photoComponentIDs.remove(item.id)
              } : nil
            )
          }
        }
      }
    }
    .onAppear {
      loadComponentImagesIfNeeded()
    }
    .sheet(isPresented: $addComponentOpen) {
      AddComponentSheet(theme: theme, manufacturerNames: manufacturers.map(\.name)) { component in
        customComponents.insert(component, at: 0)
        handleAddedComponent(component, sourceID: component.id)
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $componentToConfigure) { component in
      ComponentRatingSheet(theme: theme, component: component) { configured in
        handleAddedComponent(configured, sourceID: component.id)
      }
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $componentToAssign) { component in
      if let boardStore {
        ComponentBoardPickerSheet(theme: theme, component: component, boards: boardStore) { boardID in
          assign(component, to: boardID, in: boardStore)
          componentToAssign = nil
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
    }
    .sheet(item: $componentToDescribe) { component in
      ComponentDetailSheet(
        theme: theme,
        component: component,
        manufacturer: manufacturer(for: component.manufacturer),
        image: storedImage(for: component),
        onSaveImage: { image in
          componentImages[component.imageStorageID] = image
          photoComponentIDs.insert(component.id)
          persistComponentImages()
        },
        onRemoveImage: {
          component.imageLookupIDs.forEach { componentImages.removeValue(forKey: $0) }
          photoComponentIDs.remove(component.id)
          persistComponentImages()
        }
      )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
  }

  private func handleAddedComponent(_ component: PanelComponent, sourceID: String) {
    if let onAddComponent {
      addedComponentIDs.insert(sourceID)
      onAddComponent(component)
    } else if boardStore != nil {
      componentToAssign = component
    } else {
      addedComponentIDs.insert(sourceID)
    }
  }

  private func assign(_ component: PanelComponent, to boardID: String, in boardStore: Binding<[BoardDraft]>) {
    guard let index = boardStore.wrappedValue.firstIndex(where: { $0.id == boardID }) else { return }
    if !boardStore.wrappedValue[index].componentTypes.contains(component.type) {
      boardStore.wrappedValue[index].componentTypes.append(component.type)
    }
    addedComponentIDs.insert(component.id)
  }

  private func manufacturer(for name: String) -> ManufacturerItem? {
    manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
  }

  private func manufacturerImage(for name: String) -> UIImage? {
    manufacturer(for: name)?.image
  }

  private func storedImage(for component: PanelComponent) -> UIImage? {
    component.imageLookupIDs.lazy.compactMap { componentImages[$0] }.first
  }

  private func loadComponentImagesIfNeeded() {
    guard componentImages.isEmpty else { return }
    componentImages = ComponentImageArchive.decode(savedComponentImages)
    photoComponentIDs = photoComponentIDs.union(componentImages.keys)
  }

  private func persistComponentImages() {
    savedComponentImages = ComponentImageArchive.encode(componentImages)
  }
}

struct ComponentBoardPickerSheet: View {
  let theme: PanelTheme
  let component: PanelComponent
  @Binding var boards: [BoardDraft]
  let onSelect: (String) -> Void
  @Environment(\.dismiss) private var dismiss

  private var sortedBoards: [BoardDraft] {
    boards.sorted(by: boardPrioritySort)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Add \(component.type)")
                .font(.headline)
              Text("\(component.manufacturer) \(component.model) • \(component.ratingLabel) • \(component.poles)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          if sortedBoards.isEmpty {
            EmptyStateCard(theme: theme, title: "No boards yet", subtitle: "Create a board first, then add catalog components to it.")
          } else {
            ForEach(sortedBoards) { board in
              Button {
                onSelect(board.id)
                dismiss()
              } label: {
                HStack(spacing: 12) {
                  BoardTypeIcon(board: iconType(for: board), size: 44, overrideColor: board.color)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(board.name)
                      .font(.headline)
                      .lineLimit(1)
                      .minimumScaleFactor(0.75)
                    Text([board.number, board.type, board.componentTypes.joined(separator: ", ")]
                      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                      .joined(separator: " • "))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(2)
                  }
                  Spacer()
                  Image(systemName: "plus.circle.fill")
                    .foregroundStyle(theme.primary)
                    .font(.title3)
                }
                .padding(14)
                .background(theme.surface.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              .buttonStyle(PanelPressButtonStyle())
            }
          }
        }
        .padding(18)
        .padding(.bottom, 28)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Choose Board")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private func iconType(for board: BoardDraft) -> BoardType {
    BoardType.samples.first { $0.name.localizedCaseInsensitiveCompare(board.type) == .orderedSame } ??
      BoardType(id: "component-target", name: board.type, subtitle: "", symbol: "rectangle.3.group.fill", color: board.color)
  }
}

struct ComponentRow: View {
  let theme: PanelTheme
  let component: PanelComponent
  let manufacturer: ManufacturerItem?
  let storedImage: UIImage?
  let isAdded: Bool
  let hasPhoto: Bool
  let toggleAdded: () -> Void
  let togglePhoto: () -> Void
  let savePhoto: (UIImage) -> Void
  let showDetails: () -> Void
  var deleteComponent: (() -> Void)? = nil
  @State private var selectedPhotoItem: PhotosPickerItem?

  private var displayImage: UIImage? {
    storedImage
  }

  private var manufacturerColor: Color {
    if let manufacturer {
      return manufacturer.color
    }
    switch component.manufacturer {
    case "ABB": return Color(hex: 0xFF3B30)
    case "Schneider": return Color(hex: 0x35E177)
    case "Siemens": return Color(hex: 0x18D4E8)
    case "Eaton": return Color(hex: 0x5E78FF)
    default: return theme.primary
    }
  }

  var body: some View {
    GlassCard(theme: theme) {
      HStack(spacing: 12) {
        EquipmentBrandBadge(name: component.manufacturer, image: manufacturer?.image)
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
          Group {
            if let displayImage {
              TransparentImageBubble(
                image: displayImage,
                width: 54,
                height: 54,
                cornerRadius: 12,
                glowColor: manufacturerColor
              )
            } else {
              ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(manufacturerColor.opacity(0.10))
                VStack(spacing: 3) {
                  Image(systemName: "photo.badge.plus")
                  Text("Add")
                    .font(.caption2.bold())
                }
                .foregroundStyle(manufacturerColor.opacity(0.85))
              }
              .frame(width: 54, height: 54)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
          }
          .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
        .onChange(of: selectedPhotoItem) { item in
          loadComponentImage(from: item)
        }
        Button(action: showDetails) {
          VStack(alignment: .leading, spacing: 4) {
            Text(component.displayName)
              .font(.system(size: 16, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            Text(component.detailLine)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            HStack(spacing: 6) {
              EquipmentPill(text: component.type, color: manufacturerColor)
              EquipmentPill(text: component.poles, color: Color(hex: 0x7FA6C9))
              EquipmentPill(text: component.ratingLabel, color: Color(hex: 0x7FAE9A))
            }
          }
        }
        .buttonStyle(.plain)
        Spacer()
        if let deleteComponent {
          DeleteIconButton(theme: theme, action: deleteComponent)
        }
        Button(action: showDetails) {
          Image(systemName: "info.circle.fill")
            .foregroundStyle(manufacturerColor)
            .font(.title3)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        Button(action: toggleAdded) {
          Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
            .foregroundStyle(isAdded ? Color(hex: 0x7FAE9A) : manufacturerColor)
            .font(.title3)
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 74)
    }
    .background(manufacturerColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(manufacturerColor.opacity(0.18), lineWidth: 1)
    )
    .shadow(color: manufacturerColor.opacity(0.12), radius: 10, x: 0, y: 0)
  }

  private func loadComponentImage(from item: PhotosPickerItem?) {
    Task {
      guard let data = try? await item?.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else { return }
      await MainActor.run {
        selectedPhotoItem = nil
        savePhoto(image)
      }
    }
  }
}

struct ComponentRatingSheet: View {
  let theme: PanelTheme
  let component: PanelComponent
  let onAdd: (PanelComponent) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var rating: String
  @State private var poles: String

  init(theme: PanelTheme, component: PanelComponent, onAdd: @escaping (PanelComponent) -> Void) {
    self.theme = theme
    self.component = component
    self.onAdd = onAdd
    _rating = State(initialValue: component.rating)
    _poles = State(initialValue: component.poles)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
              InfoLine(title: "Manufacturer", value: component.manufacturer)
              InfoLine(title: "Type", value: component.type)
              InfoLine(title: "Model", value: component.model)
            }
          }

          RatingChipSection(
            theme: theme,
            title: "Ampere / Rating",
            options: AmpereRating.all,
            selection: $rating
          )

          RatingChipSection(
            theme: theme,
            title: "Poles / Phase",
            options: PoleRating.all,
            selection: $poles
          )
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Set Rating")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add") {
            let cleanedRating = normalizedRating
            onAdd(
              PanelComponent(
                id: "\(component.id)-\(cleanedRating)-\(UUID().uuidString)",
                manufacturer: component.manufacturer,
                type: component.type,
                model: component.model,
                rating: cleanedRating,
                poles: poles,
                curve: component.curve,
                sourceID: component.imageStorageID
              )
            )
            dismiss()
          }
          .disabled(rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .fontWeight(.bold)
        }
      }
    }
  }

  private var normalizedRating: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return component.rating }
    if trimmed.rangeOfCharacter(from: .letters) == nil &&
        (component.type.localizedCaseInsensitiveContains("MCB") ||
         component.type.localizedCaseInsensitiveContains("MCCB") ||
         component.type.localizedCaseInsensitiveContains("Contactor")) {
      return "\(trimmed)A"
    }
    return trimmed
  }
}

struct RatingChipSection: View {
  let theme: PanelTheme
  let title: String
  let options: [String]
  @Binding var selection: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
        ForEach(options, id: \.self) { option in
          Button {
            withAnimation(.easeOut(duration: 0.14)) {
              selection = option
            }
          } label: {
            Text(option)
              .font(.system(size: 12, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .foregroundStyle(selection == option ? .white : .primary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 10)
              .background(selection == option ? theme.primary : theme.surface.opacity(0.84))
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .stroke(selection == option ? .clear : .white.opacity(0.08), lineWidth: 1)
              )
          }
          .buttonStyle(PanelPressButtonStyle())
        }
      }
    }
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

struct AddComponentSheet: View {
  let theme: PanelTheme
  let manufacturerNames: [String]
  let onAdd: (PanelComponent) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var manufacturer = "ABB"
  @State private var type = "MCB"
  @State private var customManufacturer = ""
  @State private var customType = ""
  @State private var model = ""
  @State private var rating = "63A"
  @State private var poles = "3P"
  @State private var curve = "C Curve"

  private var canAdd: Bool {
    !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !resolvedManufacturer.isEmpty &&
      !resolvedType.isEmpty
  }

  private var resolvedManufacturer: String {
    manufacturer == "Other" ? customManufacturer.trimmingCharacters(in: .whitespacesAndNewlines) : manufacturer
  }

  private var resolvedType: String {
    type == "Other" ? customType.trimmingCharacters(in: .whitespacesAndNewlines) : type
  }

  private var isMCBType: Bool {
    resolvedType.localizedCaseInsensitiveCompare("MCB") == .orderedSame
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Company") {
          Picker("Manufacturer", selection: $manufacturer) {
            ForEach(Array(Set(manufacturerNames)).sorted() + ["Other"], id: \.self) { Text($0) }
          }
          if manufacturer == "Other" {
            TextField("Manufacturer name", text: $customManufacturer)
          }
          Picker("Equipment Type", selection: $type) {
            ForEach(EquipmentTypeCatalog.all + ["Other"], id: \.self) { Text($0) }
          }
          if type == "Other" {
            TextField("Equipment type", text: $customType)
          }
        }

        Section("Specification") {
          TextField("Model", text: $model)
          HStack {
            TextField("Ampere / rating", text: $rating)
              .keyboardType(.numberPad)
            if isMCBType || resolvedType.localizedCaseInsensitiveContains("MCCB") || resolvedType.localizedCaseInsensitiveContains("Contactor") {
              Text("A")
                .foregroundStyle(.secondary)
            }
          }
          Picker("Poles", selection: $poles) {
            ForEach(PoleRating.all, id: \.self) { Text($0) }
          }
          if isMCBType {
            TextField("Curve", text: $curve)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        BottomTabClearance()
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Add Component")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add") {
            onAdd(
              PanelComponent(
                id: "custom-\(UUID().uuidString)",
                manufacturer: resolvedManufacturer,
                type: resolvedType,
                model: model,
                rating: normalizedRating,
                poles: poles,
                curve: isMCBType ? curve : ""
              )
            )
            dismiss()
          }
          .disabled(!canAdd)
          .fontWeight(.bold)
        }
      }
    }
  }

  private var normalizedRating: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.rangeOfCharacter(from: .letters) == nil &&
        (isMCBType || resolvedType.localizedCaseInsensitiveContains("MCCB") || resolvedType.localizedCaseInsensitiveContains("Contactor")) {
      return "\(trimmed)A"
    }
    return trimmed
  }
}

struct GlassCard<Content: View>: View {
  let theme: PanelTheme
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(14)
      .background(theme.surface.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(.white.opacity(0.07), lineWidth: 1)
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

struct ImagePreviewItem: Identifiable {
  let id = UUID()
  let image: UIImage
}

struct ImagePreviewSheet: View {
  let image: UIImage
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .padding()
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.bold)
        }
      }
    }
  }
}

struct PanelVaultLogoMark: View {
  let theme: PanelTheme
  let size: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        .fill(
          LinearGradient(
            colors: [theme.primary, theme.secondary.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
        .stroke(.white.opacity(0.26), lineWidth: max(size * 0.045, 1))
        .padding(size * 0.18)
      VStack(spacing: size * 0.06) {
        HStack(spacing: size * 0.06) {
          logoSlot
          logoSlot
        }
        HStack(spacing: size * 0.06) {
          logoSlot
          Image(systemName: "bolt.fill")
            .font(.system(size: size * 0.18, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size * 0.18, height: size * 0.18)
        }
      }
    }
    .frame(width: size, height: size)
    .shadow(color: theme.primary.opacity(0.24), radius: 12, y: 6)
  }

  private var logoSlot: some View {
    RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
      .fill(.white.opacity(0.82))
      .frame(width: size * 0.18, height: size * 0.18)
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

struct EquipmentBrandBadge: View {
  let name: String
  var image: UIImage? = nil

  var body: some View {
    Group {
      if let image {
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
    .frame(width: image == nil ? 50 : 50, height: image == nil ? 28 : 50)
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

struct EquipmentPill: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(color)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
  }
}

struct CompanyRow: View {
  let theme: PanelTheme
  let title: String
  let subtitle: String
  let color: Color
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "building.2")
          .foregroundStyle(color)
          .frame(width: 36, height: 36)
          .background(color.opacity(0.14))
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.system(size: 16, weight: .bold))
          Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
          .foregroundStyle(selected ? color : .secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(selected ? color.opacity(0.12) : .white.opacity(0.045))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

struct ThemeRow: View {
  let theme: PanelTheme
  let selected: Bool

  var body: some View {
    HStack {
      HStack(spacing: 0) {
        theme.background
        theme.primary
        theme.secondary
      }
      .frame(width: 46, height: 46)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(theme.name).font(.headline)
        Text(theme.description).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: selected ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(selected ? theme.primary : .secondary)
    }
    .padding(12)
    .background(theme.surface.opacity(0.82))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct ThemePickerRow: View {
  let theme: PanelTheme
  let selectedTheme: PanelTheme

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 0) {
        selectedTheme.background
        selectedTheme.primary
        selectedTheme.secondary
      }
      .frame(width: 42, height: 42)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text("Theme").font(.headline)
        Text(selectedTheme.name).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right").foregroundStyle(.secondary)
    }
    .padding(12)
    .background(theme.surface.opacity(0.78))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct ThemePickerSheet: View {
  let theme: PanelTheme
  @Binding var selectedThemeID: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(PanelTheme.all) { option in
            Button {
              selectedThemeID = option.id
              dismiss()
            } label: {
              ThemeRow(theme: option, selected: option.id == selectedThemeID)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Theme")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

struct DisplaySizePickerSheet: View {
  let theme: PanelTheme
  @Binding var selectedInterfaceSizeID: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(InterfaceSize.all) { option in
            Button {
              selectedInterfaceSizeID = option.id
              dismiss()
            } label: {
              GlassCard(theme: theme) {
                HStack(spacing: 12) {
                  Image(systemName: option.id == "compact" ? "rectangle.compress.vertical" : option.id == "large" ? "rectangle.expand.vertical" : "rectangle.dashed")
                    .foregroundStyle(theme.primary)
                    .frame(width: 40, height: 40)
                    .background(theme.primary.opacity(0.14))
                    .clipShape(Circle())
                  VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                      .font(.headline)
                    Text(option.subtitle)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: option.id == selectedInterfaceSizeID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(option.id == selectedInterfaceSizeID ? theme.primary : .secondary)
                }
              }
            }
            .buttonStyle(PanelPressButtonStyle())
          }
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Dashboard Size")
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
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

struct PanelTheme: Identifiable, Equatable {
  let id: String
  let name: String
  let description: String
  let background: Color
  let surface: Color
  let primary: Color
  let secondary: Color

  static let vaultPurple = PanelTheme(id: "vault-purple", name: "Obsidian Blue", description: "Black glass with precise blue controls", background: Color(hex: 0x050607), surface: Color(hex: 0x121417), primary: Color(hex: 0x6E86FF), secondary: Color(hex: 0x4CC9F0))
  static let graphiteCopper = PanelTheme(id: "graphite-copper", name: "Carbon Steel", description: "Neutral graphite with soft silver-blue", background: Color(hex: 0x060708), surface: Color(hex: 0x15171A), primary: Color(hex: 0xB8C2D6), secondary: Color(hex: 0x5D7CFA))
  static let emeraldGrid = PanelTheme(id: "emerald-grid", name: "Switchgear Green", description: "Deep black-green for completion work", background: Color(hex: 0x040807), surface: Color(hex: 0x101916), primary: Color(hex: 0x48D597), secondary: Color(hex: 0x7AD7C4))
  static let oceanControl = PanelTheme(id: "ocean-control", name: "Control Teal", description: "Dark technical teal with cool contrast", background: Color(hex: 0x04090C), surface: Color(hex: 0x0F171B), primary: Color(hex: 0x31D7C8), secondary: Color(hex: 0x4E9DFF))
  static let blackout = PanelTheme(id: "blackout", name: "Blackout", description: "Almost pure black with quiet white controls", background: Color(hex: 0x020304), surface: Color(hex: 0x101113), primary: Color(hex: 0xF2F5F7), secondary: Color(hex: 0x8A98A8))
  static let deepMarine = PanelTheme(id: "deep-marine", name: "Deep Marine", description: "Navy-black with professional cyan accents", background: Color(hex: 0x03070D), surface: Color(hex: 0x0D1420), primary: Color(hex: 0x3EA7FF), secondary: Color(hex: 0x38E8B0))
  static let all = [vaultPurple, graphiteCopper, blackout, deepMarine, oceanControl, emeraldGrid]
}

struct ContractorCompany: Identifiable, Equatable {
  let id: String
  let name: String
  let role: String
  let projectCount: String
  let color: Color

  var persistenceSignature: String {
    "\(id)|\(name)|\(role)|\(projectCount)|\(color.archiveHex)"
  }

  static let samples: [ContractorCompany] = []
}

struct CustomerItem: Identifiable, Equatable {
  let id: String
  var name: String
  var kind: String
  var contactName: String
  var phone: String
  var note: String

  init(id: String = "customer-\(UUID().uuidString)", name: String, kind: String = "Company", contactName: String = "", phone: String = "", note: String = "") {
    self.id = id
    self.name = name
    self.kind = kind
    self.contactName = contactName
    self.phone = phone
    self.note = note
  }

  var persistenceSignature: String {
    "\(id)|\(name)|\(kind)|\(contactName)|\(phone)|\(note)"
  }
}

struct RecentVisit: Identifiable, Equatable {
  enum Kind: String {
    case project
    case board
  }

  let kind: Kind
  let itemID: String

  init(kind: Kind, id: String) {
    self.kind = kind
    self.itemID = id
  }

  var identifier: String {
    "\(kind.rawValue)-\(itemID)"
  }
}

extension RecentVisit {
  var id: String { identifier }
}

struct RecentBoardSelection: Identifiable {
  let id: String
}

struct SchemeAttachment: Identifiable, Equatable {
  enum Kind: Equatable {
    case pdf
    case photo
  }

  let id: String
  let kind: Kind
  var name: String
  var image: UIImage?
  var url: URL?

  static func == (lhs: SchemeAttachment, rhs: SchemeAttachment) -> Bool {
    lhs.id == rhs.id &&
      lhs.kind == rhs.kind &&
      lhs.name == rhs.name &&
      lhs.url == rhs.url &&
      (lhs.image != nil) == (rhs.image != nil)
  }

  init(id: String = "scheme-\(UUID().uuidString)", kind: Kind, name: String, image: UIImage?, url: URL? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.image = image
    self.url = url
  }

  var persistenceSignature: String {
    [
      id,
      kind == .pdf ? "pdf" : "photo",
      name,
      url?.absoluteString ?? "",
      ImageArchive.signature(for: image)
    ].joined(separator: "|")
  }
}

struct ManufacturerItem: Identifiable {
  let id: String
  var name: String
  var colorHex: UInt32
  var image: UIImage? = nil

  init(id: String = "manufacturer-\(UUID().uuidString)", name: String, colorHex: UInt32 = 0x5E78FF, image: UIImage? = nil) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.image = image
  }

  var color: Color {
    Color(hex: colorHex)
  }

  var initials: String {
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap(\.first)
    return letters.isEmpty ? String(name.prefix(2)).uppercased() : String(letters).uppercased()
  }

  var persistenceSignature: String {
    let imageSignature = ImageArchive.signature(for: image)
    return "\(id)|\(name)|\(colorHex)|\(imageSignature)"
  }

  static let defaults = [
    ManufacturerItem(id: "rittal", name: "Rittal", colorHex: 0x5E78FF),
    ManufacturerItem(id: "abb", name: "ABB", colorHex: 0xFF3B30),
    ManufacturerItem(id: "yakir", name: "Yakir", colorHex: 0x35E177),
    ManufacturerItem(id: "tamhash", name: "Tamhash", colorHex: 0xFF9F0A),
    ManufacturerItem(id: "hager", name: "HAGER", colorHex: 0x64D2FF),
    ManufacturerItem(id: "delta", name: "Delta", colorHex: 0x0A84FF),
    ManufacturerItem(id: "schneider", name: "Schneider", colorHex: 0x35E177),
    ManufacturerItem(id: "siemens", name: "Siemens", colorHex: 0x18D4E8),
    ManufacturerItem(id: "eaton", name: "Eaton", colorHex: 0x5E78FF),
    ManufacturerItem(id: "legrand", name: "Legrand", colorHex: 0xD85CFF),
    ManufacturerItem(id: "mean-well", name: "Mean Well", colorHex: 0xFFD60A),
    ManufacturerItem(id: "phoenix", name: "Phoenix", colorHex: 0xFF9F0A),
    ManufacturerItem(id: "generic", name: "Generic", colorHex: 0xAEB4BC)
  ]
}

struct PanelStat: Identifiable {
  let id: String
  let title: String
  let value: String
  let symbol: String
  let color: Color

  static let samples = [
    PanelStat(id: "projects", title: "Projects", value: "214", symbol: "folder.fill", color: Color(hex: 0x7FAE9A)),
    PanelStat(id: "photos", title: "Photos", value: "8426", symbol: "photo.fill", color: Color(hex: 0x7FA6C9)),
    PanelStat(id: "companies", title: "Companies", value: "19", symbol: "building.2.fill", color: Color(hex: 0xAEB4BC)),
    PanelStat(id: "customers", title: "Customers", value: "67", symbol: "person.2.fill", color: Color(hex: 0xA895C8))
  ]
}

struct BoardType: Identifiable {
  let id: String
  let name: String
  let subtitle: String
  let symbol: String
  let color: Color
  var emoji: String? = nil
  var localName: String? = nil
  var overview: String? = nil
  var typicalUses: [String] = []
  var typicalComponents: [String] = []
  var designChecks: [String] = []
  var notes: [String] = []

  static let fallback = BoardType(
    id: "board",
    name: "Board",
    subtitle: "Distribution board",
    symbol: "rectangle.3.group.fill",
    color: Color(hex: 0x5E78FF),
    overview: "A general low-voltage electrical assembly used to distribute, protect, control, meter or switch electrical circuits.",
    typicalUses: ["General project documentation", "Custom boards that do not fit a standard category"],
    typicalComponents: ["Main isolator or breaker", "MCBs/MCCBs", "Busbars", "Terminals", "N and PE bars"],
    designChecks: ["Rated current", "Short-circuit rating", "IP rating", "Cable entries", "Clear labeling"]
  )

  static let samples = [
    BoardType(id: "main-lv", name: "Main LV Board", subtitle: "Main low-voltage intake", symbol: "bolt.fill", color: Color(hex: 0x0A84FF), localName: "לוח ראשי", overview: "The main low-voltage switchboard for a building, floor group, factory area or service. It receives the main supply and distributes power downstream to sub boards, mechanical loads and specialist panels.", typicalUses: ["Commercial and industrial main supply", "Building incoming service", "Factory main distribution"], typicalComponents: ["Main ACB/MCCB or switch disconnector", "Metering and CTs", "Busbars", "Surge protection", "Outgoing MCCBs"], designChecks: ["Incoming supply and service size", "Icu/Ics short-circuit rating", "Form of separation", "Ventilation and heat rise", "Clear source and outgoing labels"], notes: ["Often called לוח ראשי in Israel.", "Commonly documented against IEC 61439 low-voltage assembly concepts."]),
    BoardType(id: "mdb", name: "MDB", subtitle: "Main Distribution", symbol: "bolt.square.fill", color: Color(hex: 0x5E78FF), localName: "לוח חלוקה ראשי", overview: "A main distribution board that splits a major feeder into multiple outgoing feeders. It may be the main LV board or a major distribution board below the main intake.", typicalUses: ["Office towers", "Malls", "Hospitals", "Large public buildings"], typicalComponents: ["Main MCCB/ACB", "Outgoing MCCBs", "Busbar system", "Power meter", "SPD"], designChecks: ["Load diversity", "Phase balance", "Cable termination space", "Future spare ways", "Selective protection coordination"]),
    BoardType(id: "sub-distribution", name: "Sub Distribution", subtitle: "Sub boards", symbol: "point.3.connected.trianglepath.dotted", color: Color(hex: 0x18D4E8), localName: "לוח משנה", overview: "A downstream distribution board fed from a main board or MDB. It supplies a zone, floor, tenant, machine area or service room.", typicalUses: ["Floor boards", "Tenant boards", "Mechanical-room sub boards", "Area distribution"], typicalComponents: ["Incoming isolator/MCCB", "MCBs/RCBOs", "RCD/RCCB protection", "N and PE bars", "DIN rails"], designChecks: ["Feeder rating", "Voltage drop", "Fault loop/short-circuit level", "RCD requirements", "Circuit labeling"]),
    BoardType(id: "mcc", name: "MCC", subtitle: "Motor Control Center", symbol: "gearshape.fill", color: Color(hex: 0x35E177), localName: "לוח מנועים / MCC", overview: "A board dedicated to motor feeders and motor control. It centralizes motor protection, switching, control and automation interfaces.", typicalUses: ["Pumps", "Fans", "Conveyors", "Industrial machines", "HVAC plant"], typicalComponents: ["MCCBs/MCBs", "Contactors", "Overload relays", "VFDs or soft starters", "Control transformers", "PLC/IO terminals"], designChecks: ["Motor kW and starting method", "AC-3 contactor rating", "Overload setting range", "Control voltage", "Ventilation for drives"]),
    BoardType(id: "cabinet-collection", name: "Cabinet Collection", subtitle: "Multi-cabinet assembly", symbol: "rectangle.3.group.bubble.left.fill", color: Color(hex: 0x8EA2FF), localName: "מערך ארונות", overview: "A cabinet collection is a board record used when one electrical board is physically built from several connected cabinets or bays. It keeps the cabinets grouped under one board number while still allowing build progress and photos to be tracked together.", typicalUses: ["Multi-cabinet MDBs", "Large MCC lineups", "Sectioned distribution boards", "Panel rows with shared busbars"], typicalComponents: ["Shared busbar system", "Inter-cabinet wiring", "Main breaker section", "Outgoing feeder sections", "N and PE bars"], designChecks: ["Cabinet order", "Busbar continuity", "Inter-cabinet links", "Transport split points", "Consistent labels across cabinets"]),
    BoardType(id: "ats", name: "ATS", subtitle: "Automatic Transfer Switch", symbol: "arrow.left.arrow.right", color: Color(hex: 0x8B4DFF), localName: "לוח החלפה / ATS", overview: "A transfer board that switches loads between normal utility supply and an alternate source such as generator or UPS. It may be automatic or manual depending on project needs.", typicalUses: ["Generator-backed buildings", "Critical loads", "Fire/safety services", "Data and telecom rooms"], typicalComponents: ["Motorized changeover switch or contactors", "Controller", "Source voltage sensing", "Mechanical/electrical interlocking", "Bypass or manual mode"], designChecks: ["Source interlocking", "Neutral switching method", "Generator start signal", "Transfer delay settings", "Load priority"]),
    BoardType(id: "metering", name: "Metering Board", subtitle: "Meters and CTs", symbol: "gauge.with.dots.needle.67percent", color: Color(hex: 0x64D2FF), localName: "לוח מונים", overview: "A board or section used for energy metering, tenant metering, CT wiring and monitoring equipment.", typicalUses: ["Tenant billing", "Energy monitoring", "Utility/customer metering sections"], typicalComponents: ["Energy meters", "CTs", "Test blocks", "Voltage fuses", "Communication modules"], designChecks: ["CT ratio and class", "Sealable compartments", "Meter access", "Phase order", "Communication wiring"]),
    BoardType(id: "capacitor", name: "Capacitor Bank", subtitle: "Power factor correction", symbol: "waveform.path.ecg.rectangle.fill", color: Color(hex: 0xFFD60A), localName: "לוח קבלים", overview: "A power-factor correction board that switches capacitor stages to improve power factor and reduce reactive energy penalties.", typicalUses: ["Factories", "Large commercial buildings", "Motor-heavy installations"], typicalComponents: ["PFC controller", "Capacitor contactors", "Capacitor stages", "HRC fuses/MCCBs", "Detuned reactors when needed"], designChecks: ["kVAr sizing", "Harmonic environment", "Ventilation", "Discharge resistors", "Stage protection"]),
    BoardType(id: "control", name: "Control Board", subtitle: "Controls and automation", symbol: "switch.2", color: Color(hex: 0xD85CFF), localName: "לוח פיקוד", overview: "A control panel focused on command, indication, automation and interlocking rather than heavy power distribution.", typicalUses: ["Machine control", "Pump control", "HVAC control", "Process automation"], typicalComponents: ["PLC or controller", "Relays", "Timers", "Power supplies", "Terminals", "Selector switches and lamps"], designChecks: ["Control voltage", "Input/output list", "Fail-safe logic", "Cable numbering", "Door controls and indicators"]),
    BoardType(id: "lighting", name: "Lighting", subtitle: "Lighting boards", symbol: "lightbulb.fill", color: Color(hex: 0xFFD60A), localName: "לוח תאורה", overview: "A distribution board dedicated to lighting circuits, lighting control and sometimes emergency lighting groups.", typicalUses: ["Office floors", "Public areas", "Exterior lighting", "Emergency lighting circuits"], typicalComponents: ["MCBs/RCBOs", "Contactors", "Astronomical clock or timer", "Lighting controllers", "RCD protection"], designChecks: ["Circuit grouping", "Emergency/normal separation", "Control schedule", "RCD selectivity", "Clear room/area labels"]),
    BoardType(id: "power", name: "Power", subtitle: "Power boards", symbol: "powerplug.fill", color: Color(hex: 0xFF4E5F), localName: "לוח כח", overview: "A board feeding socket circuits, small power, dedicated equipment outlets and general power loads.", typicalUses: ["Workstations", "Kitchen equipment", "Workshop outlets", "Mechanical service outlets"], typicalComponents: ["MCBs/RCBOs", "RCDs", "Socket circuit terminals", "Main isolator", "N and PE bars"], designChecks: ["Load per circuit", "RCD protection", "Dedicated equipment circuits", "Socket labeling", "Spare capacity"]),
    BoardType(id: "apartment", name: "Apartment", subtitle: "Residential boards", symbol: "house.fill", color: Color(hex: 0x35C7D7), localName: "לוח דירתי", overview: "A residential distribution board serving an apartment or small dwelling, usually with final circuits for lighting, sockets, HVAC and appliances.", typicalUses: ["Apartments", "Small homes", "Residential units"], typicalComponents: ["Main switch", "RCD/RCCB", "MCBs/RCBOs", "Surge protection", "N and PE bars"], designChecks: ["Circuit count", "RCD arrangement", "Main rating", "Future spaces", "Clear room/appliance labels"]),
    BoardType(id: "generator", name: "Generator Board", subtitle: "Generator distribution", symbol: "fuelpump.fill", color: Color(hex: 0xFF9F0A), localName: "לוח גנרטור", overview: "A board associated with generator output, protection, synchronization or distribution to emergency/backup loads.", typicalUses: ["Backup supply", "Emergency power rooms", "Generator packages"], typicalComponents: ["Generator MCCB/ACB", "Controller terminals", "Meters", "Protection relays", "Outgoing breakers"], designChecks: ["Generator rating", "Earthing/neutral method", "ATS interface", "Short-circuit contribution", "Load shedding"]),
    BoardType(id: "ups", name: "UPS Board", subtitle: "Critical power", symbol: "battery.100percent.bolt", color: Color(hex: 0x34C759), localName: "לוח UPS", overview: "A board feeding or distributing uninterruptible power supply circuits for critical equipment.", typicalUses: ["Server rooms", "Security systems", "Medical/critical equipment", "Control systems"], typicalComponents: ["UPS input/output breakers", "Maintenance bypass", "Critical load MCBs", "Meters", "Warning labels"], designChecks: ["Bypass arrangement", "Load criticality", "Neutral continuity", "Battery room/interface", "Segregation from normal power"]),
    BoardType(id: "pv", name: "PV Solar", subtitle: "Solar AC/DC board", symbol: "sun.max.fill", color: Color(hex: 0xFFCC00), localName: "לוח סולארי", overview: "A photovoltaic board for inverter AC output, DC string combining, protection or solar system isolation.", typicalUses: ["Rooftop PV", "Commercial solar systems", "Inverter rooms"], typicalComponents: ["DC isolators", "String fuses", "SPD DC/AC", "AC breakers", "Inverter feeders"], designChecks: ["DC voltage rating", "Polarity", "SPD type", "Inverter AC rating", "Warning labels and isolation"]),
    BoardType(id: "ev", name: "EV Charging", subtitle: "Charging infrastructure", symbol: "ev.charger.fill", color: Color(hex: 0x00C7BE), localName: "לוח טעינה לרכב חשמלי", overview: "A board dedicated to electric vehicle charging circuits and load management equipment.", typicalUses: ["Parking lots", "Residential charging rooms", "Commercial EV chargers"], typicalComponents: ["MCCBs/MCBs", "RCD type A/B or RDC-DD coordination", "Meters", "Load management controller", "Surge protection"], designChecks: ["Charger rating", "Diversity/load management", "RCD type", "Cable route length", "Metering and access"]),
    BoardType(id: "temporary-site", name: "Site Temporary", subtitle: "Construction site power", symbol: "hammer.fill", color: Color(hex: 0xAEB4BC), localName: "לוח זמני לאתר", overview: "A temporary distribution board for construction sites or temporary works, often ruggedized and protected for outdoor/site conditions.", typicalUses: ["Construction sites", "Temporary events", "Site cabins", "Temporary tools"], typicalComponents: ["Main breaker/RCD", "Socket outlets", "Outgoing MCBs", "Enclosure with high IP rating", "Earthing terminals"], designChecks: ["Outdoor/IP protection", "RCD protection", "Mechanical protection", "Temporary earthing", "Inspection labeling"]),
    BoardType(id: "fire-pump", name: "Fire Pump", subtitle: "Life-safety motor board", symbol: "flame.fill", color: Color(hex: 0xFF453A), localName: "לוח משאבות כיבוי", overview: "A specialized control and power board for fire pumps and related life-safety equipment.", typicalUses: ["Fire pump rooms", "Sprinkler systems", "Emergency water systems"], typicalComponents: ["Main isolator/breaker", "Pump contactors or soft starter", "Controller", "Alarms", "Pressure switch terminals"], designChecks: ["Life-safety supply requirements", "Alarm outputs", "Manual/auto operation", "Motor starting current", "Clear emergency labeling"]),
    BoardType(id: "hvac", name: "HVAC", subtitle: "Mechanical services", symbol: "fan.fill", color: Color(hex: 0x5AC8FA), localName: "לוח מיזוג / אוורור", overview: "A board serving chillers, AHUs, fans, dampers and mechanical ventilation/control loads.", typicalUses: ["Air handling units", "Ventilation fans", "Chillers", "Mechanical plant rooms"], typicalComponents: ["MCCBs/MCBs", "Contactors", "VFDs", "Overloads", "Control relays", "BMS terminals"], designChecks: ["Motor and drive heat", "BMS interface", "Local/remote control", "Maintenance isolators", "Fault indication"]),
    BoardType(id: "elv-bms", name: "ELV / BMS", subtitle: "Low-current systems", symbol: "network", color: Color(hex: 0xAF52DE), localName: "לוח תקשורת / בקרה", overview: "A low-current or building-management panel for control, communications and monitoring equipment. It is usually separate from power distribution.", typicalUses: ["BMS panels", "Security interfaces", "Communication cabinets", "Monitoring systems"], typicalComponents: ["Power supplies", "Network switches", "Controllers", "Relays", "Terminal blocks"], designChecks: ["Separation from power circuits", "24VDC load sizing", "Network labeling", "Backup supply", "Cable management"]),
    BoardType(id: "pcc", name: "PCC", subtitle: "Power control center", symbol: "slider.horizontal.3", color: Color(hex: 0x30D158), localName: "לוח כח ראשי / PCC", overview: "A power control center is a heavy-duty low-voltage assembly used for main feeders, large loads and plant-level power distribution. It often sits close to transformers, generators or major mechanical loads.", typicalUses: ["Industrial plant rooms", "Large mechanical services", "Transformer outgoing distribution"], typicalComponents: ["ACBs/MCCBs", "Busbar system", "Metering", "Protection relays", "Outgoing feeders"], designChecks: ["Short-circuit level", "Form of separation", "Thermal rise", "Access and maintenance clearance", "Feeder selectivity"]),
    BoardType(id: "synchronizing", name: "Synchronizing", subtitle: "Generator sync board", symbol: "arrow.triangle.2.circlepath", color: Color(hex: 0x64D2FF), localName: "לוח סנכרון", overview: "A synchronizing board controls and protects parallel operation of generators or generator-to-grid arrangements. It monitors voltage, frequency, phase angle and load sharing before closing breakers.", typicalUses: ["Multiple generator sets", "Generator-grid parallel operation", "Critical facilities"], typicalComponents: ["Sync controller", "ACB/MCCB control", "Protection relays", "Meters", "Load sharing modules"], designChecks: ["Phase sequence", "Voltage and frequency windows", "Breaker interlocks", "Load sharing setup", "Protection coordination"]),
    BoardType(id: "bypass", name: "Bypass Board", subtitle: "Maintenance bypass", symbol: "arrow.uturn.right.circle.fill", color: Color(hex: 0xFF9F0A), localName: "לוח מעקף", overview: "A bypass board allows critical loads to remain supplied while UPS, ATS or other equipment is isolated for service. It must make the switching path clear and hard to operate incorrectly.", typicalUses: ["UPS maintenance", "ATS maintenance", "Critical service isolation"], typicalComponents: ["Bypass switch", "Interlocked isolators", "Indication lamps", "Warning labels", "Meters"], designChecks: ["Mechanical/electrical interlocks", "Clear operating sequence", "Neutral arrangement", "Load transfer path", "Warning labels"]),
    BoardType(id: "transformer", name: "Transformer Board", subtitle: "Transformer feeder", symbol: "square.stack.3d.up.fill", color: Color(hex: 0xBF5AF2), localName: "לוח שנאי", overview: "A transformer board handles incoming or outgoing protection and distribution around a transformer. It may include LV main protection, metering and temperature/alarm interfaces.", typicalUses: ["Transformer rooms", "Industrial substations", "Building LV rooms"], typicalComponents: ["Main ACB/MCCB", "Meters", "Protection relay inputs", "Temperature alarm terminals", "Busbars"], designChecks: ["Transformer kVA", "Inrush and protection settings", "Earthing system", "Ventilation", "Cable termination space"]),
    BoardType(id: "pump", name: "Pump Board", subtitle: "Water and process pumps", symbol: "drop.fill", color: Color(hex: 0x0A84FF), localName: "לוח משאבות", overview: "A pump board controls one or more water, sewage or process pumps. It may include direct-on-line starters, star-delta, soft starters or drives depending on pump size.", typicalUses: ["Booster pumps", "Sewage pumps", "Process pumps", "Irrigation systems"], typicalComponents: ["Contactors", "Overload relays", "VFDs or soft starters", "Float/pressure inputs", "Run/fault indication"], designChecks: ["Pump kW", "Duty/standby logic", "Sensor inputs", "Manual/auto control", "Alarm output"]),
    BoardType(id: "elevator", name: "Elevator", subtitle: "Lift supply board", symbol: "arrow.up.arrow.down.square.fill", color: Color(hex: 0x5E78FF), localName: "לוח מעלית", overview: "An elevator board supplies lift controllers and associated services. It often needs clear isolation, dedicated feeds and coordination with emergency or generator-backed supply.", typicalUses: ["Passenger lifts", "Service lifts", "Lift machine rooms"], typicalComponents: ["Main isolator/MCCB", "Auxiliary MCBs", "SPD", "Meters", "Emergency supply interface"], designChecks: ["Dedicated supply", "Rescue/emergency power", "Isolation access", "Labeling", "Manufacturer requirements"]),
    BoardType(id: "outdoor-lighting", name: "Outdoor Lighting", subtitle: "Street and facade lighting", symbol: "lightbulb.2.fill", color: Color(hex: 0xFFD60A), localName: "לוח תאורת חוץ", overview: "An outdoor lighting board feeds street, parking, facade or landscape lighting. It usually combines protection with automatic schedules and weather-ready enclosure choices.", typicalUses: ["Parking lots", "Street lighting", "Facade lighting", "Landscape lighting"], typicalComponents: ["MCBs/RCBOs", "Contactors", "Astronomical clock", "SPD", "Photocell inputs"], designChecks: ["IP rating", "Earthing", "Cable lengths", "Control schedule", "Surge exposure"]),
    BoardType(id: "pdu", name: "PDU", subtitle: "Data center distribution", symbol: "server.rack", color: Color(hex: 0x32D74B), localName: "לוח PDU", overview: "A power distribution unit board distributes critical power to server racks, telecom equipment or data cabinets. It often emphasizes metering, redundancy and clean circuit identification.", typicalUses: ["Server rooms", "Data centers", "Telecom spaces"], typicalComponents: ["Input MCCB", "Metering", "Branch MCBs", "RCD/RCM where required", "Monitoring modules"], designChecks: ["A/B feed separation", "Load monitoring", "Circuit labeling", "Neutral loading", "Thermal management"]),
    BoardType(id: "harmonic-filter", name: "Harmonic Filter", subtitle: "Power quality", symbol: "waveform.path", color: Color(hex: 0xFF375F), localName: "לוח סינון הרמוניות", overview: "A harmonic filter board reduces harmonic distortion caused by drives, UPS systems and non-linear loads. It may be passive or active depending on the installation.", typicalUses: ["Drive-heavy plants", "UPS rooms", "Large commercial buildings", "Power quality correction"], typicalComponents: ["Active filter module", "Detuned reactors", "Capacitors", "MCCB/fuses", "Controller"], designChecks: ["Measured THD", "Load profile", "Ventilation", "Protection sizing", "Power quality target"]),
    BoardType(id: "fire-alarm", name: "Fire Alarm", subtitle: "Life-safety controls", symbol: "bell.and.waves.left.and.right.fill", color: Color(hex: 0xFF453A), localName: "לוח גילוי אש", overview: "A fire alarm or life-safety interface panel organizes control power, relays and monitored circuits around fire detection and emergency systems. It should remain clearly separated from ordinary power distribution.", typicalUses: ["Fire alarm interfaces", "Smoke control interfaces", "Emergency command panels"], typicalComponents: ["Power supplies", "Relays", "Monitoring modules", "Terminal blocks", "Battery/interface wiring"], designChecks: ["Life-safety labeling", "Circuit supervision", "Backup supply", "Cable separation", "Alarm/fault outputs"]),
    BoardType(id: "earthing", name: "Earthing", subtitle: "Grounding and bonding", symbol: "point.bottomleft.forward.to.point.topright.scurvepath", color: Color(hex: 0x8E8E93), localName: "לוח הארקה", overview: "An earthing or bonding board centralizes grounding bars, test links and bonding connections for an installation. It is often simple physically but very important for safety and documentation.", typicalUses: ["Main earthing terminals", "Lightning protection bonds", "Telecom bonding", "Industrial equipotential bonding"], typicalComponents: ["Copper earth bar", "Test links", "Labels", "Bonding terminals", "Surge protection bonds"], designChecks: ["Conductor sizes", "Continuity", "Labeling", "Test accessibility", "Separation from live parts"])
  ]
}

struct ProjectItem: Identifiable {
  let id: String
  let name: String
  let customer: String
  let detail: String
  let status: String
  let color: Color
  var coverImage: UIImage? = nil
  var photoImages: [UIImage] = []
  var dueDate: Date? = nil
  var schemeAttachments: [SchemeAttachment] = []

  var searchText: String {
    "\(name) \(customer) \(detail) \(status) \(dueDate.map { DateDisplay.due.string(from: $0) } ?? "") \(schemeAttachments.map(\.name).joined(separator: " "))"
  }

  var persistenceSignature: String {
    let coverSignature = ImageArchive.signature(for: coverImage)
    let photoSignature = photoImages.map { ImageArchive.signature(for: $0) }.joined(separator: "|")
    let schemeSignature = schemeAttachments.map(\.persistenceSignature).joined(separator: "|")
    return [
      id, name, customer, detail, status, "\(color.archiveHex)",
      coverSignature, photoSignature,
      "\(dueDate?.timeIntervalSince1970 ?? 0)",
      schemeSignature
    ].joined(separator: "||")
  }

  static let samples: [ProjectItem] = []
}

struct ComponentGroup: Identifiable {
  let id: String
  let name: String
  let items: [PanelComponent]

  static let samples = [
    ComponentGroup(id: "mcbs", name: "MCBs", items: [
      PanelComponent(id: "abb-s201-1p", manufacturer: "ABB", type: "MCB", model: "S201", rating: "Set A", poles: "1P", curve: "B/C/D Curve"),
      PanelComponent(id: "abb-s202-2p", manufacturer: "ABB", type: "MCB", model: "S202", rating: "Set A", poles: "2P", curve: "B/C/D Curve"),
      PanelComponent(id: "abb-s203-3p", manufacturer: "ABB", type: "MCB", model: "S203", rating: "Set A", poles: "3P", curve: "B/C/D Curve"),
      PanelComponent(id: "abb-s204-4p", manufacturer: "ABB", type: "MCB", model: "S204", rating: "Set A", poles: "4P", curve: "B/C/D Curve"),
      PanelComponent(id: "abb-sn201-1pn", manufacturer: "ABB", type: "MCB", model: "SN201", rating: "Set A", poles: "1P+N", curve: "B/C Curve"),
      PanelComponent(id: "abb-s300-p", manufacturer: "ABB", type: "MCB", model: "S300 P", rating: "Set A", poles: "1P-4P", curve: "Industrial"),
      PanelComponent(id: "abb-su200", manufacturer: "ABB", type: "MCB", model: "SU200", rating: "Set A", poles: "1P-4P", curve: "UL/CSA"),
      PanelComponent(id: "schneider-ic60n", manufacturer: "Schneider", type: "MCB", model: "Acti9 iC60N", rating: "Set A", poles: "1P-4P", curve: "B/C/D"),
      PanelComponent(id: "schneider-ic60h", manufacturer: "Schneider", type: "MCB", model: "Acti9 iC60H", rating: "Set A", poles: "1P-4P", curve: "B/C/D"),
      PanelComponent(id: "siemens-5sy", manufacturer: "Siemens", type: "MCB", model: "SENTRON 5SY", rating: "Set A", poles: "1P-4P", curve: "B/C/D"),
      PanelComponent(id: "siemens-5sl", manufacturer: "Siemens", type: "MCB", model: "SENTRON 5SL", rating: "Set A", poles: "1P-4P", curve: "B/C/D"),
      PanelComponent(id: "eaton-faz", manufacturer: "Eaton", type: "MCB", model: "FAZ", rating: "Set A", poles: "1P-4P", curve: "B/C/D")
    ]),
    ComponentGroup(id: "rcbo", name: "RCBOs", items: [
      PanelComponent(id: "abb-ds201-1pn", manufacturer: "ABB", type: "RCBO", model: "DS201", rating: "Set A", poles: "1P+N", curve: "B/C Curve + RCD"),
      PanelComponent(id: "abb-ds202-2p", manufacturer: "ABB", type: "RCBO", model: "DS202", rating: "Set A", poles: "2P", curve: "B/C Curve + RCD"),
      PanelComponent(id: "abb-ds203-3p", manufacturer: "ABB", type: "RCBO", model: "DS203", rating: "Set A", poles: "3P", curve: "B/C Curve + RCD"),
      PanelComponent(id: "abb-ds204-4p", manufacturer: "ABB", type: "RCBO", model: "DS204", rating: "Set A", poles: "4P", curve: "B/C Curve + RCD"),
      PanelComponent(id: "schneider-acti9-rcbo", manufacturer: "Schneider", type: "RCBO", model: "Acti9 iDPN Vigi", rating: "Set A", poles: "1P+N", curve: "B/C + RCD")
    ]),
    ComponentGroup(id: "mccbs", name: "MCCBs", items: [
      PanelComponent(id: "abb-tmax-xt1", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT1", rating: "Set A - max 160A", poles: "3P/4P", curve: "Basic - thermal-magnetic"),
      PanelComponent(id: "abb-tmax-xt2", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT2", rating: "Set A - max 160A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch"),
      PanelComponent(id: "abb-tmax-xt3", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT3", rating: "Set A - max 250A", poles: "3P/4P", curve: "Basic - thermal-magnetic"),
      PanelComponent(id: "abb-tmax-xt4", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT4", rating: "Set A - max 250A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch"),
      PanelComponent(id: "abb-tmax-xt5", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT5", rating: "Set A - max 630A", poles: "3P/4P", curve: "Heavy duty - TM/Ekip Dip/Touch"),
      PanelComponent(id: "abb-tmax-xt6", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT6", rating: "Set A - max 1000A", poles: "3P/4P", curve: "Basic - thermal-magnetic/Ekip Dip"),
      PanelComponent(id: "abb-tmax-xt7", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT7", rating: "Set A - max 1600A", poles: "3P/4P", curve: "Heavy duty - Ekip Dip/Touch"),
      PanelComponent(id: "abb-tmax-xt7m", manufacturer: "ABB", type: "MCCB", model: "SACE Tmax XT7 M", rating: "Set A - max 1600A", poles: "3P/4P", curve: "Motorized - Ekip Dip/Touch"),
      PanelComponent(id: "schneider-nsx", manufacturer: "Schneider", type: "MCCB", model: "Compact NSX", rating: "16-630A", poles: "3P/4P", curve: "TM/Micrologic"),
      PanelComponent(id: "schneider-nsj", manufacturer: "Schneider", type: "MCCB", model: "EasyPact CVS/NSX", rating: "16-630A", poles: "3P/4P", curve: "Thermal Magnetic"),
      PanelComponent(id: "siemens-3va1", manufacturer: "Siemens", type: "MCCB", model: "SENTRON 3VA1", rating: "16-160A", poles: "3P/4P", curve: "Thermal Magnetic"),
      PanelComponent(id: "siemens-3va2", manufacturer: "Siemens", type: "MCCB", model: "SENTRON 3VA2", rating: "25-630A", poles: "3P/4P", curve: "ETU"),
      PanelComponent(id: "eaton-nzm", manufacturer: "Eaton", type: "MCCB", model: "NZM", rating: "20-1600A", poles: "3P/4P", curve: "Electronic/TM"),
      PanelComponent(id: "eaton-bzmx", manufacturer: "Eaton", type: "MCCB", model: "BZMX", rating: "15-250A", poles: "3P/4P", curve: "Thermal Magnetic")
    ]),
    ComponentGroup(id: "contactors", name: "Contactors", items: [
      PanelComponent(id: "abb-af16-30-10", manufacturer: "ABB", type: "Contactor", model: "AF16-30-10", rating: "16A", poles: "3P", curve: "1NO Aux"),
      PanelComponent(id: "abb-af26-30-00", manufacturer: "ABB", type: "Contactor", model: "AF26-30-00", rating: "26A", poles: "3P", curve: "No Aux"),
      PanelComponent(id: "abb-af38-30-00", manufacturer: "ABB", type: "Contactor", model: "AF38-30-00", rating: "38A", poles: "3P", curve: "No Aux"),
      PanelComponent(id: "schneider-lc1d", manufacturer: "Schneider", type: "Contactor", model: "TeSys D", rating: "9-150A", poles: "3P", curve: "AC-3"),
      PanelComponent(id: "siemens-3rt", manufacturer: "Siemens", type: "Contactor", model: "SIRIUS 3RT", rating: "9-250A", poles: "3P", curve: "AC-3"),
      PanelComponent(id: "eaton-dilm", manufacturer: "Eaton", type: "Contactor", model: "DILM", rating: "7-170A", poles: "3P", curve: "AC-3")
    ]),
    ComponentGroup(id: "drives-power", name: "Drives & Power", items: [
      PanelComponent(id: "abb-acs580", manufacturer: "ABB", type: "VFD", model: "ACS580", rating: "0.75-250kW", poles: "3PH", curve: "400V"),
      PanelComponent(id: "schneider-atv320", manufacturer: "Schneider", type: "VFD", model: "Altivar ATV320", rating: "0.18-15kW", poles: "3PH", curve: "400V"),
      PanelComponent(id: "siemens-g120", manufacturer: "Siemens", type: "VFD", model: "SINAMICS G120", rating: "0.55-250kW", poles: "3PH", curve: "400V"),
      PanelComponent(id: "meanwell-psu", manufacturer: "Mean Well", type: "PSU", model: "HDR DIN rail", rating: "24VDC", poles: "1PH", curve: "60-150W"),
      PanelComponent(id: "siemens-sitop", manufacturer: "Siemens", type: "PSU", model: "SITOP PSU", rating: "24VDC", poles: "1PH", curve: "5-20A")
    ]),
    ComponentGroup(id: "general-equipment", name: "General Equipment", items: [
      PanelComponent(id: "generic-acb", manufacturer: "Generic", type: "ACB", model: "Air Circuit Breaker", rating: "Set A", poles: "3P/4P", curve: "Withdrawable/fixed"),
      PanelComponent(id: "generic-rccb", manufacturer: "Generic", type: "RCD/RCCB", model: "Residual Current Device", rating: "Set A", poles: "2P/4P", curve: "30-300mA"),
      PanelComponent(id: "generic-overload", manufacturer: "Generic", type: "Overload Relay", model: "Thermal overload relay", rating: "Set A", poles: "3P", curve: "Motor protection"),
      PanelComponent(id: "generic-soft-starter", manufacturer: "Generic", type: "Soft Starter", model: "Motor soft starter", rating: "Set kW", poles: "3PH", curve: "Ramp start/stop"),
      PanelComponent(id: "generic-transformer", manufacturer: "Generic", type: "Transformer", model: "Control transformer", rating: "Set VA", poles: "1PH", curve: "400/230V"),
      PanelComponent(id: "generic-spd", manufacturer: "Generic", type: "SPD", model: "Surge Protection Device", rating: "Type 2", poles: "3P+N", curve: "40kA"),
      PanelComponent(id: "generic-fuse", manufacturer: "Generic", type: "Fuse", model: "NH fuse link", rating: "Set A", poles: "1P", curve: "gG/gL"),
      PanelComponent(id: "generic-fuse-holder", manufacturer: "Generic", type: "Fuse Holder", model: "DIN fuse holder", rating: "Set A", poles: "1P/3P", curve: "10x38/NH"),
      PanelComponent(id: "generic-isolator", manufacturer: "Generic", type: "Isolator", model: "Load break switch", rating: "Set A", poles: "3P/4P", curve: "Door-coupled"),
      PanelComponent(id: "generic-changeover", manufacturer: "Generic", type: "Changeover Switch", model: "Manual changeover", rating: "Set A", poles: "4P", curve: "I-0-II"),
      PanelComponent(id: "generic-meter", manufacturer: "Generic", type: "Meter", model: "Digital meter", rating: "230/400V", poles: "3PH", curve: "Panel mount"),
      PanelComponent(id: "generic-power-analyzer", manufacturer: "Generic", type: "Power Analyzer", model: "Power quality analyzer", rating: "230/400V", poles: "3PH", curve: "Modbus"),
      PanelComponent(id: "generic-plc", manufacturer: "Generic", type: "PLC", model: "Compact PLC", rating: "24VDC", poles: "DIN", curve: "Digital I/O"),
      PanelComponent(id: "generic-relay", manufacturer: "Generic", type: "Relay", model: "Interface relay", rating: "24VDC", poles: "DIN", curve: "1CO/2CO"),
      PanelComponent(id: "generic-timer", manufacturer: "Generic", type: "Timer", model: "Time relay", rating: "24-230V", poles: "DIN", curve: "On/off delay"),
      PanelComponent(id: "generic-selector", manufacturer: "Generic", type: "Selector Switch", model: "Selector switch", rating: "22mm", poles: "2/3 position", curve: "Panel door"),
      PanelComponent(id: "generic-push-button", manufacturer: "Generic", type: "Push Button", model: "Push button", rating: "22mm", poles: "NO/NC", curve: "Panel door"),
      PanelComponent(id: "generic-indicator", manufacturer: "Generic", type: "Indicator Light", model: "Pilot light", rating: "24/230V", poles: "22mm", curve: "LED"),
      PanelComponent(id: "generic-fan", manufacturer: "Generic", type: "Fan", model: "Panel fan", rating: "230V", poles: "Filter fan", curve: "Airflow"),
      PanelComponent(id: "generic-thermostat", manufacturer: "Generic", type: "Thermostat", model: "Panel thermostat", rating: "230V", poles: "DIN", curve: "NO/NC"),
      PanelComponent(id: "generic-door-interlock", manufacturer: "Generic", type: "Door Interlock", model: "Door interlock", rating: "Set A", poles: "Handle", curve: "Mechanical"),
      PanelComponent(id: "generic-cable-gland", manufacturer: "Generic", type: "Cable Gland", model: "Cable gland", rating: "Set size", poles: "M thread", curve: "IP rated"),
      PanelComponent(id: "generic-trunking", manufacturer: "Generic", type: "Trunking", model: "Wiring duct", rating: "Set cm", poles: "PVC", curve: "Slotted"),
      PanelComponent(id: "generic-copper-bar", manufacturer: "Generic", type: "Copper Bar", model: "Copper bar", rating: "Set cm", poles: "Flat bar", curve: "Busbar"),
      PanelComponent(id: "generic-earth-bar", manufacturer: "Generic", type: "Earth Bar", model: "PE bar", rating: "Set length", poles: "PE", curve: "Copper/brass"),
      PanelComponent(id: "generic-neutral-bar", manufacturer: "Generic", type: "Neutral Bar", model: "N bar", rating: "Set length", poles: "N", curve: "Copper/brass")
    ]),
    ComponentGroup(id: "panel-hardware", name: "Panel Hardware", items: [
      PanelComponent(id: "generic-busbar-250", manufacturer: "Generic", type: "Busbar", model: "Copper busbar", rating: "250A", poles: "3P+N", curve: "cm/m sizing"),
      PanelComponent(id: "generic-busbar-630", manufacturer: "Generic", type: "Busbar", model: "Copper busbar", rating: "630A", poles: "3P+N", curve: "cm/m sizing"),
      PanelComponent(id: "phoenix-terminal", manufacturer: "Phoenix", type: "Terminal Block", model: "UK series", rating: "2.5-35mm²", poles: "DIN", curve: "cm rail"),
      PanelComponent(id: "generic-din", manufacturer: "Generic", type: "DIN Rail", model: "35mm rail", rating: "1m", poles: "DIN", curve: "Cut to cm")
    ])
  ]
}

struct PanelComponent: Identifiable {
  let id: String
  let manufacturer: String
  let type: String
  let model: String
  let rating: String
  let poles: String
  let curve: String
  var sourceID: String = ""

  var imageStorageID: String {
    sourceID.isEmpty ? id : sourceID
  }

  var imageLookupIDs: [String] {
    Array(NSOrderedSet(array: [id, imageStorageID])) as? [String] ?? [id, imageStorageID]
  }

  var displayName: String {
    [manufacturer, type, model]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " ")
  }

  var ratingLabel: String {
    let trimmed = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.localizedCaseInsensitiveContains("set a") { return "Set A" }
    return trimmed
  }

  var detailLine: String {
    [model, poles, curve]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " • ")
  }

  var searchText: String {
    "\(manufacturer) \(type) \(model) \(rating) \(poles) \(curve)"
  }
}

struct BoardDraft: Identifiable {
  let id: String
  var number: String
  var group: String
  var name: String
  var customer: String
  var company: String = ""
  var project: String
  var type: String
  var subtype: String = BoardSubtypeCatalog.defaultSubtype
  var manufacturer: String = "Generic"
  var ampere: String
  var cabinetCount: String
  var buildFormat: String = "Panels"
  var dateOut: Date = Date()
  var dueDate: Date? = nil
  var finishDate: Date? = nil
  var finishTimeHours: String = ""
  var mainBreakerType: String
  var mainBreakerModel: String = ""
  var mainBreakerAmpere: String
  var componentTypes: [String]
  var color: Color = Color(hex: 0x5E78FF)
  var coverImage: UIImage? = nil
  var photoImages: [UIImage] = []
  var schemeAttachments: [SchemeAttachment] = []
  var completedChecklistItems: Set<String> = []
  var personalChecklistItems: [PersonalChecklistItem] = []

  var searchText: String {
    "\(number) \(group) \(name) \(customer) \(company) \(project) \(type) \(subtype) \(manufacturer) \(ampere) \(cabinetCount) \(buildFormat) \(DateDisplay.short.string(from: dateOut)) \(dueDate.map { DateDisplay.due.string(from: $0) } ?? "") \(finishDate.map { DateDisplay.short.string(from: $0) } ?? "") \(mainBreakerType) \(mainBreakerModel) \(mainBreakerAmpere) \(componentTypes.joined(separator: " "))"
  }

  var displayType: String {
    let cleanSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    guard BoardSubtypeCatalog.isVisible(cleanSubtype) else { return type }
    return "\(type) • \(cleanSubtype)"
  }

  var persistenceSignature: String {
    let coverSignature = ImageArchive.signature(for: coverImage)
    let photoSignature = photoImages.map { ImageArchive.signature(for: $0) }.joined(separator: "|")
    let schemeSignature = schemeAttachments.map(\.persistenceSignature).joined(separator: "|")
    return [
      id, number, group, name, customer, project, type, subtype, manufacturer,
      company,
      ampere, cabinetCount, buildFormat, "\(dateOut.timeIntervalSince1970)",
      "\(dueDate?.timeIntervalSince1970 ?? 0)",
      "\(finishDate?.timeIntervalSince1970 ?? 0)", finishTimeHours,
      mainBreakerType, mainBreakerModel, mainBreakerAmpere,
      componentTypes.joined(separator: ","), "\(color.archiveHex)",
      coverSignature, photoSignature,
      schemeSignature,
      completedChecklistItems.sorted().joined(separator: ","),
      personalChecklistItems.map { "\($0.id):\($0.title):\($0.isDone)" }.joined(separator: ",")
    ].joined(separator: "||")
  }

  var mainBreakerLabel: String {
    [(mainBreakerType == "Main Breaker" ? nil : mainBreakerType), mainBreakerModel, mainBreakerAmpere]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " • ")
  }

  var completion: Int {
    let checklist = ChecklistTemplate.items(for: cabinetCount)
    let totalWeight = max(checklist.map(\.weight).reduce(0, +), 1)
    let completedWeight = checklist
      .filter { completedChecklistItems.contains($0.id) }
      .map(\.weight)
      .reduce(0, +)
    return Int((Double(completedWeight) / Double(totalWeight) * 100).rounded())
  }

  var isCompleted: Bool {
    completion >= 100
  }

  var statusTitle: String {
    isCompleted ? "Finished" : "In Progress"
  }
}

struct PersonalChecklistItem: Identifiable, Hashable {
  let id: String
  var title: String
  var isDone: Bool

  init(id: String = "personal-\(UUID().uuidString)", title: String, isDone: Bool = false) {
    self.id = id
    self.title = title
    self.isDone = isDone
  }
}

enum EquipmentCompany {
  static let all = ["ABB", "Schneider", "Siemens", "Eaton", "Legrand", "Hager", "Mean Well", "Phoenix", "Generic"]
}

enum BoardSubtypeCatalog {
  static let defaultSubtype = "No subtype"

  static func isVisible(_ subtype: String) -> Bool {
    let cleanSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
    return !cleanSubtype.isEmpty && cleanSubtype != defaultSubtype && cleanSubtype != "General"
  }

  static func options(for boardType: String) -> [String] {
    let lower = boardType.lowercased()
    var options = [defaultSubtype, "Control", "EV Charger", "Metering", "Automation", "Pump Control", "HVAC Control", "Generator Control", "Solar", "UPS", "Temporary Site"]
    if lower.contains("ev") || lower.contains("charging") {
      options = [defaultSubtype, "EV Charger", "Load Management", "Parking Level", "Fast Charger", "Metering"]
    } else if lower.contains("mcc") || lower.contains("motor") || lower.contains("pump") || lower.contains("hvac") {
      options = [defaultSubtype, "Control", "Pump Control", "HVAC Control", "VFD", "Soft Starter", "Automation"]
    } else if lower.contains("lighting") {
      options = [defaultSubtype, "Indoor Lighting", "Outdoor Lighting", "Emergency Lighting", "Timer Control", "Astronomical Clock"]
    } else if lower.contains("ats") || lower.contains("generator") {
      options = [defaultSubtype, "Generator Control", "ATS Control", "Synchronization", "Bypass"]
    }
    return Array(NSOrderedSet(array: options)) as? [String] ?? options
  }
}

enum EquipmentTypeCatalog {
  static let all = [
    "MCB", "MCCB", "ACB", "RCD/RCCB", "RCBO", "Contactor", "Overload Relay",
    "VFD", "Soft Starter", "PSU", "Transformer", "Busbar", "Terminal Block",
    "SPD", "Fuse", "Fuse Holder", "Isolator", "Changeover Switch", "Meter",
    "Power Analyzer", "PLC", "Relay", "Timer", "Selector Switch", "Push Button",
    "Indicator Light", "Fan", "Thermostat", "Door Interlock", "Cable Gland",
    "DIN Rail", "Trunking", "Copper Bar", "Earth Bar", "Neutral Bar"
  ]
}

enum AmpereRating {
  static let all = [
    "0.5A", "1A", "2A", "3A", "4A", "6A", "10A", "13A", "16A", "20A",
    "25A", "32A", "40A", "50A", "63A", "80A", "100A", "125A", "160A",
    "200A", "225A", "250A", "315A", "400A", "500A", "630A", "800A",
    "1000A", "1250A", "1600A", "2000A", "2500A", "3200A", "4000A",
    "5000A", "6300A"
  ]
}

enum PoleRating {
  static let all = ["1P", "1P+N", "2P", "3P", "3P+N", "4P", "3PH", "1PH", "DIN"]
}

struct PanelVaultSnapshot: Codable {
  let projects: [ProjectRecord]
  let boards: [BoardRecord]
  let customers: [CustomerRecord]
  let companies: [CompanyRecord]?
  let manufacturers: [ManufacturerRecord]?

  init(projects: [ProjectItem], boards: [BoardDraft], customers: [CustomerItem], companies: [ContractorCompany], manufacturers: [ManufacturerItem]) {
    self.projects = projects.map(ProjectRecord.init(project:))
    self.boards = boards.map(BoardRecord.init(board:))
    self.customers = customers.map(CustomerRecord.init(customer:))
    self.companies = companies.map(CompanyRecord.init(company:))
    self.manufacturers = manufacturers.map(ManufacturerRecord.init(manufacturer:))
  }

  func encoded() -> String {
    guard let data = try? JSONEncoder().encode(self) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func decode(_ rawValue: String) -> PanelVaultSnapshot? {
    guard let data = rawValue.data(using: .utf8), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(PanelVaultSnapshot.self, from: data)
  }
}

enum ImageArchive {
  private static let encodedImageCache = NSCache<UIImage, NSString>()

  static func encode(_ image: UIImage?) -> String? {
    guard let image else { return nil }
    if let cached = encodedImageCache.object(forKey: image) {
      return cached as String
    }
    let encoded: String?
    if image.hasTransparency, let data = image.pngData() {
      encoded = data.base64EncodedString()
    } else {
      encoded = image.jpegData(compressionQuality: 0.72)?.base64EncodedString()
    }
    if let encoded {
      encodedImageCache.setObject(encoded as NSString, forKey: image)
    }
    return encoded
  }

  static func encode(_ images: [UIImage]) -> [String] {
    images.compactMap { encode($0) }
  }

  static func decode(_ rawValue: String?) -> UIImage? {
    guard let rawValue, let data = Data(base64Encoded: rawValue) else { return nil }
    guard let image = UIImage(data: data) else { return nil }
    encodedImageCache.setObject(rawValue as NSString, forKey: image)
    return image
  }

  static func decode(_ rawValues: [String]?) -> [UIImage] {
    rawValues?.compactMap { decode($0) } ?? []
  }

  static func signature(for image: UIImage?) -> String {
    guard let image else { return "no-image" }
    return "\(Int(image.size.width))x\(Int(image.size.height)):\(image.scale):\(image.imageOrientation.rawValue):\(ObjectIdentifier(image).hashValue)"
  }

  static func warmCache(for image: UIImage) {
    _ = encode(image)
  }

  static func preparedForStorage(_ image: UIImage, maximumDimension: CGFloat = 2200) -> UIImage {
    let longestSide = max(image.size.width, image.size.height)
    guard longestSide > maximumDimension else { return image }

    let scale = maximumDimension / longestSide
    let targetSize = CGSize(
      width: max((image.size.width * scale).rounded(), 1),
      height: max((image.size.height * scale).rounded(), 1)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = !image.hasTransparency
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }
}

extension UIImage {
  var hasTransparency: Bool {
    guard let alphaInfo = cgImage?.alphaInfo else { return false }
    switch alphaInfo {
    case .first, .last, .premultipliedFirst, .premultipliedLast:
      return true
    default:
      return false
    }
  }
}

enum ComponentImageArchive {
  static func encode(_ images: [String: UIImage]) -> String {
    let encoded = images.compactMapValues { ImageArchive.encode($0) }
    guard let data = try? JSONEncoder().encode(encoded) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func decode(_ rawValue: String) -> [String: UIImage] {
    guard let data = rawValue.data(using: .utf8),
          let encoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return encoded.compactMapValues { ImageArchive.decode($0) }
  }
}

struct ProjectRecord: Codable {
  let id: String
  let name: String
  let customer: String
  let detail: String
  let status: String
  let colorHex: UInt32
  let coverImageData: String?
  let photoImageData: [String]?
  let dueDate: Date?
  let schemes: [SchemeRecord]

  init(project: ProjectItem) {
    id = project.id
    name = project.name
    customer = project.customer
    detail = project.detail
    status = project.status
    colorHex = project.color.archiveHex
    coverImageData = ImageArchive.encode(project.coverImage)
    photoImageData = ImageArchive.encode(project.photoImages)
    dueDate = project.dueDate
    schemes = project.schemeAttachments.map(SchemeRecord.init(attachment:))
  }

  var project: ProjectItem {
    ProjectItem(
      id: id,
      name: name,
      customer: customer,
      detail: detail,
      status: status,
      color: Color(hex: colorHex),
      coverImage: ImageArchive.decode(coverImageData),
      photoImages: ImageArchive.decode(photoImageData),
      dueDate: dueDate,
      schemeAttachments: schemes.map(\.attachment)
    )
  }
}

struct BoardRecord: Codable {
  let id: String
  let number: String
  let group: String
  let name: String
  let customer: String
  let company: String?
  let project: String
  let type: String
  let subtype: String?
  let manufacturer: String
  let ampere: String
  let cabinetCount: String
  let buildFormat: String
  let dateOut: Date
  let dueDate: Date?
  let finishDate: Date?
  let finishTimeHours: String?
  let mainBreakerType: String
  let mainBreakerModel: String
  let mainBreakerAmpere: String
  let componentTypes: [String]
  let colorHex: UInt32
  let coverImageData: String?
  let photoImageData: [String]?
  let schemes: [SchemeRecord]
  let completedChecklistItems: [String]
  let personalChecklistItems: [PersonalChecklistRecord]

  init(board: BoardDraft) {
    id = board.id
    number = board.number
    group = board.group
    name = board.name
    customer = board.customer
    company = board.company
    project = board.project
    type = board.type
    subtype = board.subtype
    manufacturer = board.manufacturer
    ampere = board.ampere
    cabinetCount = board.cabinetCount
    buildFormat = board.buildFormat
    dateOut = board.dateOut
    dueDate = board.dueDate
    finishDate = board.finishDate
    finishTimeHours = board.finishTimeHours
    mainBreakerType = board.mainBreakerType
    mainBreakerModel = board.mainBreakerModel
    mainBreakerAmpere = board.mainBreakerAmpere
    componentTypes = board.componentTypes
    colorHex = board.color.archiveHex
    coverImageData = ImageArchive.encode(board.coverImage)
    photoImageData = ImageArchive.encode(board.photoImages)
    schemes = board.schemeAttachments.map(SchemeRecord.init(attachment:))
    completedChecklistItems = Array(board.completedChecklistItems)
    personalChecklistItems = board.personalChecklistItems.map(PersonalChecklistRecord.init(item:))
  }

  var board: BoardDraft {
    BoardDraft(
      id: id,
      number: number,
      group: group,
      name: name,
      customer: customer,
      company: company ?? "",
      project: project,
      type: type,
      subtype: subtype ?? BoardSubtypeCatalog.defaultSubtype,
      manufacturer: manufacturer,
      ampere: ampere,
      cabinetCount: cabinetCount,
      buildFormat: buildFormat,
      dateOut: dateOut,
      dueDate: dueDate,
      finishDate: finishDate,
      finishTimeHours: finishTimeHours ?? "",
      mainBreakerType: mainBreakerType,
      mainBreakerModel: mainBreakerModel,
      mainBreakerAmpere: mainBreakerAmpere,
      componentTypes: componentTypes,
      color: Color(hex: colorHex),
      coverImage: ImageArchive.decode(coverImageData),
      photoImages: ImageArchive.decode(photoImageData),
      schemeAttachments: schemes.map(\.attachment),
      completedChecklistItems: Set(completedChecklistItems),
      personalChecklistItems: personalChecklistItems.map(\.item)
    )
  }
}

struct CustomerRecord: Codable {
  let id: String
  let name: String
  let kind: String?
  let contactName: String?
  let phone: String
  let note: String

  init(customer: CustomerItem) {
    id = customer.id
    name = customer.name
    kind = customer.kind
    contactName = customer.contactName
    phone = customer.phone
    note = customer.note
  }

  var customer: CustomerItem {
    CustomerItem(id: id, name: name, kind: kind ?? "Company", contactName: contactName ?? "", phone: phone, note: note)
  }
}

struct CompanyRecord: Codable {
  let id: String
  let name: String
  let role: String
  let projectCount: String
  let colorHex: UInt32

  init(company: ContractorCompany) {
    id = company.id
    name = company.name
    role = company.role
    projectCount = company.projectCount
    colorHex = company.color.archiveHex
  }

  var company: ContractorCompany {
    ContractorCompany(id: id, name: name, role: role, projectCount: projectCount, color: Color(hex: colorHex))
  }
}

struct ManufacturerRecord: Codable {
  let id: String
  let name: String
  let colorHex: UInt32
  let imageData: String?

  init(manufacturer: ManufacturerItem) {
    id = manufacturer.id
    name = manufacturer.name
    colorHex = manufacturer.colorHex
    imageData = ImageArchive.encode(manufacturer.image)
  }

  var manufacturer: ManufacturerItem {
    ManufacturerItem(id: id, name: name, colorHex: colorHex, image: ImageArchive.decode(imageData))
  }
}

struct SchemeRecord: Codable {
  let id: String
  let kind: String
  let name: String
  let url: String?
  let imageData: String?

  init(attachment: SchemeAttachment) {
    id = attachment.id
    kind = attachment.kind == .pdf ? "pdf" : "photo"
    name = attachment.name
    url = attachment.url?.absoluteString
    imageData = ImageArchive.encode(attachment.image)
  }

  var attachment: SchemeAttachment {
    SchemeAttachment(
      id: id,
      kind: kind == "pdf" ? .pdf : .photo,
      name: name,
      image: ImageArchive.decode(imageData),
      url: url.flatMap(URL.init(string:))
    )
  }
}

struct PersonalChecklistRecord: Codable {
  let id: String
  let title: String
  let isDone: Bool

  init(item: PersonalChecklistItem) {
    id = item.id
    title = item.title
    isDone = item.isDone
  }

  var item: PersonalChecklistItem {
    PersonalChecklistItem(id: id, title: title, isDone: isDone)
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
