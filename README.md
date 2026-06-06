# SPI Master Controller – All 4 Modes

A fully verified SPI Master Controller implemented in Verilog, supporting all four SPI modes (Mode 0, 1, 2, 3). Simulated and tested in Xilinx Vivado XSim with a self-checking testbench that runs all modes automatically.

---

## Table of Contents

- [Overview](#overview)
- [SPI Modes](#spi-modes)
- [Port Description](#port-description)
- [FSM Architecture](#fsm-architecture)
- [Timing Diagrams](#timing-diagrams)
- [File Structure](#file-structure)
- [Simulation Results](#simulation-results)
- [How to Run in Vivado](#how-to-run-in-vivado)
- [Key Design Decisions](#key-design-decisions)

---

## Overview

The Serial Peripheral Interface (SPI) is a synchronous serial communication protocol widely used between microcontrollers and peripheral devices (ADCs, DACs, sensors, flash memory, displays).

This project implements a **parameterized SPI Master** that supports:
- All 4 SPI modes via a single `MODE[1:0]` parameter
- MSB-first 8-bit transfers
- Active-low chip select (`cs_n`)
- Self-checking testbench with 4 DUT instances (one per mode) running in parallel

---

## SPI Modes

SPI mode is defined by two bits:

| MODE | CPOL | CPHA | SCLK Idle | Sample Edge      | Shift Edge       |
|------|------|------|-----------|------------------|------------------|
| 0    | 0    | 0    | LOW       | Rising (leading) | Falling (trailing)|
| 1    | 0    | 1    | LOW       | Falling (trailing)| Rising (leading) |
| 2    | 1    | 0    | HIGH      | Falling (leading)| Rising (trailing)|
| 3    | 1    | 1    | HIGH      | Rising (trailing)| Falling (leading)|

- **CPOL** (Clock Polarity): defines the idle level of SCLK
- **CPHA** (Clock Phase): defines which edge is used to sample data

---

## Port Description

| Port       | Direction | Width | Description                        |
|------------|-----------|-------|------------------------------------|
| `clk`      | input     | 1     | System clock                       |
| `rst_n`    | input     | 1     | Active-low synchronous reset       |
| `start`    | input     | 1     | Pulse high for one clock to begin  |
| `tx_data`  | input     | 8     | Byte to transmit (MSB first)       |
| `rx_data`  | output    | 8     | Byte received from slave           |
| `busy`     | output    | 1     | High during active transfer        |
| `done`     | output    | 1     | One-cycle pulse when transfer ends |
| `sclk`     | output    | 1     | SPI clock to slave                 |
| `mosi`     | output    | 1     | Master Out Slave In                |
| `miso`     | input     | 1     | Master In Slave Out                |
| `cs_n`     | output    | 1     | Chip Select (active low)           |

---

## FSM Architecture

The controller uses a 6-state FSM. CPHA=0 and CPHA=1 share the same states but take different paths through them.

```
                        ┌─────────────────────────────────────────────┐
                        │                                             │
              start=1   │                                    bit_cnt<7│
   ┌──────┐  ────────►  ┌───────┐  ──────►  ┌──────┐        ┌───────┐│
   │      │             │       │            │      │        │       ││
   │ IDLE │             │ SETUP │            │ LEAD │──────► │ TRAIL ││
   │      │ ◄────────── │       │            │      │        │       ││
   └──────┘  done=1     └───────┘            └──────┘        └───────┘│
                                               │  ▲              │    │
                                  (CPHA=1 only)│  │              │bit_cnt=7
                                               ▼  │              │    │
                                            ┌──────┐             │    │
                                            │      │             ▼    │
                                            │ HOLD │          ┌──────┐│
                                            │      │          │ IDLE ││
                                            └──────┘          └──────┘│
                                                                       │
                                                                       └──(CPHA=0 only, last bit)
```

### State Descriptions

| State | SCLK Level | Action |
|-------|-----------|--------|
| **IDLE** | `cpol` (idle) | Wait for `start`. Pre-drive MOSI bit[7] if CPHA=0 |
| **SETUP** | `cpol` (idle) | CS goes low. One clock for MISO/MOSI to settle |
| **LEAD** | `~cpol` (active) | Leading edge asserted. CPHA=0: sample MISO. CPHA=1: drive MOSI |
| **HOLD** | `~cpol` (active) | CPHA=1 only. Hold leading level one extra clock so slave can update MISO |
| **TRAIL** | `cpol` (idle) | Trailing edge. CPHA=0: drive next MOSI. CPHA=1: sample MISO |
| **IDLE** | `cpol` (idle) | After bit 7: assert `done`, deassert CS, return to idle |

### CPHA=0 Path (Modes 0, 2)
```
IDLE → SETUP → LEAD(sample) → TRAIL(shift) → LEAD → TRAIL → ... [×8] → IDLE
```

### CPHA=1 Path (Modes 1, 3)
```
IDLE → SETUP → LEAD(drive) → HOLD → TRAIL(sample) → LEAD → ... [×8] → IDLE
```

> The `HOLD` state is the key fix for CPHA=1: the slave updates MISO on the same
> system clock that the master detects the leading edge. Without HOLD, the master
> would sample the old MISO value (off-by-one bit error).

---

## Timing Diagrams

### Mode 0 (CPOL=0, CPHA=0)
```
CS_N   ‾‾‾‾|_________________________________|‾‾‾‾
SCLK   ______|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|______
MOSI   ──────[7][6][5][4][3][2][1][0]─────────────  (shifted on falling)
MISO   ──────[7][6][5][4][3][2][1][0]─────────────  (sampled on rising)
             ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑   sample points
```

### Mode 1 (CPOL=0, CPHA=1)
```
CS_N   ‾‾‾‾|_________________________________|‾‾‾‾
SCLK   ______|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|______
MOSI   ────[7][6][5][4][3][2][1][0]───────────────  (shifted on rising)
MISO   ──────[7][6][5][4][3][2][1][0]─────────────  (sampled on falling)
               ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓   sample points
```

### Mode 2 (CPOL=1, CPHA=0)
```
CS_N   ‾‾‾‾|_________________________________|‾‾‾‾
SCLK   ‾‾‾‾‾‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾‾‾‾‾‾
MOSI   ──────[7][6][5][4][3][2][1][0]─────────────  (shifted on rising)
MISO   ──────[7][6][5][4][3][2][1][0]─────────────  (sampled on falling)
             ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓   sample points
```

### Mode 3 (CPOL=1, CPHA=1)
```
CS_N   ‾‾‾‾|_________________________________|‾‾‾‾
SCLK   ‾‾‾‾‾‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾‾‾‾‾‾
MOSI   ────[7][6][5][4][3][2][1][0]───────────────  (shifted on falling)
MISO   ──────[7][6][5][4][3][2][1][0]─────────────  (sampled on rising)
               ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑   sample points
```

---

## File Structure

```
SPI_master_all_modes/
│
├── src/
│   └── spi_controller_all_modes.v   # SPI Master RTL (parameterized)
│
├── sim/
│   └── tb_spi_all_modes.v           # Self-checking testbench (all 4 modes)
│
└── README.md
```

---

## Simulation Results

Tested in Xilinx Vivado 2023 XSim (Behavioral Simulation):

```
--- Mode 0 (CPOL=0 CPHA=0) ---
  Mode0  TX=a5  RX=a5  PASS
  Mode0  TX=5a  RX=5a  PASS
  Mode0  TX=ff  RX=ff  PASS
  Mode0  TX=00  RX=00  PASS
--- Mode 1 (CPOL=0 CPHA=1) ---
  Mode1  TX=a5  RX=a5  PASS
  Mode1  TX=5a  RX=5a  PASS
  Mode1  TX=ff  RX=ff  PASS
  Mode1  TX=00  RX=00  PASS
--- Mode 2 (CPOL=1 CPHA=0) ---
  Mode2  TX=a5  RX=a5  PASS
  Mode2  TX=5a  RX=5a  PASS
  Mode2  TX=ff  RX=ff  PASS
  Mode2  TX=00  RX=00  PASS
--- Mode 3 (CPOL=1 CPHA=1) ---
  Mode3  TX=a5  RX=a5  PASS
  Mode3  TX=5a  RX=5a  PASS
  Mode3  TX=ff  RX=ff  PASS
  Mode3  TX=00  RX=00  PASS
================================
TOTAL: 16 PASS, 0 FAIL
================================
```

---

## How to Run in Vivado

1. Open Vivado and create a new RTL project
2. Add `src/spi_controller_all_modes.v` as a Design Source
3. Add `sim/tb_spi_all_modes.v` as a Simulation Source
4. Set `tb_spi_all_modes` as the top simulation module
5. Go to **Flow → Settings → Simulation** and set **Simulation Run Time** to `50us`
6. Click **Run Simulation → Run Behavioral Simulation**
7. Click the **Run All (▶▶)** button or type `run all` in the Tcl console

---

## Key Design Decisions

**Why a SETUP state?**
A one-clock SETUP state between CS assertion and the first SCLK edge gives the slave time to load its shift register and drive MISO[7] before the master samples it. This mirrors the real-world CS-to-SCLK setup time (t_CSS) required by SPI slave datasheets.

**Why a HOLD state for CPHA=1?**
For CPHA=1 the slave drives MISO on the leading edge — but in a synchronous simulation both the master and slave react to the same edge in the same clock cycle. Without HOLD, the master would sample the old MISO (causing a 1-bit right shift in received data). The HOLD state gives the slave one extra system clock to update MISO before the master samples on the trailing edge.

**Why a system-clock-based slave in the testbench?**
Using `always @(posedge sclk)` in the testbench causes delta-cycle races in Vivado XSim because `sclk` is itself driven by a non-blocking assignment inside a `posedge clk` block. The slave instead uses edge detection (`sclk_prev`) inside a `posedge clk` block, eliminating all races.

---

## License

MIT License — free to use, modify, and distribute.
