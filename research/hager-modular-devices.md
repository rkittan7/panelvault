# Hager relays and modular (DIN-rail) devices - catalogue dossier

**Research date:** 19 September 2026
**Source:** Hager's international export store, "Hager Africa & Near East" (`hager.com/intl-en/catalogue`), which is the store serving Israel. Every reference list below is complete for that store on this date: each category was paged through in full. Technical values come from each reference's own product page. Other Hager regions (UK, DE, FR) sell further ranges; section 9 covers them.

Draft rows for the app, in `webapp/catalog.json` format, are in [`hager-catalog-rows.json`](hager-catalog-rows.json) (9 rows). They cover only the latching relays (EPN, EPS), load-shedding relays (60060, ED183), time relays and staircase timer (EZM100, EZD100, EZF100, EZL100, EMN001) and twilight switches (EEN). The rest of this dossier is reference only. The rows are not yet in the catalog.

## 1. What was collected

| Store category | References | Where it goes in PanelVault |
|---|---:|---|
| Miniature circuit breakers (MCB and multipolar) | 506 | `mcbs` |
| Residual current circuit breakers (RCCB) | 66 | `rcbo` |
| Add-on blocks for MCB (earth-leakage blocks) | 39 | `rcbo` |
| Latching (impulse) relays and accessories | 19 | `relays` |
| Installation relays, contactors, load shedding | 71 | `contactors` / `relays` |
| Monitoring / control relays (EU range) | 7 | `relays` |
| Residual-current relays and toroids (HR) | 13 | `relays` |
| Time switches and relays | 6 | `control-automation` |
| Twilight switches | 8 | `control-automation` |
| Modular switches, push buttons, LED indicators | 64 | `switching` / `door-devices` |
| Modular load switch breakers and changeover switches | 58 + 11 | `switching` |
| Energy meters | 16 | `metering` |
| Bell and safety transformers | 8 | `control-power` |
| Dimmers, bells | 4 + 2 | not drafted (not panel parts) |

## 2. Relays

### 2.1 Latching (impulse) relays - EPN / EPS

All 16A AC1, 250V (4-pole versions to 400V), 50/60Hz. An impulse relay toggles its contacts on each pulse from a push button.

| Ref | Contacts | Coil | Modules |
|---|---|---|---:|
| EPN510 | 1NO | 230V AC (also 110V DC) | 1 |
| EPN511 | 1NO | 12V | 1 |
| EPN513 | 1NO | 24V | 1 |
| EPN515 | 1NO+1NC | 230V | 1 |
| EPN518 | 1NO+1NC | 24V | 1 |
| EPN520 | 2NO | 230V | 1 |
| EPN521 | 2NO | 12V | 1 |
| EPN524 | 2NO | 24V | 1 |
| EPN526 | 2NO | 48V | 1 |
| EPN525 | 2NO+2NC | 230V | 2 |
| EPN540 | 4NO | 230V | 2 |
| EPN541 | 4NO | 24V | 2 |
| EPN546 | 3NO+1NC | 230V | 2 |
| EPS410B | 1NO, electronic, silent | 230V | 1 |
| EPS450B | 1NO, electronic, with 5min-1h off timer | 230V | 1 |

Accessories: EPN050 (centralised control), EPN051 (aux 1NO+1NC), EPN052 (multi-level central control), EPN053 (control by maintained contact).

### 2.2 Monitoring relays - EU range

All 17.5mm or 35mm wide, 87mm high, 230/400V networks, measuring range 161-520V.

| Ref | Monitors | Contacts | Modules | Notes |
|---|---|---|---:|---|
| EUM100 | Voltage (under and window), phase loss, sequence | 1CO | 1 | Off-delay 0.1-10s |
| EUM200 | Same as EUM100 | 2CO | 2 | Off-delay to 30s, 50/60Hz |
| EUP100 | Phase loss, sequence, asymmetry (no voltage limits) | 1CO | 1 | 3P(N) only |
| EUU100 | Undervoltage | 1CO | 1 | 0.2s drop-out |
| EUU200 | Undervoltage | 2CO | 2 | 0.2s drop-out |
| EUD100 | Voltage and phase, with on-delay | 1CO | 1 | Off-delay to 10s |
| EUC100 | Current, single phase | 1CO | 1 | Measuring range not published on the page |

