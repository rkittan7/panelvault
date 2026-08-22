// The finish record for a board, and the only board fields a worker edits
// through a sheet.
//
// The manager app opens BoardEditSheet from this same tap, which can rename the
// board, retype it, change its customer and delete it — none of which belongs to
// a worker. What does belong to them is closing a board out: PLAN.md puts
// "update assigned boards" in the worker role.
//
// Note that `isCompleted` is *derived* from the cabinet checklists (100% done),
// not from anything here. A worker completes a board by working through those
// checklists on the board screen. This sheet records the two facts the checklist
// cannot know: the date it actually left the bench, and the hours it took.

import SwiftUI

struct BoardProgressSheet: View {
  let theme: PanelTheme
  @Binding var board: BoardDraft
  @Environment(\.dismiss) private var dismiss

  @State private var isFinished: Bool
  @State private var finishDate: Date
  @State private var finishTimeHours: String

  init(theme: PanelTheme, board: Binding<BoardDraft>) {
    self.theme = theme
    self._board = board
    self._isFinished = State(initialValue: board.wrappedValue.finishDate != nil)
    self._finishDate = State(initialValue: board.wrappedValue.finishDate ?? Date())
    self._finishTimeHours = State(initialValue: board.wrappedValue.finishTimeHours)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          GlassCard(theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
              Text(board.name)
                .font(.system(size: 18, weight: .heavy))
              Text(board.number.isEmpty ? board.type : "\(board.number) • \(board.type)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Divider().opacity(0.4)
              HStack {
                Text("Checklist progress")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Spacer()
                Text("\(board.completion)%")
                  .font(.system(size: 15, weight: .heavy))
                  .foregroundStyle(theme.primary)
              }
              Text("A board counts as finished at 100%. Work the cabinet checklists on the board screen to move this.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }

          CreationFormSection(theme: theme, title: "Finish Record", symbol: "flag.checkered", subtitle: "Fill this in when the board leaves the bench") {
            CreationToggleInput(theme: theme, title: "Has a finish date", symbol: "checkmark.seal.fill", isOn: $isFinished)
            if isFinished {
              CreationDateInput(theme: theme, title: "Finished on", symbol: "calendar", selection: $finishDate, displayedComponents: .date)
            }
            CreationTextInput(theme: theme, title: "Hours worked", placeholder: "Hours", symbol: "timer", text: $finishTimeHours, keyboardType: .decimalPad)
          }

          Text("Board details — name, number, type, customer — are set in the PanelVault manager app.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

          BottomTabClearance(height: 40)
        }
        .padding(18)
      }
      .background(theme.background.ignoresSafeArea())
      .navigationTitle("Finish Record")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            save()
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
    }
  }

  private func save() {
    // Clearing the toggle has to clear the date, not just hide the picker,
    // or the board keeps reporting a finish date nobody can see.
    board.finishDate = isFinished ? finishDate : nil
    board.finishTimeHours = finishTimeHours.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
