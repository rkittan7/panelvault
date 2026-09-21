"""The data contracts, field for field from `panelvault_scheme_extraction.md`.

Field names are the API contract for the model calls and are not renamed.
Two of the validators below are deliberately hard errors rather than
warnings, because they catch the two failure modes that are otherwise
silent: a quantity that does not match the tags it claims to count, and a
cell called spare when nothing said שמור.
"""

from __future__ import annotations

from typing import Annotated, Any, Literal, Optional

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, WithJsonSchema, model_validator
from pydantic_core import PydanticUndefined

# The only two words that make a circuit spare. An empty cell is empty (§2.4).
SPARE_WORDS = ("שמור", "שמורים")

DeviceClass = Literal[
    "mccb", "mcb", "rcd", "contactor", "motor_protection", "switch", "fuse",
    "spd", "lamp", "relay", "step_relay", "shunt_trip", "plc", "plc_module",
    "psu", "terminal", "alarm_interface", "enclosure", "label", "external",
]
Confidence = Literal["high", "medium", "low"]
FindingType = Literal[
    "duplicate_tag", "contradiction", "suspected_typo", "model_mismatch",
    "bom_list_gap", "missing_data", "attention",
]
Severity = Literal["blocking", "review", "note"]


class Contract(BaseModel):
    """Reject anything the schema did not ask for, on the way in."""

    model_config = ConfigDict(extra="forbid")


def ServerField(default: Any = PydanticUndefined, **kwargs: Any) -> Any:
    """A field the pipeline fills in, which the model must never be asked for.

    Flags, human-review marks and sheet labels are stage 5's business. Putting
    them in the tool schema would invite the model to populate them, and a
    model-authored `needs_human: false` is worth nothing.
    """
    if default is PydanticUndefined:
        return Field(json_schema_extra={"server_side": True}, **kwargs)
    return Field(default, json_schema_extra={"server_side": True}, **kwargs)


# ------------------------------------------------------------ stage 3 output

class TitleBlock(Contract):
    project: Optional[str] = None
    panel: Optional[str] = None
    panel_builder: Optional[str] = None
    client: Optional[str] = None
    consultant: Optional[str] = None
    drawing_no: Optional[str] = None
    drawn_by: Optional[str] = None
    revision_dates: list[str] = Field(default_factory=list)
    status: Optional[str] = None
    total_pages: Optional[str] = None


class Sheet(Contract):
    page_number: int
    sheet_label: str
    title_block: TitleBlock = Field(default_factory=TitleBlock)


class Busbar(Contract):
    name: str
    spec: Optional[str] = None
    role_he: Optional[str] = None


class AuxContact(Contract):
    to_point: Optional[str] = None
    module: Optional[str] = None
    purpose_he: Optional[str] = None


class Device(Contract):
    tag: str
    tags_expanded: list[str] = Field(default_factory=list)
    qty: int = 0
    device_class: DeviceClass
    description_he: Optional[str] = None
    manufacturer: Optional[str] = None
    model: Optional[str] = None
    rating: Optional[str] = None
    # A breaker may carry both a frame rating and a calibrated setting
    # (`3X40A Inc=32A`). `Inc` is that same device's setting, never a second
    # device — keeping them in separate fields is what stops it becoming one.
    setting: Optional[str] = None
    curve: Optional[str] = None
    poles: Optional[str] = None
    fed_from: Optional[str] = None
    feeds: Optional[str] = None
    aux_contacts: list[AuxContact] = Field(default_factory=list)
    notes_he: Optional[str] = None

    # Filled by stage 5, never by the model.
    flags: list[str] = ServerField(default_factory=list)
    needs_human: bool = ServerField(False)
    sheet_label: Optional[str] = ServerField(None)

    @model_validator(mode="after")
    def qty_matches_expansion(self) -> "Device":
        if self.tags_expanded and self.qty != len(self.tags_expanded):
            raise ValueError(
                f"{self.tag}: qty is {self.qty} but tags_expanded lists "
                f"{len(self.tags_expanded)} tags ({', '.join(self.tags_expanded[:6])}…). "
                "A range must expand to exactly the devices it counts."
            )
        return self