### 2.3 Earth-leakage relays - HR range

| Ref | Setting | Type | Delay |
|---|---|---|---|
| HR500 | 30mA fixed | A | Instantaneous |
| HR502 | 300mA fixed | A HI | Instantaneous |
| HR510 | 30mA, 100mA, 300mA, 500mA, 1A, 3A, 10A | A HI | Adjustable |

The toroid is separate and can be up to 25m from the relay (50m with twisted pair). It withstands 30kA for 100ms. Toroids:
- round: HR700 (30mm), HR741 (35mm), HR742 (70mm), HR743 (105mm), HR744 (140mm), HR745 (210mm)
- rectangular: HR830 (70x175mm), HR831 (115x305mm), HR832 (150x350mm), HR833 (200x500mm)

### 2.4 Installation relays and contactors

AC-7a/AC-7b rated; Hager lists 100,000 mechanical and 30,000 electrical operations. These are building contactors, not motor contactors: the ESC225 is 25A AC1 but only 8.5A AC-3.

| Family | Coil | Ratings | Contacts available |
|---|---|---|---|
| ESC | 230V AC 50Hz | 25A (1-2M), 40A and 63A (3M) | 1NO, 2NO, 2NC, 1NO+1NC, 3NO, 4NO, 4NC, 2NO+2NC, 3NO+1NC |
| ESD | 24V AC | 25A, 63A | 2NO, 2NC, 1NO+1NC, 4NO, 4NC, 2NO+2NC |
| ESL225 | 12V AC | 25A | 2NO |
| ESC..S / ESD..S | Hum-free 230V AC, 24V AC, 24V DC (..SDC) | 25-63A | See the reference list |
| ERC / ERD | 230V / 24V, with manual override switch | 25A, 40A, 63A | 1NO-4NO, 2NC, 4NC, 2NO+2NC |
| ERC216 / 218 / 418, ERD218 | 230V / 24V | 16A relay (AC-3 5.5A) | 2NO, 1NO+1NC, 2NO+2NC |
| ESC080 | - | 6A aux contact, half module | 1NO+1NC |

Hager's warning on hum-free parts: they "are not suitable for intensive use cases (powered 24/7)".

Load shedding: 60060 (universal 3-channel load shedder, 3 modules) and ED183 (intensity relay, 7-39A setting, 400V, 1 module).

### 2.5 Time relays and switches

| Ref | Function | Supply | Range | Contact |
|---|---|---|---|---|
| EZM100 | Multifunction | 12-240V AC/DC | 50ms-100h | 1CO 8A |
| EZD100 | On-delay | 24-240V AC/DC | 50ms-100h | 1CO 8A |
| EZF100 | Off-delay with control input | 24-240V AC/DC | 50ms-100h | 1CO 8A |
| EZL100 | Emergency-lighting test | 230V AC | 10-180min | 1CO 8A |
| EMN001 | Staircase time lag | 230V | 30s-10min | 16A NO |

Twilight switches: EEN100 (wall cell) and EEN101 (flush cell), 1 module, 10A, 5-2000lx; spare cells EEN002 and EEN003. The EE701, EE702, 4504 and 4505 are wall-mounted compact units, not DIN-rail.

## 3. MCBs

Icn is the rating to IEC 60898-1 and Icu the rating to IEC 60947-2. Where a family shows two figures, like "10/15kA", they are Icn/Icu.

