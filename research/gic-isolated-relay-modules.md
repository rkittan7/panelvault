# GIC isolated relay output modules (IRL / IRLA series) - product dossier

**Research date:** 20 September 2026
**Scope:** GIC's *Isolated Relay Output Module* range - the four catalogue references IRLA01S, IRLA02S, IRLA04S and IRLA08S - as published by the manufacturer on `gicindia.com`. Technical values come from GIC's own catalogue extract ([`Isolated_Relay_Output_Module.pdf`](https://www.gicindia.com/catalog/Isolated_Relay_Output_Module.pdf), catalogue pages 134-136) and from the instruction manual shipped in the box ([`49LL001-01.pdf`](https://www.gicindia.com/instruction_manual/49LL001-01.pdf)). Where the two disagree, both values are shown and the difference is flagged.

Draft rows for the app, in `webapp/catalog.json` format, are in [`gic-catalog-rows.json`](gic-catalog-rows.json) (4 rows, group `relays`). They are not yet in the catalog.

## 1. What the device is

GIC calls the family **IRL series relay output modules**; the ordering codes all start **IRLA**. It is an *interface / control relay*: a DIN-rail box that takes a volt-free (dry) contact on the field side and gives back a real 8 A changeover contact on the panel side, with the two sides galvanically separated from each other and from the supply.

GIC's own wording is "effective 3 way isolation between supply, input switch & relay output" - three separated circuits, not two:

1. the 85-265 V AC module supply (A1/A2),
2. the low-voltage input loop (C common, Z1...Z8 per channel),
3. each relay's own changeover contact (15/16/18, 25/26/28, ...).

The input loop is driven by the module itself - the connection diagram shows 24 V DC across the input terminals, so the field device is just a closing contact or an **NPN proximity switch**; with a proximity switch the `C` terminal acts as the ground/reference. No separate input supply is wired.

Closing input Zn energises relay Rn and lights its red LED; a green `Un` LED shows the module is powered.

**Typical use, per GIC:** fire-alarm interfaces to HVAC, lift/elevator controls and access-control door releases, plus PLC interfacing - i.e. exactly the case where one fire panel output has to drive several dissimilar circuits that must not share a reference.

## 2. Ordering information

| Cat. No. | Channels | Output | Supply | Width | Packed weight |
|---|---:|---|---|---:|---:|
| **IRLA01S** | 1 | 1 C/O, 8 A | 110-240 V AC | 18 mm (1M) | 90 g |
| **IRLA02S** | 2 | 2 C/O, 8 A | 110-240 V AC | 36 mm (2M) | 129 g |
| **IRLA04S** | 4 | 4 C/O, 8 A | 110-240 V AC | 72 mm (4M) | 209 g |
| **IRLA08S** | 8 | 8 C/O, 8 A | 110-240 V AC | 105 mm (6M) | 303 g |

Every channel is an independent single-pole changeover contact; there is no multi-pole or multi-contact-per-channel option, and there is **no low-voltage (24 V DC) supply variant** in this range. If the panel has only 24 V DC control power, GIC's [slim relay](https://www.gicindia.com/products/interface-relays/slim-relays/) range is the family that offers 24 V DC / 24 V AC-DC / 120 V AC-DC / 230 V AC coils.

## 3. Technical specification

| Parameter | Value |
|---|---|
| Function | Interface / control relay |
| Supply voltage | 85-265 V AC (marked 110-240 V AC) |
| Frequency | 47-63 Hz |
| Power consumption (max @ 265 V AC) | 2.5 VA (01S) / 3 VA (02S) / 3.8 VA (04S) / 5.6 VA (08S) |
| Input | Volt-free contact or NPN proximity switch, 24 V DC loop provided by the module |
| Output | 1 C/O per channel, 8 A resistive @ 240 V AC / 30 V DC |
| Contact material | AgNi / AgSnO₂ |
| Mechanical life | 1 x 10⁷ operations |
| Electrical life | 1 x 10⁵ operations (manual). The catalogue extract prints 10⁷ for both lines - treat the manual's 10⁵ as the design figure |
| LED indication | Green `Un` = power on; red `Rn` = that channel's relay energised |
| Mounting | 35 mm symmetrical DIN rail, or surface/base mounting via two Ø4.2 mm holes |
| Degree of protection | IP-20 terminals; IP-40 housing (the manual also carries an "IP-30 for housing" note - confirm on the unit if the panel's IP claim depends on it) |
| Pollution degree | 2 |
| Housing | Flame retardant UL 94-V0 |
| Operating temperature | -20 °C to +55 °C |
| Storage temperature | -25 °C to +70 °C |
| Humidity | 15-85 % RH, non-condensing |
| Max altitude | 2000 m |

### 3.1 Isolation - the reason to buy it

Tested to IEC 60947-5-1 Ed. 3.0:

| Between | Test voltage |
|---|---:|
| Supply input to input switch | 4 kV AC |
| Supply input to relay output | 4 kV AC |
| Input switch to relay output | 4 kV AC (2.5 kV AC on one column of the table - the 8-channel unit is the likely exception; verify before relying on 4 kV for IRLA08S) |

The manual additionally cites insulation resistance > 50 kΩ (single-fault condition) and IEC 61010-1 Ed. 3.0.

### 3.2 Standards and certification

- **Safety:** IEC 60947-5-1, IEC 61010-1, UL 508
- **EMC immunity:** IEC 61000-4-2 (ESD, Level II), 61000-4-3 (radiated, Level II), 61000-4-4 (fast transients, Level IV), 61000-4-5 (surge, Level IV), 61000-4-6 (conducted, 10 V Level III), 61000-4-11 (dips and interruptions)
- **Emissions:** CISPR 14-1 conducted and radiated, Class A; harmonic current IEC 61000-3-2
- **Environmental:** IEC 60068-2-1 cold, 60068-2-2 dry heat, 60068-2-6 vibration, 60068-2-27 shock (repetitive and non-repetitive)
- **Marks:** CE, RoHS - [EC Declaration of Conformity](https://www.gicindia.com/CE&RoHS/EC_Declaration_of_Conformity_Isolated_Relay_Module.pdf) (scanned; no machine-readable text)

Note the **Class A emissions** rating: this is industrial equipment, not intended for residential supply networks without further assessment.

## 4. Terminals and wiring

| | Terminal screw | Torque | Conductor |
|---|---|---:|---|
| One size in the range | M3 | 0.60 N·m (6 lb·in) | 1 x 4.0 mm² (catalogue) / 1 x 0.8-5 mm² (manual), 18-10 AWG (manual) or 20-10 AWG (catalogue), 3.5-4.0 mm blade |
| The other | M2.6 | 0.54 N·m (5 lb·in) | 1 x 2.5 mm² (catalogue) / 1 x 0.2-3.3 mm² (manual), 24-12 AWG, 3.5 mm blade |

**Caution:** the catalogue and the manual lay these two blocks out differently, so which screw size belongs to the single-channel unit and which to the 2/4/8-channel units cannot be settled from the PDFs alone. Check the printed leaflet in the box before torquing. Both documents agree on: **copper conductor rated 75 °C only**, one conductor per terminal.

### 4.1 Terminal numbering

- Supply: `~A1`, `~A2`
- Input loop: `C` (common) and `Z`, or `Z1`...`Z8` on multi-channel units
- Outputs, per channel *n*: `n5` common, `n6` NC, `n8` NO - so channel 1 is 15/16/18, channel 2 is 25/26/28, channel 4 is 45/46/48, channel 8 is 85/86/88

### 4.2 Dimensions

Height 90 mm and 100 mm surface-fixing hole centres (Ø4.2 mm, two off) on the 2-, 4- and 8-channel units; widths as in section 2. GIC's mounting drawing is on catalogue page 136 and page 2 of the manual - take the depth and the single-channel outline from the drawing rather than from this table, because the extracted dimension strings are not unambiguous.

GIC's DIN clips are the withdraw-fully type: push a screwdriver into the clip to release, and pull the clips right out when surface-mounting.

## 5. Buying and selecting

- **Manufacturer:** General Industrial Controls Pvt. Ltd. (GIC), Pune 411026, India. Founded 1974, ISO 9001:2015, exports to 100+ countries. Service: +91 20-30680011, service@gicindia.com.
- **Indicative price:** IRLA04S is listed on IndiaMART at about ₹1,080 per piece by an Indian distributor - a reseller figure, useful only as an order-of-magnitude check.
- **Israeli route: M.I. Valish Ltd (מ.י. וליש)**, 7 HaTa'asiya St., Rosh HaAyin, 03-9103377, info@valish.co.il. GIC is on their supplier line card and their homepage announces GIC timers as a new line. GIC's own site publishes no Israel representative, so Valish is the practical route - but confirm with them whether they stock the **IRLA** modules themselves or only the GIC timers. See [`valish-israel-supplier.md`](valish-israel-supplier.md).

### Selection checklist

1. Control supply is mains (110-240 V AC)? If the panel's interface rail runs on 24 V DC, this range does not fit - use GIC slim relays.
2. Load fits 8 A resistive @ 240 V AC / 30 V DC? Inductive and lamp loads need de-rating; GIC publishes no AC15/DC13 figures for this range.
3. Switching duty low? 10⁵ electrical operations is fine for fire-alarm and interlock duty, not for cyclic process switching.
4. Channel count: pick the module, not a cabinet of single relays - 8 channels in 105 mm is the whole point of the range.
5. Field side is a dry contact or NPN proximity? A PNP output or a wet 24 V signal is **not** what the input loop expects.

## 6. Where it sits in PanelVault

- Group: `relays` ("Relays"), alongside the safety relays and Hager latching relays.
- Type string: **Interface Relay** - a new type value; the existing catalog has no interface/isolated relay entries at all.
- **Consistency gap found while researching:** `GIC` is in the website's `BOARD_MANUFACTURERS` list ([webapp/public/app.js:43](webapp/public/app.js:43)) but missing from `ManufacturerItem.defaults` in the phone app ([worker/Sources/Models.swift:208](worker/Sources/Models.swift:208)), even though the comment on the website list says the two are kept in step. A GIC part read off a scheme will fall back to Generic on the phone until GIC is added there.
