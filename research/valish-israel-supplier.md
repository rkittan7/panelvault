# M.I. Valish Ltd (מ.י. וליש) - supplier page

**Research date:** 20 September 2026
**Scope:** kept deliberately narrow - the supplier itself, and the two brands we care about: **GIC** and **ETEK**. Their catalogue carries another twenty brands; none of them are covered here.

**Source:** the company's own site `valish.co.il` and its 61-page digital catalogue, [`valish_catalog.pdf`](https://valish.co.il/image/valish_catalog.pdf).

> **Site health, as of this date:** the certificate on `valish.co.il` has expired (fetch needs `curl -k`), `www.valish.co.il` returns a setup error, and every subpage - about, products, manufacturers, contact - returns a 404 placeholder. Only the homepage and the catalogue PDF work, and the catalogue is undated: its index cites page numbers up to 109 while the file holds 61 pages, so it is abridged or renumbered. Assume anything here can be out of date and confirm by phone.

## 1. The company

| | |
|---|---|
| Name | מ.י. וליש בע"מ / M.I. Valish Ltd |
| Trade | Importer and distributor of electrical and electronic components for Israeli industry, control and panel building |
| In business | Over 50 years (per their own profile) |
| Address | 7 HaTa'asiya St., Rosh HaAyin Industrial Zone, P.O.B. 1460, 48017 |
| Phone / Fax | 03-9103377 / 03-9103388 |
| Email | info@valish.co.il |
| Customers they name | Electrical wholesalers, manufacturing plants, project houses, contractors and **panel shops** |

## 2. GIC - confirmed

GIC is on Valish's supplier list, and the homepage banner reads *"ספקים חדש - טיימרים מתוצרת חברת GIC"*: **GIC timers are a recent addition to their line card.** That is almost certainly why GIC entered the app's manufacturer picker.

What the catalogue shows against the GIC line:

| Catalogue pages | Products | Part numbers printed |
|---|---|---|
| 14 | **Timers**: staircase automats (0-20 min and 0-20 h), off-delay, on-delay, motor reset, star-delta, multifunction 0.1 s-999 h | B2B3B1, C1C3B1, RDT4, ODT4, UDT0, SDT0, SDT1S, CJDT0, CMDT0, DDTS |
| 15 | **Digital panel pulse counters**, 85-265 VAC / 12-48 VAC-DC / 10-80 VDC, 24x48 and 45x45 formats, to 999999 | Z72FBA, ZJ2FBA, ZH2FBA, A6B1, D1B1, LA25F1, LD17F1 |

The PDF prints no brand beside those codes - the attribution rests on the homepage banner, and GIC's own site publishes no model codes for its timers to cross-check against. Treat it as strong but not proven.

**Not shown in the catalogue:** the **IRLA isolated relay modules**, the monitoring relays, the slim relays or anything else from GIC's range. Full product detail on the IRLA family is in [`gic-isolated-relay-modules.md`](gic-isolated-relay-modules.md), with draft catalog rows in [`gic-catalog-rows.json`](gic-catalog-rows.json).

## 3. ETEK - not confirmed

**ETEK does not appear anywhere in Valish's published material.** Their supplier picker lists 21 brands - Canalplast, Tend, Songchuan, Telergon, Bremas Ersce, Grafoplast, MMM, ILME, Esbee, Hugro, Tecsystem, Moflash, Flexicon, Rehau, Alfaelectric, Elfin, Zippy, ZS, GIC, Connectwell, Teco - and ETEK is not among them. No ETEK part number (EKM, EKL, EKC, ETM, ETL, ETD, ETU) appears anywhere in the 61 pages, and the unattributed contactor family in their catalogue is a CN/CU series with RHU overloads, which is not ETEK's EKC/EKR naming.

That does not settle it. Their published material is visibly stale, so the line may have been added since. But on the evidence, **the ETEK-via-Valish route is unconfirmed** - which is the single most useful thing to ask them.

The ETEK parts we actually want - the Ø22 mm panel lamps - are in [`etek-22mm-lamps.md`](etek-22mm-lamps.md), with 3 draft rows in [`etek-catalog-rows.json`](etek-catalog-rows.json).

## 4. What to ask on the call - 03-9103377

1. **Do you carry ETEK?** If yes: which ranges, and is there a price list?
2. Which **GIC** lines do you stock - only timers, or also the **IRLA isolated relay modules**, monitoring relays and slim relays?
3. Confirm the GIC timer part numbers on catalogue page 14 are current, and get the counter range on page 15 attributed.
4. Current full catalogue with a date on it.

## 5. App note

Neither **GIC** nor **ETEK** exists in the phone app's `ManufacturerItem.defaults` ([worker/Sources/Models.swift:208](worker/Sources/Models.swift:208)). GIC is at least in the website's `BOARD_MANUFACTURERS` ([webapp/public/app.js:43](webapp/public/app.js:43)); ETEK is in neither list, so an ETEK part read off a scheme falls back to Generic on both.
