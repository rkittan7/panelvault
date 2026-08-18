// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

struct DashboardView: View {
  let theme: PanelTheme
  let interfaceSize: InterfaceSize
  let contractorMode: Bool
  @Binding var selectedTab: WorkerTab
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
  @Binding var profileName: String
  @Binding var profileCompany: String
  @Binding var profilePhone: String
  @Binding var profileImageToken: String
  @Binding var activeCompany: ContractorCompany?
  @Binding var companies: [ContractorCompany]
  @Binding var recentVisits: [RecentVisit]
  @State private var profileOpen = false
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
          sectionHeader("Boards", symbol: "rectangle.3.group.fill", count: activeBoardDashboardCount, accent: theme.secondary) {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .boards
            selectedTab = .projects
          }
          activeBoardsList
          sectionHeader("Projects", symbol: "folder.fill", count: activeProjectDashboardCount) {
            archiveQuery = ""
            archiveBoardTypeFilter = "All"
            archiveStatusFilter = "In Progress"
            archiveMode = .projects
            selectedTab = .projects
          }
          activeProjectsList
          sectionHeader("Board Types", symbol: "square.grid.2x2.fill") {
            dashboardSheet = .boardTypes
          }
          boardTypesGrid
          quickSearch
          sectionHeader("Recents", symbol: "clock.arrow.circlepath") {
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
      .sheet(item: $dashboardSheet) { sheet in
        switch sheet {
        case .boardTypes:
          BoardTypesSheet(theme: theme, boardTypes: boardTypes)
        case .recentProjects:
          ProjectsListSheet(theme: theme, projects: $projects, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers)
        case .stats:
          DashboardStatsSheet(theme: theme, projects: projects, boardCount: boardCount)
        case .customers:
          SimpleListSheet(
            theme: theme,
            title: "Customers",
            rows: uniqueCustomers.map { SimpleListRow(symbol: "person.crop.circle", title: $0, subtitle: "", color: theme.primary) }
          )
        }
      }
    }
    .sheet(item: $selectedProject) { project in
      // onUpdateProject stays wired — it is how project photos and schemes get
      // written back. There is no onDeleteProject: a worker does not delete a
      // project from their dashboard.
      ProjectDetailSheet(theme: theme, project: project, boards: $boards, boardTypes: boardTypes, manufacturers: manufacturers) { board in
        remember(.board, id: board.id)
      } onUpdateProject: { updatedProject, previousName in
        if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
          projects[index] = updatedProject
        }
        for index in boards.indices where boards[index].project == previousName {
          boards[index].project = updatedProject.name
        }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: selectedBoardBinding) { boardID in
      if let index = boards.firstIndex(where: { $0.id == boardID.id }) {
        NavigationStack {
          BoardScreen(theme: theme, board: $boards[index], boardTypes: boardTypes, manufacturers: manufacturers) {
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

  private var selectedBoardBinding: Binding<RecentBoardSelection?> {
    Binding {
      selectedBoardID.map(RecentBoardSelection.init(id:))
    } set: { selection in
      selectedBoardID = selection?.id
    }
  }

  var header: some View {
    HStack(spacing: 14) {
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

      Button {
        profileOpen = true
      } label: {
        ProfileAvatarView(theme: theme, name: profileName, imageToken: profileImageToken, size: 48)
      }
      .buttonStyle(PanelPressButtonStyle())
      .accessibilityLabel("Profile")
    }
    .sheet(isPresented: $profileOpen) {
      ProfileEditorSheet(
        theme: theme,
        name: $profileName,
        company: $profileCompany,
        phone: $profilePhone,
        imageToken: $profileImageToken
      )
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
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.primary)
            .frame(width: 30, height: 30)
            .background(theme.primary.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

  func sectionHeader(_ title: String, symbol: String, count: Int? = nil, accent: Color? = nil, action: @escaping () -> Void) -> some View {
    let tint = accent ?? theme.primary
    return HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      Text(title)
        .font(.system(size: 22, weight: .heavy))
      if let count {
        Text(count > 3 ? "3+" : "\(count)")
          .font(.system(size: 12, weight: .heavy))
          .foregroundStyle(tint)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(tint.opacity(0.14))
          .clipShape(Capsule())
          .overlay(
            Capsule()
              .stroke(tint.opacity(0.18), lineWidth: 1)
          )
      }
      Spacer()
      Button(action: action) {
        Image(systemName: "arrow.right")
          .font(.system(size: 14, weight: .heavy))
          .foregroundStyle(tint)
          .frame(width: 34, height: 28)
          .background(tint.opacity(0.13))
          .clipShape(Capsule())
          .overlay(
            Capsule()
              .stroke(tint.opacity(0.18), lineWidth: 1)
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
  case customers

  var id: String { rawValue }
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

struct ProjectDashboardRow: View {
  let theme: PanelTheme
  let project: ProjectItem
  var boardCount: Int? = nil
  var displayedStatus: String? = nil
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
          if let image = project.coverThumbnail {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 48, height: 48)
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
          if let image = project.coverThumbnail {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 48, height: 48)
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
            RecentKindBadge(title: "Project", color: theme.primary)
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

  var body: some View {
    GlassCard(theme: theme) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 12) {
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)

          VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Text(board.name)
              .font(.system(size: 17, weight: .heavy))
              .lineLimit(1)
              .minimumScaleFactor(0.65)
            if let dueDate = board.dueDate {
              DueDateBadge(date: dueDate, compact: true)
            }
            Spacer(minLength: 5)
            Text("\(board.completion)%")
              .font(.system(size: 17, weight: .black))
              .foregroundStyle(progressColor)
              .monospacedDigit()
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 5) {
            RecentBoardInfoChip(symbol: "number", text: board.number, color: board.color)
            RecentBoardInfoChip(symbol: "bolt.fill", text: board.ampere, color: theme.secondary)
            RecentManufacturerChip(manufacturer: manufacturer, fallbackName: board.manufacturer)
          }
          .fixedSize(horizontal: false, vertical: true)
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
        }
      }
      .frame(minHeight: 82)
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
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 7) {
          RecentKindBadge(title: "Board", color: theme.secondary)
          RecentStatusBadge(status: board.statusTitle)
          Spacer(minLength: 10)
        }

        HStack(spacing: 12) {
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
              Text(board.name)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
              Spacer(minLength: 5)
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
              RecentBoardInfoChip(symbol: "number", text: board.number, color: board.color)
              RecentBoardInfoChip(symbol: "bolt.fill", text: board.ampere, color: theme.secondary)
              RecentManufacturerChip(manufacturer: manufacturer, fallbackName: board.manufacturer)
            }
            .fixedSize(horizontal: false, vertical: true)
          }
        }
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
        }
      }
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
          BoardCardThumbnail(theme: theme, boardType: boardType, color: board.color, image: board.coverThumbnail, completed: board.isCompleted)

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
          .frame(width: 48, height: 48)
          .clipped()
      } else {
        BoardTypeIcon(board: boardType, size: 28, overrideColor: color)
      }
    }
      .frame(width: 48, height: 48)
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
