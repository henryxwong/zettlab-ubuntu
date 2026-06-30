# RGB LED Control Protocol

## Device Info

| Field | Value |
|-------|-------|
| **Device** | ZettLab ZettOS_RGB |
| **USB VID:PID** | `0x5759:0x4358` |
| **Kernel Node** | `/dev/ttyACM0` |
| **Driver** | `cdc_acm` |
| **USB Class** | CDC ACM (Communications) |
| **Speed** | USB 2.0 Full Speed (12 Mbps) |

### Endpoints

| Endpoint | Type | Max Packet | Interval | Direction |
|----------|------|------------|----------|-----------|
| 0x83 | Interrupt | 16 bytes | 1ms | IN (notification) |
| 0x02 | Bulk | 32 bytes | — | OUT (write) |
| 0x01 | Bulk | 64 bytes | — | IN (read) |

## Protocol Specification

The device presents as a standard CDC ACM serial port. It accepts write-only commands — no responses are returned.

**Connection parameters:**
- Baud rate: 115200
- Data bits: 8, Stop bits: 1, Parity: None (8N1)
- No flow control or handshake

### Command Frame Format (11 bytes)

```
Offset  Size  Value                          Description
------  ----  ----------------------------   -----------
0       2     0xFF, 0xFF (little-endian)    Header constant
2       1     mode (0-6)                     Animation mode
3       1     startR                         Start color red
4       1     startG                         Start color green
5       1     startB                         Start color blue
6       1     endR                           End color red
7       1     endG                           End color green
8       1     endB                           End color blue
9       1     -(speed) & 0xFF                Speed (negated, two's complement)
10      1     CRC8                           Checksum over bytes 2-9
```

### Frame Assembly

1. Write 2-byte header: `0xFF 0xFF`
2. Append 8 bytes of payload: `[mode, startR, startG, startB, endR, endG, endB, -(speed)]`
3. Append 1-byte CRC8: computed over payload bytes only (offsets 2-9, **not** the header)

### CRC8 Computation

CRC8 using polynomial 0x07 (CRC-8/SAE J1850). The checksum is computed over **payload bytes only** (bytes 2-9):

```
crc = 0
for each byte b in payload:
    crc = crc8_table[crc ^ b]
```

### Parameter Mapping

| Byte | Meaning | Valid Range |
|------|---------|-------------|
| 2 | Mode | 0-6 |
| 3 | Start R | 0-255 |
| 4 | Start G | 0-255 |
| 5 | Start B | 0-255 |
| 6 | End R | 0-255 |
| 7 | End G | 0-255 |
| 8 | End B | 0-255 |
| 9 | Speed (negated) | 0–255 |

### Light Modes

| Value | Mode | Description |
|-------|------|-------------|
| 0 | OFF_MODE | LEDs off |
| 1 | BREATHE_MODE | Breathing/pulsing effect |
| 2 | FLOW_MODE | Color flow |
| 3 | FOUNTAIN_MODE | Fountain effect |
| 4 | GRADIENT_MODE | Color gradient |
| 5 | FLICKER_MODE | Flicker effect |
| 6 | LIGHT_MODE | Static/solid color |

## Brightness Control

**No dedicated brightness field exists.** The protocol only accepts: `mode`, `startR/G/B`, `endR/G/B`, and `speed`. RGB values are sent as raw 8-bit bytes (0x00 = off, 0xFF = max).

**Dimming workaround:** Send lower RGB values to reduce brightness. Note: this also affects color saturation (e.g., `0x80` instead of `0xFF` gives a dimmer, less saturated color). Pure intensity-only dimming is not supported by the protocol.

## Python Control Script

A standalone Python script is provided at `rgb_control.py`. It implements the full protocol (frame assembly, CRC8 computation, serial communication).

### Requirements

- **Python 3.6+** (uses `bytes` literals and f-strings)
- **No external dependencies** — uses only stdlib modules: `sys`, `os`, `termios`
- **Group access** — user must be in the `dialout` group: `sudo usermod -aG dialout $USER` (requires re-login)

### Usage

```bash
# Solid red (mode 6, full brightness)
python3 rgb_control.py 6

# Solid blue
python3 rgb_control.py 6 0 0 255 0 0 255 5

# Green breathing effect
python3 rgb_control.py 1 0 255 0 0 0 0 3

# Red-to-blue gradient
python3 rgb_control.py 4 255 0 0 0 0 255 10

# Turn off LEDs
python3 rgb_control.py 0

# Dim white (lower RGB values = dimmer)
python3 rgb_control.py 6 128 128 128 128 128 128 5
```

**Syntax:** `python3 rgb_control.py <mode> [start_r start_g start_b end_r end_g end_b speed]`

If color/speed args are omitted, defaults to: solid red (`255,0,0`), speed `5`.

### Parameters

| Arg | Description | Range |
|-----|-------------|-------|
| `mode` | Animation mode (required) | 0-6 |
| `start_r,g,b` | Starting color | 0-255 |
| `end_r,g,b` | Ending color | 0-255 |
| `speed` | Animation speed (higher = faster, 0 wraps to max) | 0–255 |

### Modes

| Mode | Name |
|------|------|
| 0 | OFF (LEDs off) |
| 1 | BREATHE (pulsing) |
| 2 | FLOW (color flow) |
| 3 | FOUNTAIN |
| 4 | GRADIENT (start to end color) |
| 5 | FLICKER |
| 6 | LIGHT (solid color) |

### Source Code

See `rgb_control.py` for the full implementation.
