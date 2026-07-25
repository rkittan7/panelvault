// Stock movement chart — grouped daily bars, no chart library.
//
// Form follows the data's job: movement is change-over-time on discrete days,
// so bars, not a line. Two series (in / out) means a legend is mandatory and
// identity is never carried by colour alone — the tooltip names each series.

const SVG_NS = "http://www.w3.org/2000/svg";

const svgEl = (tag, attrs = {}) => {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
  return node;
};

/** Rounds a raw axis step up to the nearest 1, 2 or 5 × a power of ten. */
function niceStep(raw) {
  const magnitude = 10 ** Math.floor(Math.log10(Math.max(raw, 1)));
  const normalised = raw / magnitude;
  const snapped = normalised <= 1 ? 1 : normalised <= 2 ? 2 : normalised <= 5 ? 5 : 10;
  return snapped * magnitude;
}

/** Buckets movements into the last `days` calendar days. */
function bucketMovements(movements, days) {
  const buckets = [];
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  for (let offset = days - 1; offset >= 0; offset--) {
    const date = new Date(today);
    date.setDate(date.getDate() - offset);
    buckets.push({ date, in: 0, out: 0 });
  }

  const firstDay = buckets[0].date.getTime();
  for (const movement of movements) {
    const when = new Date(movement.date);
    when.setHours(0, 0, 0, 0);
    const index = Math.round((when.getTime() - firstDay) / 86400000);
    if (index < 0 || index >= buckets.length) continue;
    // An adjustment counts on the side it actually moved stock.
    const delta = movement.kind === "consume" ? -movement.quantity : movement.quantity;
    if (delta >= 0) buckets[index].in += delta;
    else buckets[index].out += -delta;
  }
  return buckets;
}

/**
 * Renders the chart into `container` (a positioned element).
 * Returns nothing; re-call to redraw.
 */
export function renderMovementChart(container, movements, { days = 14 } = {}) {
  container.replaceChildren();

  const data = bucketMovements(movements, days);
  const rawPeak = Math.max(1, ...data.map((d) => Math.max(d.in, d.out)));

  const W = 620;
  const H = 148;
  const padL = 26;
  const padR = 6;
  const padT = 8;
  const padB = 18;
  const plotW = W - padL - padR;
  const plotH = H - padT - padB;

  const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img" });
  svg.setAttribute("aria-label", `Stock movements over the last ${days} days`);

  // --- recessive gridlines + y ticks on rounded steps, so the axis reads
  // 0 / 400 / 800 rather than 0 / 353 / 707
  const ticks = 3;
  const step = niceStep(rawPeak / ticks);
  const peak = step * ticks;

  for (let i = 0; i <= ticks; i++) {
    const value = step * i;
    const y = padT + plotH - (plotH * i) / ticks;
    svg.append(svgEl("line", {
      class: "grid-line", x1: padL, x2: W - padR, y1: y, y2: y,
    }));
    const label = svgEl("text", { class: "axis-text", x: padL - 7, y: y + 3, "text-anchor": "end" });
    label.textContent = value;
    svg.append(label);
  }

  const colW = plotW / data.length;
  const barW = Math.max(3, Math.min(9, colW / 2 - 2.5));
  const gap = 2; // surface gap between the paired bars

  data.forEach((bucket, index) => {
    const cx = padL + colW * index + colW / 2;
    const group = svgEl("g", { class: "col" });

    // hover band behind the pair
    group.append(svgEl("rect", {
      class: "band",
      x: padL + colW * index, y: padT,
      width: colW, height: plotH, rx: 4,
    }));

    const bar = (value, color, offset) => {
      if (value <= 0) return;
      const h = Math.max(2, (value / peak) * plotH);
      group.append(svgEl("rect", {
        class: "bar",
        x: cx + offset, y: padT + plotH - h,
        width: barW, height: h,
        rx: Math.min(3, barW / 2),
        fill: color,
      }));
    };
    bar(bucket.in, "var(--positive)", -barW - gap / 2);
    bar(bucket.out, "var(--secondary)", gap / 2);

    // x labels: only every other day, so they never collide
    if (index % Math.ceil(data.length / 7) === 0) {
      const label = svgEl("text", {
        class: "axis-text", x: cx, y: H - 5, "text-anchor": "middle",
      });
      label.textContent = bucket.date.toLocaleDateString(undefined, { day: "numeric", month: "short" });
      svg.append(label);
    }

    group.addEventListener("mouseenter", () => showTooltip(container, svg, bucket, cx / W));
    group.addEventListener("mouseleave", () => hideTooltip(container));
    svg.append(group);
  });

  const chart = document.createElement("div");
  chart.className = "chart";
  chart.append(svg);
  container.append(chart);
}

function showTooltip(container, svg, bucket, xRatio) {
  hideTooltip(container);
  const tip = document.createElement("div");
  tip.className = "tooltip";

  const date = document.createElement("div");
  date.className = "t-date";
  date.textContent = bucket.date.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
  tip.append(date);

  const line = (label, value, color) => {
    const row = document.createElement("div");
    row.className = "t-row";
    const swatch = document.createElement("i");
    swatch.style.background = color;
    row.append(swatch, document.createTextNode(`${label} ${value}`));
    return row;
  };
  tip.append(line("In", bucket.in, "var(--positive)"));
  tip.append(line("Out", bucket.out, "var(--secondary)"));

  tip.style.left = `${xRatio * 100}%`;
  tip.style.top = "-4px";
  container.append(tip);
}

function hideTooltip(container) {
  container.querySelector(".tooltip")?.remove();
}
