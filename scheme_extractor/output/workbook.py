"""The xlsx a reviewer opens.

Values only, never formulas. Stage 6 already did the arithmetic in code and
checked that every BOM line's per-sheet breakdown sums to its quantity; a
spreadsheet formula would only re-do that work in a place where it can break.
It also sidesteps openpyxl's `data_only` trap entirely — there is nothing to
destroy on a round trip, because there are no formulas to lose.

Every sheet is right-to-left: the source drawings are Hebrew and the
destination column is the one a reviewer reads first.
"""

from __future__ import annotations

from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from ..models.schema import ExtractionRun

HEADER = Font(bold=True, color="FFFFFF")
HEADER_FILL = PatternFill("solid", fgColor="2F4858")
FLAGGED = PatternFill("solid", fgColor="FDE2E2")


def _sheet(book: Workbook, title: str, headers: list[str]):
    worksheet = book.create_sheet(title)
    # RTL, because the drawings are.
    worksheet.sheet_view.rightToLeft = True
    worksheet.append(headers)
    for column, _ in enumerate(headers, start=1):
        cell = worksheet.cell(row=1, column=column)
        cell.font = HEADER
        cell.fill = HEADER_FILL
        cell.alignment = Alignment(vertical="center")
    worksheet.freeze_panes = "A2"
    return worksheet


def _autosize(worksheet) -> None:
    for column in worksheet.columns:
        width = max((len(str(cell.value or "")) for cell in column), default=8)
        worksheet.column_dimensions[get_column_letter(column[0].column)].width = min(60, max(10, width + 2))


def write(run: ExtractionRun, path: Path) -> Path:
    book = Workbook()
    book.remove(book.active)

    bom = _sheet(book, "BOM", [
        "Class", "Manufacturer", "Model", "Rating", "Poles", "Curve", "Qty",
        "Per-sheet breakdown", "Tags", "Flags", "Needs human",
    ])
    for line in run.bom:
        bom.append([
            line.device_class, line.manufacturer or "", line.model or "", line.rating or "",
            line.poles or "", line.curve or "", line.qty,
            ", ".join(f"{sheet}:{qty}" for sheet, qty in sorted(line.breakdown.items())),
            ", ".join(line.tags), ", ".join(line.flags), "yes" if line.needs_human else "",
        ])
        if line.needs_human:
            for column in range(1, 12):
                bom.cell(row=bom.max_row, column=column).fill = FLAGGED
    _autosize(bom)

    circuits = _sheet(book, "Circuits", [
        "Sheet", "Terminal", "Protective device", "Destination (יעד)", "Span",
        "Confidence", "Cable", "Inc", "Spare", "Flags", "Needs human",
    ])
    for row in run.circuits:
        circuits.append([
            row.sheet_label or "", row.terminal, row.protective_device or "",
            row.destination_he or "", ", ".join(row.span_terminals), row.span_confidence,
            row.cable or "", row.inc or "", "yes" if row.is_spare else "",
            ", ".join(row.flags), "yes" if row.needs_human else "",
        ])
        if row.needs_human:
            for column in range(1, 12):
                circuits.cell(row=circuits.max_row, column=column).fill = FLAGGED
    _autosize(circuits)

    devices = _sheet(book, "Devices", [
        "Sheet", "Tag", "Qty", "Class", "Manufacturer", "Model", "Rating",
        "Setting", "Curve", "Poles", "Fed from", "Feeds", "Description (תיאור)", "Flags",
    ])
    for sheet in run.sheets:
        for device in sheet.devices:
            devices.append([
                sheet.sheet.sheet_label, device.tag, device.qty, device.device_class,
                device.manufacturer or "", device.model or "", device.rating or "",
                device.setting or "", device.curve or "", device.poles or "",
                device.fed_from or "", device.feeds or "", device.description_he or "",
                ", ".join(device.flags),
            ])
    _autosize(devices)

    io = _sheet(book, "PLC IO", ["Sheet", "Module", "Connector", "Point", "Type", "Description", "Wire"])
    for sheet in run.sheets:
        for point in sheet.io_points:
            io.append([
                sheet.sheet.sheet_label, point.module or "", point.connector or "",
                point.point or "", point.type or "", point.description_he or "", point.wire_colour or "",
            ])
    _autosize(io)

    findings = _sheet(book, "Findings", ["Severity", "Type", "Item", "Sheets", "Detail"])
    order = {"blocking": 0, "review": 1, "note": 2}
    for finding in sorted(run.audit.findings, key=lambda f: order.get(f.severity, 3)):
        findings.append([
            finding.severity, finding.type, finding.item,
            ", ".join(finding.sheets), finding.detail_he or "",
        ])
    _autosize(findings)

    summary = _sheet(book, "Summary", ["Field", "Value"])
    summary.append(["Job", run.job_id])
    summary.append(["Source hash", run.source_hash])
    summary.append(["Sheets", len(run.sheets)])
    summary.append(["Device units", sum(line.qty for line in run.bom)])
    summary.append(["Outgoing circuits", run.counts.total])
    summary.append(["Spare (שמור printed)", run.counts.spare])
    summary.append(["Unlabelled circuits", run.counts.unlabelled])
    summary.append(["Cost (USD)", run.cost.get("total_usd", "")])
    for fact in run.audit.panel:
        summary.append([fact.field, fact.value or ""])
    for warning in run.warnings:
        summary.append(["Warning", warning])
    for note in run.notes:
        summary.append(["Note", note])
    _autosize(summary)

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    book.save(path)
    return path