class CircuitRow(Contract):
    terminal: str
    protective_device: Optional[str] = None
    destination_he: Optional[str] = None
    span_terminals: list[str] = Field(default_factory=list)
    span_confidence: Confidence = "low"
    cable: Optional[str] = None
    inc: Optional[str] = None
    is_spare: bool = False
    needs_zoom: bool = False

    flags: list[str] = ServerField(default_factory=list)
    needs_human: bool = ServerField(False)
    sheet_label: Optional[str] = ServerField(None)

    @model_validator(mode="after")
    def spare_needs_the_word(self) -> "CircuitRow":
        if self.is_spare:
            text = self.destination_he or ""
            if not any(word in text for word in SPARE_WORDS):
                raise ValueError(
                    f"{self.terminal}: is_spare is true but destination_he is "
                    f"{text!r}. A circuit is spare only where שמור or שמורים is printed."
                )
        return self


class IOPoint(Contract):
    module: Optional[str] = None
    connector: Optional[str] = None
    point: Optional[str] = None
    type: Optional[str] = None
    description_he: Optional[str] = None
    wire_colour: Optional[str] = None
    sheet_label: Optional[str] = ServerField(None)


class CrossReference(Contract):
    tag: str
    role_he: Optional[str] = None
    note: Optional[str] = None


class Gap(Contract):
    terminal: Optional[str] = None
    missing: Optional[str] = None
    note: Optional[str] = None


class Anomaly(Contract):
    item: str
    type: Optional[str] = None
    detail: Optional[str] = None


class ZoomRegion(Contract):
    reason: str
    bbox_pct: list[float] = Field(
        min_length=4, max_length=4,
        description="Exactly four fractions of the page: x0, y0, x1, y1.",
    )
    terminals: list[str] = Field(default_factory=list)


class SheetExtraction(Contract):
    sheet: Sheet
    busbars: list[Busbar] = Field(default_factory=list)
    devices: list[Device] = Field(default_factory=list)
    circuit_table: list[CircuitRow] = Field(default_factory=list)
    io_points: list[IOPoint] = Field(default_factory=list)
    cross_references: list[CrossReference] = Field(default_factory=list)
    gaps: list[Gap] = Field(default_factory=list)
    anomalies: list[Anomaly] = Field(default_factory=list)
    needs_zoom_regions: list[ZoomRegion] = Field(default_factory=list)

    # Pipeline bookkeeping, not model output.
    layout_kind: str = ServerField("table")
    zoom_passes: int = ServerField(0)
    notes: list[str] = ServerField(default_factory=list)


# ------------------------------------------------------------ stage 4 output

class ZoomCell(Contract):
    span_terminals: list[str] = Field(default_factory=list)
    destination_he: Optional[str] = None
    confidence: Confidence = "low"


def _pairs_to_map(value: Any) -> Any:
    """`[{"terminal": "X11", "value": "12.8A"}]` → `{"X11": "12.8A"}`."""
    if isinstance(value, list):
        return {
            str(item.get("terminal")): str(item.get("value"))
            for item in value
            if isinstance(item, dict) and item.get("terminal") and item.get("value") is not None
        }
    return value


# Strict tool use cannot express an open-keyed map (`additionalProperties`
# must be false), so the model returns terminal/value pairs and they are
# folded back into a map here. Everything downstream still sees a dict.
TerminalMap = Annotated[
    dict[str, str],
    BeforeValidator(_pairs_to_map),
    WithJsonSchema({
        "type": "array",
        "items": {
            "type": "object",
            "properties": {"terminal": {"type": "string"}, "value": {"type": "string"}},
            "required": ["terminal", "value"],
            "additionalProperties": False,
        },
    }),
]


class ZoomResult(Contract):
    terminals: list[str] = Field(default_factory=list)
    cells: list[ZoomCell] = Field(default_factory=list)
    cable_row: TerminalMap = Field(default_factory=dict)
    inc_row: TerminalMap = Field(default_factory=dict)
    unresolved: list[str] = Field(default_factory=list)


# ------------------------------------------------------------ stage 7 output