| Series | Curve | Breaking capacity | Poles | Amp ratings in this store |
|---|---|---|---|---|
| NBN | B | 10kA Icn / 15kA Icu | 1P, 2P, 3P | 6, 10, 16, 20, 25, 32, 40, 50, 63 |
| | | | 4P | as above, without 50 |
| NCN | C | 10kA Icn / 15kA Icu | 1P, 2P, 3P | 2, 4, 6, 10, 16, 20, 25, 32, 40, 50, 63 |
| | | | 4P | 6-63 |
| NDN | D | 10kA Icn / 15kA Icu (1P 32A and 50A: 10kA) | 1P-4P | 2-63 |
| NFN | C | 6kA Icn / 10kA Icu | 1P-4P | 4-63 |
| NF..A | C | 6kA / 10kA | 1P-4P | 2-63 |
| NEN | B | 6kA / 10kA | 1P-3P | partial set (6, 16, 20, 25, 32, 40, 50, 63) |
| NFT | C | 6kA / 10kA | 1P+N (1M) | 2-40 |
| NGN100 | D | 6kA / 10kA | 1P | 0.5 only |
| NRN | C | 25kA Icu up to 25A; 20kA at 32-40A; 15kA at 50-63A | 1P-4P | 0.5-63 |
| NQN120 | B | 25kA | 1P | 20 only |
| HMX | C | 50kA Icn and Icu | 1P-4P (1.5M per pole) | 10, 16, 20, 32, 40, 63 |
| HMB / HMC / HMD | B / C / D | 15kA Icn | 1P-4P (1.5M per pole) | 80, 100, 125 |
| MU | C | 6kA | 1P-4P | 6-63 (4P to 50) |
| MB | B | 6kA | 1P, 2P, 4P (3P 6A only) | 6-63 |
| MT | B | 6kA | 2P, 3P | 6-40 |
| MBN | B | 6kA Icn / 10kA Icu | 4P (plus some 1P and 3P) | 6-50 |
| MN..Z | C | 6kA Icu | 1P-3P; 4P 63A only | 6-50 |
| MA..Z | C | 6kA Icu, Ue 230V | 1P-4P | 2-40 |
| MC..A | C | 6kA | 1P-4P | 0.5-6, plus 4P 40/50/63 |
| MW, MV..Z | C | 3kA | MW 1P-4P, MV 1P | 6-40 |
| MJT | C | 4.5kA Icn / 6kA Icu | 1P+N (1M) | 2-40 |
| MLN | C | 6kA | 1P+N (1M) | 6-40 |

How the part numbers read: series letters, then the pole digit (1-4, or 7 for 1P+N), then the amps (99 = 125A, 90 = 100A, 00 = 0.5A), then a suffix letter for the variant. For example, NCN316A is an NCN, 3-pole, 16A. The N-series and M-series with a biconnect bottom terminal take a comb busbar underneath and a cable on top.

## 4. RCCBs

| Letters | Poles | Ratings | Sensitivity | Type |
|---|---|---|---|---|
| CDC / CFC / CCC | 1P+N, 3P+N | 16-100A | 10, 30, 300mA | AC |
| CE / CGC | 2P, 4P | 40-63A | 100, 500mA | AC |
| CD / CF | 2P, 4P | 25-63A | 30, 300mA | A |
| CEA440E | 4P | 40A | 100mA | A |
| CDA / CFA / CGA | 3P+N | 80-125A | 30, 300, 500mA | A |
| CDH / CFH / CH / CQ | 1P+N-4P | 25-125A | 30, 300mA | A high immunity |
| CDB | 1P+N, 3P+N | 25-63A | 30mA | B |
| CN / CP / CPA | 2P, 4P, 3P+N | 40-100A | 100, 300mA | Selective (S) |

The earth-leakage add-on blocks (BD, BF, BE, BG, BR, BDC, BFC, BDH, BFH, BTH; 2P-4P, 25-125A, 30mA to adjustable) clip onto a matching MCB to make an RCBO.

## 5. Switching and door devices

