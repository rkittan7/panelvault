# Socomec changeover switches - product and selection dossier

**Research date:** 24 August 2026  
**Scope:** Current Socomec transfer/changeover-switch products found in the EMEA/IEC and North American/UL catalogues, plus regional products that materially extend the range. This is a family-level engineering and procurement guide; exact reference-specific electrical ratings, dimensions, terminals, accessories, firmware and certificates must be checked on the selected reference page before ordering.

## 1. Executive summary

Socomec calls this product class **Transfer Switching Equipment (TSE)**. The company divides it by how the transfer is initiated:

- **MTSE** - manually operated transfer switching equipment.
- **RTSE** - remotely operated transfer switching equipment, normally commanded by dry/volt-free contacts from a PLC, genset controller, pushbutton station or external ATS controller.
- **ATSE** - automatic transfer switching equipment with source monitoring and transfer logic built in or supplied as a coordinated controller.

The current IEC range runs from **25 A to 6300 A**:

- Compact manual: **COMO CS**, **SIRCO M**, **SIRCO VM1**.
- Heavy-duty manual: **SIRCOVER**, including open-transition, overlapping-contact, bypass and PV variants.
- Compact remote/automatic: **ATyS S** and **ATyS M**.
- Large remote/automatic: **ATyS r**, **ATyS g**, **ATyS p**.
- Very-high-current remote: **ATyS d H**, 4000-6300 A.
- Separate ATS controllers: **ATyS C25, C35, C55 and C65**.
- Enclosed and maintenance-bypass assemblies are available for several families.

The North American portfolio is different: **SIRCOVER UL** manual switches and **ATyS UL 1008** non-automatic switches cover 100-1200 A, while **ATyS FT** and **ATyS DT** automatic switches cover 100-400 A under UL 1008/cULus.

Socomec's EMEA catalogue says its TSE products comply with IEC 60947-6-1. Individual families may additionally cite IEC 60947-3, GB/T 14048.11, IEC 61439-2 for assemblies, or UL/CSA standards in North America. Do not transfer a certification claim from one regional product to another.

## 2. How the switching arrangements differ

| Marking / name | Electrical sequence | Load interruption | Correct use |
|---|---|---:|---|
| **I-II** | Source I to Source II without an operator-selectable stable OFF position | Brief interruption on an open-transition device | Compact/manual or fast-transfer applications where a maintained OFF position is not required |
| **I-0-II** | Break Source I, pass through a stable centre OFF, then make Source II | Yes | General-purpose open-transition transfer; safest default when sources are not synchronised |
| **I-I+II-II** | Source I, momentary overlap of I and II, then Source II | Intended no-break transfer | Only where both sources are synchronised and the system design permits momentary paralleling |
| **Bypass** | Multiple interlocked switching paths isolate or bypass the normal transfer device | Depends on model and sequence | Maintenance or replacement of ATS/TSE while retaining a supply path |
| **FT** | North American fast, open-transition transfer with no centre-off position | Short transfer interruption | UL 1008 emergency/standby systems needing fast transfer |
| **DT** | North American delayed open transition with a centre-off interval | Controlled interruption | UL 1008 systems needing an intentional neutral/off delay |

**Important:** overlapping-contact transfer is not a general substitute for open transition. Synchronism, phase sequence, voltage, frequency, protection, utility rules and generator-paralleling constraints must all be resolved by the system designer.

## 3. Current IEC/EMEA family matrix

### 3.1 Manual products

