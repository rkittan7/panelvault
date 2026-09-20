# ETEK Ø22 mm panel lamps

**Research date:** 20 September 2026
**Scope:** ETEK's 22 mm panel-mount indicator lamps only - the EKLD22 LED indicator and the lamp variants of the EKPB2 pushbutton range. Nothing else from ETEK is covered here.

Draft rows for the app, in `webapp/catalog.json` format, are in [`etek-catalog-rows.json`](etek-catalog-rows.json) (3 rows, group `door-devices`). They are not yet in the catalog.

> ETEK publishes model codes and a feature list per range but no per-reference ordering tables - there is no downloadable datasheet on the public site, and the product pages say to contact sales for ordering codes. Everything below is from ETEK's own product pages; where a value is missing it is because they do not publish it, and it is marked as such.

## 1. EKLD22 - the dedicated LED indicator

This is the one to use when the hole only needs a lamp.

| Parameter | Value |
|---|---|
| Panel cut-out | **Ø22.5 mm**; Ø25 mm and Ø30 mm with a reducing ring |
| Voltages (Ue) | 6.3, 12, 24, 48 V AC/DC; 110, 220, 380 V AC |
| Current (Ie) | ≤20 mA to ≤80 mA, depending on version |
| Colours | Red, green, yellow, blue, white |
| Light source | High-brightness solid-colour LED |
| Variants | Steady, **flashing**, bi-colour and RGB tri-colour |
| Terminals | Built-in screw terminals |
| Protection | **IP65** |
| Withstand voltage | 2500 V power-frequency, minimum |
| Electrical life | ≥3000 h |
| Ambient | -5 °C to +40 °C, 45-85 % RH |
| Installation / pollution | Category III / degree 3 |

**Not published:** body length behind the panel, terminal wire capacity, exact current per voltage, and the ordering-code structure for colour and voltage. Those come from the sales contact.

Two things worth flagging against the lamps already in the catalog. The **IP65** front rating is the same class as the Salzer and Eaton units, so it is legitimate for a door. But **≥3000 h electrical life is short** for an LED indicator - it is an order of magnitude below what the European brands quote, so on a lamp that sits permanently lit (a "panel live" indicator), expect replacement rather than fit-and-forget.

## 2. EKPB2 - lamps inside the pushbutton range

The EKPB2 is ETEK's 22 mm pushbutton family, in **plastic or metal bezel**, and it carries the illuminated operators and pilot lights that match the buttons in the same panel.

| Parameter | Value |
|---|---|
| Lamp types | **LED 6-24 V**, **neon 110-380 V**, incandescent |
| Circuit rating | AC 50/60 Hz to 380 V; DC to 220 V |
| Control voltages | AC 24, 48, 110, 220, 380 V; DC 24, 48, 110, 220 V |
| Insulation voltage (Ui) | 660 V |
| Electrical durability | 50 x 10⁴ cycles |
| Protection | **IP40** |
| Standard | IEC 60947-5-1 |
| Ambient | -5 °C to +40 °C |

**The IP40 is the catch.** An EKPB2 pilot light is a *panel-interior* or dry-enclosure device; it is not the part to put on an outdoor or washdown door. Where the door needs a sealed lamp, use the EKLD22 at IP65 - and note that mixing the two in one door means two different bezel looks.

**Not published:** ordering codes and suffixes for lamp colour, voltage and bezel material; panel cut-out is implied to be 22 mm by the range name but is not stated on the page.

## 3. Sharing the same hole

**EKLV22** is a 22 mm digital voltmeter from the same family - round (R) or square (S) head, LED display in white, green, red, yellow or blue, AC 80-500 V (RAV/SAV) or DC 5-120 V (RDV/SDV), ≤20 mA, accuracy class 1.0, <200 ms per reading, two-wire on AC, reverse-polarity protection on DC, Ø22 mm cut-out. Not a lamp, but it drops into the same hole pattern if a door needs a reading rather than an indication.

## 4. Where this sits in PanelVault

Group `door-devices`, type **Indicator Light** - the same type string as the Salzer PL16-22D and SZ22 rows, which are the closest existing peers. The draft rows follow the catalog's existing convention of one row per colour for red and green, with the remaining colours noted in the text.

**ETEK is in neither manufacturer list** - not in the phone app's `ManufacturerItem.defaults` ([worker/Sources/Models.swift:208](worker/Sources/Models.swift:208)) and not in the website's `BOARD_MANUFACTURERS` ([webapp/public/app.js:43](webapp/public/app.js:43)) - so an ETEK part read off a scheme falls back to Generic on both. It needs adding to both before these rows are worth much.

## 5. What to ask before ordering

1. Ordering codes for EKLD22 by colour and voltage, and whether the flashing and bi-colour versions are stocked or made to order.
2. Body depth behind the panel and terminal capacity for EKLD22 - needed for a crowded door.
3. Whether the EKPB2 pilot light can be had with a sealed front, or whether IP65 means EKLD22 only.
4. Who imports ETEK into Israel. ETEK publishes no Israeli representative, and ETEK is **not** on Valish's line card - see [`valish-israel-supplier.md`](valish-israel-supplier.md). It is on the shelf at retail here (socketstore, Tel Aviv) but that is MCBs and RCDs, not the lamps.
