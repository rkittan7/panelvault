// Copied from the PanelVault app (ios/Runner/SceneDelegate.swift) by
// tools/split_worker.py. The worker app is a deliberate copy of PanelVault's
// design system and data model, with manager-only creation removed and the
// warehouse added. Edit here; do not re-run the splitter over hand edits.

import SwiftUI

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

func dueDateComesFirst(_ left: Date?, _ right: Date?) -> Bool? {
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

func activeBoardPrioritySort(_ left: BoardDraft, _ right: BoardDraft) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  if left.completion != right.completion { return left.completion > right.completion }
  return left.name < right.name
}

func boardPrioritySort(_ left: BoardDraft, _ right: BoardDraft) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  if left.isCompleted != right.isCompleted { return !left.isCompleted && right.isCompleted }
  if left.completion != right.completion { return left.completion > right.completion }
  return left.name < right.name
}

func projectPrioritySort(_ left: ProjectItem, _ right: ProjectItem) -> Bool {
  if let dueSort = dueDateComesFirst(left.dueDate, right.dueDate) { return dueSort }
  return left.name < right.name
}

func syncedManufacturer(named name: String, in manufacturers: [ManufacturerItem]) -> ManufacturerItem? {
  manufacturers.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ??
    ManufacturerItem.defaults.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
}

func dueUrgencyColor(for date: Date) -> Color {
  let hours = date.timeIntervalSince(Date()) / 3600
  if hours <= 0 { return Color(hex: 0xFF453A) }
  let days = min(max(hours / 24, 0), 14)
  let urgency = 1 - (days / 14)
  let red = 0.20 + (urgency * 0.80)
  let green = 0.86 - (urgency * 0.58)
  let blue = 0.34 - (urgency * 0.18)
  return Color(red: red, green: green, blue: blue)
}