| Family | Current range | Poles / arrangement | Main purpose | Principal standard(s) shown by Socomec |
|---|---:|---|---|---|
| [COMO CS I-II](https://emea.socomec.com/en/p/como-cs-i-ii) | 25-100 A | Multi-pole; 3P and 4P references; backplate or door mounting | Compact cam-operated on-load source/circuit transfer | IEC 60947-3; product page also lists UL 60947-4-1 |
| [COMO CS I-0-II](https://emea.socomec.com/en/p/como-cs-i-0-ii) | 25-100 A | I-0-II | Compact manual transfer with OFF | See reference page |
| [COMO CS Bypass I-0-II](https://emea.socomec.com/en/p/como-cs-bypass-i-0-ii) | 25-100 A | Bypass | Compact bypass switching | See reference page |
| [SIRCO M I-0-II](https://emea.socomec.com/en/p/manual-transfer-switch-sirco-m-i-0-ii) | 25-125 A | 3P or 4P | Modular manual transfer with positive-break indication | IEC 60947-3 |
| [SIRCO VM1 I-0-II](https://emea.socomec.com/en/p/manual-transfer-switch-sirco-vm1-i-0-ii) | 63-125 A | 3P or 4P | Modular manual transfer with visible breaking | IEC 60947-3 |
| [SIRCO VM1 I-I+II-II](https://emea.socomec.com/en/p/manual-transfer-switch-sirco-vm1-i-iii-ii) | 63-125 A | 3P or 4P; overlapping contact | Compact no-break manual transfer for synchronised sources | IEC 60947-3 |
| [SIRCOVER I-0-II](https://emea.socomec.com/en/p/sircover-i-0-ii) | 125-3200 A | 3P or 4P; open transition | Heavy-duty manual on-load transfer and isolation | IEC 60947-6-1, IEC 60947-3, GB/T 14048.11 |
| [SIRCOVER I-I+II-II](https://emea.socomec.com/en/p/sircover-i-iii-ii) | 125-1600 A | 3P or 4P; overlapping contact | No-break manual transfer between synchronised sources | IEC 60947-6-1, IEC 60947-3 |
| [SIRCOVER Bypass I-0-II](https://emea.socomec.com/en/p/sircover-bypass-i-0-ii) | 125-1600 A | 3+6P or 4+8P | Three-interlocked-switch bypass arrangement | IEC 60947-6-1, IEC 60947-3 |
| [SIRCOVER Bypass I-I+II-II](https://emea.socomec.com/en/p/sircover-bypass-i-iii-ii) | 125-1600 A | 3+6P or 4+8P; overlap version | No-break bypass arrangement for synchronised sources | IEC 60947-6-1, IEC 60947-3 |
| [SIRCOVER PV](https://emea.socomec.com/en/p/sircover-pv) | 200-630 A | 3P or 4P; I-0-II | On-load changeover/source inversion between PV circuits | IEC 60947-3 |
| [SIRCOVER ATS Bypass](https://emea.socomec.com/en/p/sircover-ats-bypass) | 125-630 A | 4+12P | Simultaneous upstream/downstream ATS isolation plus source selection while bypassed | IEC 60947-3 family documentation |

### 3.2 Remotely operated products

| Family | Current range | Poles / supply | Control and use | Standard(s) shown |
|---|---:|---|---|---|
| ATyS S 12 VDC | 40-125 A | Compact RTSE; 12 VDC motor supply | Dry-contact remote transfer | See selected reference |
| ATyS S 24/48 VDC | 40-125 A | Compact RTSE; 24/48 VDC motor supply | Dry-contact remote transfer | See selected reference |
| ATyS S 230 VAC | 40-125 A | Compact RTSE; 230 VAC motor supply | Dry-contact remote transfer | See selected reference |
| ATyS d S | 40-125 A | Compact RTSE; dual 230 VAC source supply | Source-independent remote operation from either available supply | IEC family documentation |
| [ATyS d M](https://emea.socomec.com/en/p/atys-d-m) | 40-160 A | 2P or 4P; dual 230 VAC source inputs with integrated DPS on published references | Modular RTSE controlled by volt-free contacts; external controller required for automatic operation | IEC 60947-6-1, IEC 60947-3, GB/T 14048.11 |
| [ATyS r](https://emea.socomec.com/en/p/atys-r) | 125-3200 A | 3P or 4P | Motorised Class PC RTSE; pulse logic from PLC, switch, genset controller or external ATS controller | IEC 60947-6-1, IEC 60947-3, GB/T 14048.11 |
| [ATyS d H IEC Fixed](https://emea.socomec.com/en/p/atys-d-h-iec-fixed) | 4000, 5000, 6300 A | 3P or 4P; integrated dual power supply | High-current fixed RTSE, I-0-II, dry-contact commands | IEC 60947-6-1, Class PC |

All ATyS M devices use mechanically stable positions and power the actuator during transfer rather than continuously. Socomec states a blackout duration below 90 ms for the ATyS d M/t M/g M coil-and-rotating-contact platform. This figure is platform-specific and is not a universal transfer time for every ATyS product.

### 3.3 Automatic products

| Family | Current range | Poles | Controller/application | Key distinction |
|---|---:|---|---|---|
| [ATyS t M](https://emea.socomec.com/en/p/atys-t-m) | 40, 63, 80, 100, 125, 160 A | 4P | Integrated controller for three-phase mains/mains | Quick setup by potentiometer and DIP switches; priority-source functions |
| [ATyS g M](https://emea.socomec.com/en/p/atys-g-m) | 40, 63, 80, 100, 125, 160 A | 2P or 4P | Integrated controller for mains/genset | Compact single- or three-phase ATSE; AC-33B capability stated up to 125 A |
| [ATyS p M](https://emea.socomec.com/en/p/atys-p-m) | 40, 63, 80, 100, 125, 160 A | 4P references; supports single- or three-phase applications | Fully programmable integrated controller | Adds flexible parameters, remote-control interface and trip function to t M/g M capabilities |
| [ATyS p M + COM](https://emea.socomec.com/en/p/atys-p-m-com) | 40, 63, 80, 100, 125, 160 A | 4P references published on this page | Fully programmable controller plus communication | Six COM references in the current EMEA page |
| [ATyS g](https://emea.socomec.com/en/p/atys-g) | 125-3200 A | 3P or 4P | Integrated controller for mains/mains and mains/genset; settings by potentiometers/DIP switches | Optional RS485 monitoring; 30 IEC Class PC versions |
| [ATyS p](https://emea.socomec.com/en/p/atys-p) | 125-3200 A | 3P or 4P | Fully programmable integrated controller with LCD | Event log, power/energy measurement, programmable I/O, genset exercise, optional RS485 or Ethernet/webserver; 30 Class PC versions |

The standard modular current steps are **40, 63, 80, 100, 125 and 160 A**. The published large ATyS range uses **125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500 and 3200 A** frames/references.

### 3.4 Regional IEC variant

[ATyS a M](https://apac.socomec.com/en/p/atys-a-m) is a preset automatic transfer switch published in Socomec's APAC catalogue from **25 to 160 A**. It should be treated as a regional offer: confirm local availability, voltage/frequency version, approvals and support before specifying it outside that sales region.

## 4. Separate ATS controllers

An RTSE becomes an automatic scheme only when paired with a suitable controller and correctly designed sensing/control wiring.

| Controller | Positioning | Suitable switch technologies / notable functions |
|---|---|---|
| [ATyS C25](https://emea.socomec.com/en/p/atys-c25) | Entry level, with communications | Drives ATyS r/S/d M or contactor-based schemes; fixed timers and thresholds; not the stated choice for breaker-based systems |
| [ATyS C35](https://emea.socomec.com/en/p/atys-c35) | Digital functions | Display and communication; programmable thresholds/timers; can drive Socomec or other switch-, contactor- or breaker-based RTSE |
| [ATyS C55](https://emea.socomec.com/en/p/atys-c55) | Smart functions | Configurable sources and timers; supports motorised switches, breakers or contactors; transformer/transformer and transformer/genset combinations |
| [ATyS C65](https://emea.socomec.com/en/p/atys-c65) | Advanced functions | Current, voltage and energy monitoring; load shedding, fire-fighting lift functions, autonomy, events/alarms and DIRIS Digiware compatibility |

Controller standards published by Socomec include IEC 61010-2-201 and, depending on model and coordinated RTSE, IEC 60947-6-1 and GB/T 14048.11 Annex C.

## 5. Bypass and enclosed solutions

Socomec lists both component-form switches and factory-enclosed solutions. Current EMEA category entries include:

- **ATyS Bypass Single Line** and **ATyS Bypass Double Line**, 40-3200 A, for no-break ATS maintenance arrangements.
- **ATyS g/p in steel enclosures**, 200-3200 A.
- **ATyS d M, g M and p M in steel enclosures**, 40-160 A.
- **ATyS g M in polycarbonate enclosures**, 40-160 A, including single-phase versions.
- **ATyS p M / ATyS p IGH in steel enclosures**, 40-400 A, aimed at sensitive/high-rise/public-access buildings.
- **COMO CS in polycarbonate enclosures**, 25-100 A.
- **SIRCO M in steel enclosures**, 32-100 A.
- **SIRCOVER in polyester enclosures**, 160-630 A.
- **SIRCOVER in painted-steel enclosures**, 160-1600 A.

The enclosed-product pages cite IEC 60947-3, IEC 60947-6-1 and IEC 61439-2 as applicable. The enclosure is not merely an accessory: assembly rating, temperature rise, IP protection, cable space, gland arrangement, short-circuit coordination and installation method must be checked at the assembly level.

## 6. North American UL/CSA portfolio

| Family | Range | Transfer type | Compliance and notes |
|---|---:|---|---|
| [SIRCOVER UL](https://www.socomec.us/en-us/p/sircover-ul) | 100, 200, 260, 400, 600, 800, 1200 A | Manual I-0-II; 2P/3P/4P depending rating | UL 1008 (transfer), UL 98 (disconnect variants), CSA C22.2 No. 4; ratings/certification vary by reference |
| [ATyS UL 1008](https://www.socomec.us/en-us/p/atys-ul-1008) | 100, 200, 260, 400, 600, 800, 1200 A | Non-automatic motorised open transition; 2P/3P/4P depending rating | UL 1008 and IEC 60947-6-1 shown; compatible with external TSE controls |
| [ATyS FT](https://www.socomec.us/en-us/p/atys-ft) | 100, 200, 260, 400 A | Fully automatic fast open transition, no centre OFF | cULus/UL 1008 and CSA C22.2 No. 178.1-14; includes C66 controller; RS485 Modbus and Digiware bus |
| [ATyS DT](https://www.socomec.us/en-us/p/atys-dt) | 100, 200, 260, 400 A | Fully automatic delayed open transition with centre OFF | Same cULus standard family; includes C66 controller; intentional disconnected interval |

North American FT/DT references include 3P, 4P and solid-neutral configurations depending model. Socomec describes them for emergency, legally required standby and optional standby systems. Final suitability must be evaluated against NEC article, emergency-system classification, service entrance requirements, withstand/closing rating, upstream protective device and enclosure listing.

## 7. Electrical and mechanical design points

### Positive-break and visible-break indication

- **Positive-break indication** mechanically links the indicated position to the main-contact state; it is a safety feature, not source-voltage proof.
- Some SIRCO VM1 products provide **double visible breaking**, allowing direct visual confirmation of isolation.
- ATyS products use electrical and mechanical interlocking to prevent simultaneous connection of unsynchronised sources in their intended open-transition sequence.

### Class PC

Socomec labels the main SIRCOVER/ATyS IEC switching elements **Class PC** under IEC 60947-6-1. In practical selection, this means the device is a switch-based transfer product whose short-circuit performance depends on its published withstand/conditional ratings and coordination with the specified upstream short-circuit protective device. It is not an overcurrent protective device.

### Utilisation categories

Do not size only from the front-panel ampere value. Check the reference's operational current at the actual voltage and utilisation category:

- **AC-31** - non-inductive or slightly inductive loads.
- **AC-32** - mixed resistive/inductive loads.
- **AC-33** - motor or highly inductive/mixed loads typical of distribution systems.
- The A/B suffix distinguishes frequent and infrequent operating duty as defined by the applicable standard.

Socomec specifically advertises AC-33B performance for SIRCOVER and for ATyS M up to stated ratings; the exact table for the selected reference remains controlling.

### Neutral and pole count

- Use the system earthing/grounding study and local rules to decide whether the neutral is solid or switched.
- A 4-pole transfer switch does not automatically solve every separately derived source or ground-fault scheme; generator neutral bonding, protective-earth continuity, residual-current/ground-fault protection and circulating neutral current must be reviewed together.
- Never switch the protective conductor.

### Short-circuit coordination

For every selected reference, record:

1. Rated operational voltage and current.
2. Utilisation category.
3. Rated short-time withstand current **Icw** and duration, where stated.
4. Conditional short-circuit current / withstand-and-closing rating and the exact fuse or breaker conditions.
5. Required conductor or busbar size and terminal limits.
6. Upstream protective-device manufacturer, model, setting and clearing time.

The UL SIRCOVER catalogue, for example, publishes different short-circuit ratings with specified fuse classes, specific breakers and any-breaker conditions. Those values cannot be mixed.

## 8. Controls, communications and accessories

Availability depends on family and frame, but the range includes:

- Direct and external operating handles, padlockable handles and door-coupling shafts.
- Auxiliary position contacts and pre-break contacts.
- Bridging/common bars, copper connection pieces, terminal screens/shrouds and phase barriers.
- Voltage sensing taps.
- Dual power supply (DPS) modules, autotransformers and 12/24/48 VDC converters for selected ATyS systems.
- Manual emergency handles and selector/key-switch options.
- RS485 Modbus modules; Ethernet modules with embedded webserver on ATyS p; Digiware integration on advanced controllers and North American FT/DT.
- Remote displays, programmable I/O and current transformers where required for power/energy measurement.
- Steel, polyester and polycarbonate enclosures.

Accessory compatibility is frame- and reference-specific. A handle, bridge, terminal cover or communications module for one frame must not be assumed to fit another.

## 9. Selection workflow

1. **Fix the jurisdiction and approval basis.** IEC/GB, UL/CSA, local utility and building/emergency rules come first.
2. **Define the sources.** Mains/mains, mains/genset, two gensets, PV/DC circuits, storage, transformer/transformer, and whether either source is separately derived.
3. **Choose manual, remote or automatic.** Use MTSE for local human operation, RTSE for external logic, or ATSE for integrated sensing and sequence control.
4. **Choose transfer sequence.** I-0-II is the default for unsynchronised sources; overlap/no-break needs a synchronism and paralleling design; bypass is selected for maintainability.
5. **Choose poles/neutral.** Base this on the earthing and protection design, not convenience.
6. **Rate the load.** Continuous current, voltage, frequency, utilisation category, motor starting/inrush, transformer magnetising current, harmonics, ambient temperature and enclosure derating.
7. **Coordinate faults.** Verify Icw/conditional rating or UL WCR/SCCR with the actual upstream device and available fault current.
8. **Choose physical format.** DIN/modular, backplate, door mount, open switch, factory enclosure or switchboard-integrated assembly.
9. **Choose controls.** Supply voltage, dry-contact logic, source sensing, timers, genset start/stop, load shedding, fire input, return-to-zero, exercise schedule and manual-mode behaviour.
10. **Choose communications.** None, status contacts, Modbus RTU, Ethernet/webserver or Digiware ecosystem.
11. **Plan maintenance.** Isolation, lockout, bypass, inspectable contacts, spares, firmware/configuration backup and exercise/testing intervals.
12. **Lock the exact reference.** Download its current datasheet, dimensional drawing, manual, declaration/certificate and approved accessory list.

## 10. Installation and commissioning checklist

- Installation and energisation by qualified electrical personnel only.
- Confirm source voltage, frequency, phase sequence and control-supply version before wiring.
- Maintain required clearances, creepage, phase barriers, terminal covers and enclosure ventilation.
- Torque power and control terminals exactly as specified; re-check busbar alignment so terminals are not mechanically loaded.
- Confirm handle/shaft alignment and door interlocking before energising.
- Test mechanical operation and stable I/0/II positions de-energised.
- Prove source sensing, phase-loss/undervoltage/overvoltage/frequency thresholds and all timers with controlled test conditions.
- Verify generator start, warm-up, transfer, retransfer and cool-down sequences.
- Verify manual mode, remote inhibit, emergency handle, padlocking and all position feedback.
- Test the actual failure modes: loss of preferred source, failure of alternate source, source return, controller loss and motor-supply loss.
- Save the final controller configuration and record firmware, settings, reference numbers, serial numbers and protective-device coordination.
- Establish periodic functional transfer tests and manufacturer-recommended inspection/maintenance.

## 11. Common specification mistakes

- Calling an **RTSE** “automatic” without adding an ATS controller and source sensing.
- Selecting by amperes alone and ignoring AC-33 or UL total-system ratings.
- Treating **I-I+II-II** as safe for unsynchronised utility and generator sources.
- Assuming 4P always means the correct neutral/grounding solution.
- Ignoring available fault current or using a short-circuit rating tied to a different fuse/breaker.
- Combining an open switch and enclosure without validating the finished assembly to IEC 61439-2 or the applicable UL enclosure/listing rules.
- Assuming catalogue accessories are universal across frames.
- Reusing old ATyS d/t/A/C nomenclature from legacy documents without checking whether that exact reference is still active in the target region.
- Specifying communications without the required option module, protocol map, current transformers or gateway.

## 12. Procurement data to capture per reference

For a usable PanelVault/catalogue record, capture these fields:

- Manufacturer and regional sales entity.
- Product family, full description and exact order reference.
- Lifecycle/availability code and country of origin where published.
- MTSE/RTSE/ATSE and Class PC classification.
- Transition sequence and stable positions.
- Rated current, poles, switched/solid neutral arrangement, voltage and frequency.
- IEC utilisation category or UL load category.
- Ui, Uimp, Icw, conditional short-circuit rating or UL WCR/SCCR.
- Operating/control supply and power consumption.
- Transfer time / blackout time under the stated conditions.
- Mechanical and electrical endurance.
- Dimensions, mass, mounting orientation and frame size.
- Terminal type, conductor/busbar ranges and tightening torque.
- Front/device IP rating and enclosure IP/NEMA rating.
- Standard contacts, optional I/O and communications.
- Required and compatible accessories.
- EAN/GTIN, customs code and packing data.
- Datasheet, manual, CAD/BIM, declaration of conformity, third-party certificate, PEP and firmware links.
- Dealer quote, lead time, warranty and local technical-support contact.

## 13. Authoritative source index

### Current product/category sources

- [Socomec EMEA Transfer Switching Equipment category - page 1](https://emea.socomec.com/en/c/transfer-switching-equipment-tse)
- [Socomec EMEA Transfer Switching Equipment category - page 2](https://emea.socomec.com/en/c/transfer-switching-equipment-tse?p=2)
- [Socomec EMEA Transfer Switching Equipment category - page 3](https://emea.socomec.com/en/c/transfer-switching-equipment-tse?p=3)
- [Socomec EMEA transfer-switching controllers](https://emea.socomec.com/en/c/transfer-switching-controllers)
- [Socomec North America transfer switches](https://www.socomec.us/en-us/c/transfer-switches)

### Current catalogues and brochures

- [Socomec 2026 general catalogue - power switching overview (PDF)](https://emea.socomec.com/sites/default/files/2026-03/Overview-Products--services_CATALOGUE-GENERAL_2026-03-16-11-17-44_CGD008_V02_EN_English_PLURI.pdf)
- [SIRCOVER manual transfer switching equipment, 125-3200 A (PDF)](https://emea.socomec.com/sites/default/files/2025-11/SIRCOVER-Manually-operated-Transfer-Swit_CATALOGUE-PAGES_2025-10-28-09-04-32_PCG032_EN_V01_English_PLURI.pdf)
- [ATyS r/g/p, 125-3200 A catalogue pages (PDF)](https://emea.socomec.com/sites/default/files/2025-03/ATYS-RANGE-ATYS-R%2C-ATYS-G%2C-ATYS-P_CATALOGUE---PAGES_2025-03_PCG029_EN_2.pdf)
- [ATyS M modular transfer equipment brochure (PDF)](https://emea.socomec.com/sites/default/files/2026-01/ATyS-M---Modular-Transfer-Switching-Equi_BROCHURE_2026-01-21-14-58-57_DOC0193401en_English_PLURI.pdf)
- [Enclosed manual transfer switches catalogue pages (PDF)](https://emea.socomec.com/sites/default/files/2025-03/MANUAL-TRANSFER-ENCLOSED-SWITCHES---ENCLOSED-COMO-CS%2C-SIRCOVER%2C-SIRCO-M_CATALOGUE---PAGES_2025-03_PCG118_EN_1.pdf)
- [SIRCOVER UL 98/1008 catalogue pages (PDF)](https://www.socomec.us/sites/default/files/2025-05/SIRCOVER-UL-981008---Manually-operated-_CATALOGUE-PAGES_2025-05-14-11-25-53_DCG_English---US_C-USA_0.pdf)
- [Socomec North America 2025 general catalogue (PDF)](https://www.socomec.us/sites/default/files/2025-05/Solutions-for-power-switching-power-mon_CATALOGUE-GENERAL_2025-05-21-15-44-35_DCG192013us_English---US_C-USA.pdf)

## 14. Limits of this dossier

- Socomec changes regional catalogues, firmware and reference availability. The research date matters.
- Public Socomec pages generally use “Ask for pricing”; no dependable public global price list was found.
- Exact current, voltage, utilisation-category, short-circuit, dimension and terminal data can differ within one family. The selected reference's current technical page and certificate override this summary.
- Local electrical code, utility conditions and the engineer of record determine final suitability.