class Finding(Contract):
    type: FindingType
    item: str
    sheets: list[str] = Field(default_factory=list)
    detail_he: Optional[str] = None
    severity: Severity = "review"


class PanelFact(Contract):
    field: str
    value: Optional[str] = None
    sheets: list[str] = Field(default_factory=list)


class AuditResult(Contract):
    findings: list[Finding] = Field(default_factory=list)
    panel: list[PanelFact] = Field(default_factory=list)


# -------------------------------------------------------------- stage 6 + run

class BOMLine(Contract):
    device_class: DeviceClass
    manufacturer: Optional[str] = None
    model: Optional[str] = None
    rating: Optional[str] = None
    poles: Optional[str] = None
    # Not part of the grouping key, but stock-defining downstream: a red lamp
    # and a green lamp are different parts, and so are a C-curve and a B-curve
    # breaker. Carried only when every device in the group agrees; left empty
    # when they do not, so a disagreement never masquerades as a fact.
    curve: Optional[str] = None
    sensitivity: Optional[str] = None
    qty: int
    tags: list[str] = Field(default_factory=list)
    # Every line carries this, not only the ones over twenty units, so a
    # reviewer can verify any total by hand (§11.6).
    breakdown: dict[str, int] = Field(default_factory=dict)
    flags: list[str] = Field(default_factory=list)
    needs_human: bool = False


class CircuitCounts(Contract):
    total: int = 0
    spare: int = 0
    unlabelled: int = 0


class ExtractionRun(Contract):
    job_id: str
    source_hash: str
    sheets: list[SheetExtraction] = Field(default_factory=list)
    bom: list[BOMLine] = Field(default_factory=list)
    circuits: list[CircuitRow] = Field(default_factory=list)
    counts: CircuitCounts = Field(default_factory=CircuitCounts)
    audit: AuditResult = Field(default_factory=AuditResult)
    cost: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)


# ------------------------------------------------------- JSON Schema for tools

UNSUPPORTED_CONSTRAINTS = (
    "maxItems", "minLength", "maxLength", "minimum", "maximum",
    "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "uniqueItems",
)


def tool_schema(model: type[BaseModel]) -> dict[str, Any]:
    """A JSON Schema the strict tool-use parameter will accept.

    Pydantic emits `$ref`/`$defs` and marks only non-defaulted fields as
    required. Strict mode wants every property required, no additional
    properties, and — since a `$ref` graph is easy to get wrong — no
    indirection. So the refs are inlined and the constraints tightened here.
    """
    raw = model.model_json_schema()
    defs = raw.pop("$defs", {})

    def inline(node: Any) -> Any:
        if isinstance(node, dict):
            if "$ref" in node:
                name = node["$ref"].rsplit("/", 1)[-1]
                merged = inline(defs[name])
                # Keep any sibling keywords (description, default) next to it.
                extra = {k: v for k, v in node.items() if k != "$ref"}
                return {**merged, **extra}
            return {key: inline(value) for key, value in node.items()}
        if isinstance(node, list):
            return [inline(item) for item in node]
        return node

    schema = inline(raw)

    def tighten(node: Any) -> Any:
        if isinstance(node, dict):
            properties = node.get("properties")
            if isinstance(properties, dict):
                node = dict(node)
                node["properties"] = {
                    name: value
                    for name, value in properties.items()
                    if not (isinstance(value, dict) and value.get("server_side"))
                }
            node = {key: tighten(value) for key, value in node.items()}
            node.pop("server_side", None)
            if node.get("type") == "object" and "properties" in node:
                node["additionalProperties"] = False
                node["required"] = list(node["properties"].keys())
            # `default` is advisory and strict mode does not honour it; the
            # model must emit every field explicitly.
            node.pop("default", None)
            # Strict mode rejects length and range constraints (minItems
            # beyond 0 or 1 included). Pydantic still enforces them when the
            # answer is validated, and a violation earns the correction turn.
            for keyword in UNSUPPORTED_CONSTRAINTS:
                node.pop(keyword, None)
            if node.get("minItems", 0) > 1:
                node.pop("minItems")
            return node
        if isinstance(node, list):
            return [tighten(item) for item in node]
        return node

    return tighten(schema)