- **SBN modular switches:** 1P-4P, 16-125A. SBB216/225/232 are 2P with an indicator lamp.
- **Load break switches:** HAB (20-63A), HAC (63-80A), HAD (100-125A), HAE (125-160A, visible break), HA406 (4P 125A, visible break) and HA964N (4P 250A). HZC and HZI handles, shaft extensions, auxiliary contacts (HZC311, HZC312) and terminal shrouds.
- **Changeover switches:** HIM302/304/308 (3P 20/40/80A), HIM402/406 (3P+N 20/63A), HI403R-HI406R (63-125A). SF263/SF463 (63A, I-0-II), SFT (centre off, 25-40A) and SFH (25A, no off), both with a top common point.
- **SVN LED indicators:** 121 green, 122 red, 123 orange, 124 blue, 125 clear, all 230V; 131 green and 132 red at 12-48V; double 126/222 and triple 127/129/221/223. SVS..B are the QuickConnect busbar versions.
- **SVN push buttons:** 311/321/331/351/371/391 impulse; 312/352 latching; 411/432/433/452 have a built-in lamp.
- **Selector and key switches:** SK600 selector (stays in position), SK606 key switch 10A.

## 6. Energy meters (all DIN-rail)

| Family | Comms | References |
|---|---|---|
| ECR | Modbus RTU, MID | ECR180D (1ph 80A), ECR380D (3ph 80A), ECR300C (3ph CT 1/5A) |
| ECM | M-Bus, MID | ECM140D (1ph 40A, 1M), ECM380D (3ph 80A), ECM310D (3ph 125A), ECM300C (CT) |
| ECP | S0 pulse, MID | ECP140D, ECP180D, ECP300C |
| ECA | Agardio, MID | ECA180D, ECA380D, ECA310D, ECA300C |
| ECN140D | none, not MID | 1ph 40A |

TXF121 is a KNX interface for the meters.

## 7. Transformers

- **Bell transformers:** ST301 (4VA), ST303 (8VA), ST305 (16VA); 230V to 8-12V.
- **Safety transformers:** ST313 (16VA), ST312 (25VA), ST314 (40VA), ST315 (63VA); 230V to 12-24V.

## 8. Things to decide before merging

1. **Three new `type` values.** The drafts use `Latching Relay`, `Load-Shedding Relay` and `Twilight Switch`. The drawing matcher and any type filters have never seen them. The alternative is to fold them into the existing `Relay` and `Timer` types.
2. **Hager is not in the default brand list yet.** It needs adding, as Allen-Bradley, Salzer and Satec were, with its colour and logo.

## 9. Not in the Near East store

Searching the store for "RCBO" returns nothing. A search for surge protection returns only obsolete SPK data-line protectors, and no arc-fault device appears. Hager does sell these in Europe:
- ADA/ADC RCBOs
- SPN surge arresters
- ARC arc-fault devices

If they are wanted, they need a separate pass on the UK or DE catalogue, and the Israeli distributor should confirm they can be supplied.

## Sources

- Store category pages under `https://hager.com/intl-en/catalogue/modular-devices/...` and `.../high-power-switching/residual-current-relays-and-motor-protection-switches/residual-current-relays-and-accessories`
- Product pages at `https://hager.com/intl-en/catalogue/information/<ref-slug>`, for example [EUM100](https://hager.com/intl-en/catalogue/information/eum100-u-p-control-relay-1p-3p-n-1co), [EZM100](https://hager.com/intl-en/catalogue/information/ezm100-multifunction-time-relay-12-240v), [HR510](https://hager.com/intl-en/catalogue/information/hr510-elr-0-03-10a-confi-type-a), [ESC225](https://hager.com/intl-en/catalogue/information/esc225-contactor-25a-2no-230v), [NCN116A](https://hager.com/intl-en/catalogue/information/ncn116a-mcb-1p-10ka-15ka-c-16a-1m) and [NRN116](https://hager.com/intl-en/catalogue/information/nrn116-mcb-1p-25ka-c-16a-1m)
- EUM100 and EUP100 measuring ranges and functions: [eibabo EUM100](https://www.eibabo.us/hager/control-relay-1p-n-3p-n-1-changeover-contact-installation-relay-eum100-eb11812567), [eibabo EUP100](https://www.eibabo.us/hager/control-relay-3p-n-1-changeover-contact-installation-relay-eup100-eb11812569)
