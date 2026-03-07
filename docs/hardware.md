# Hardware

## Overview

| Component | Model |
|-----------|-------|
| Board | Raspberry Pi 5 (8 GB) |
| Display | ROADOM 10.1" IPS Touchscreen |
| Speaker + Mic | Inwa USB clip-on speaker with detachable microphone |
| Power supply | iRasptek 5.1 V / 5 A USB-C (PD 27 W) |
| Cooling | Aluminium heatsink set (4 pcs, passive) |
| SD card | Kingston Canvas Select Plus 32 GB |

No case is needed — the Pi mounts directly to the back of the display. The Pi is connected via Ethernet (LAN cable) for better reliability than Wi-Fi.

## Raspberry Pi 5 (8 GB)

- **SoC:** Broadcom BCM2712, 2.4 GHz quad-core Arm Cortex-A76 (64-bit)
- **RAM:** 8 GB LPDDR4X-4267
- **GPU:** VideoCore VII — OpenGL ES 3.1, Vulkan 1.2
- **Video out:** 2 × micro-HDMI (dual 4Kp60, HDR), 4Kp60 HEVC decoder
- **Networking:** dual-band 802.11ac Wi-Fi, Bluetooth 5.0 (BLE), Gigabit Ethernet
- **USB:** 2 × USB 3.0, 2 × USB 2.0
- **Expansion:** PCIe 2.0 ×1

## ROADOM 10.1" Touchscreen

- **Resolution:** 1024 × 600 (supports up to 1920 × 1080 input)
- **Panel:** IPS, 178° viewing angle
- **Touch:** 5-point capacitive, 3–5 ms response, driver-free
- **Audio:** dual built-in speakers
- **Ports:** HDMI (signal), 2 × micro-USB (power + touch)
- **Mounting:** Pi attaches to rear standoffs — no separate case needed

The display connects via HDMI for video and micro-USB for touch input. Both screen protectors should be removed for the best touch experience.

Sources: [Amazon](https://www.amazon.com/Raspberry-ROADOM-Touchscreen-Responsive-Compatible/dp/B09XDK2FRR), [Newegg](https://www.newegg.com/waveshare-barebone-systems-mini-pc-other/p/2SW-004U-002P9)

## Inwa USB Speaker + Microphone

- **Output:** 2 × speakers + passive bass radiator, 10 W peak
- **Frequency response:** 40 Hz – 20 kHz
- **Microphone:** detachable, unidirectional, with AEC echo cancellation and one-button mute
- **Connection:** USB (USB-C and USB-A adapters included), plug-and-play
- **Mounting:** clip-on, fits monitors up to ~1.1" (28 mm) thick

The microphone is the voice input path for wake-word detection and talk mode. The speaker provides audio feedback and can replace or supplement the display's built-in speakers.

Sources: [Amazon](https://www.amazon.com/Computer-Speakers-Microphone-Desktop-Learning/dp/B0FKGP8JQX), [Inwa Audio](https://www.inwaudio.com/products/inwa-computer-speakers-for-desktop-pc-usb-monitor-speaker-bar-with-clip-on-wired-desk-speakers-with-hd-stereo-loud-sound-laptop-speaker-mini-sound-bar-easily-clamps-to-monitor)

## iRasptek Power Supply

- **Output:** 5.1 V / 5 A, USB-C, PD 27 W
- **Purpose:** official-spec power for Pi 5 (avoids under-voltage throttling)

## Aluminium Heatsink Set

- **Quantity:** 4 pieces (self-adhesive)
- **Material:** aluminium, black
- **Cooling:** passive — no fan, completely silent

Attached to the SoC, RAM, and other hot components on the Pi 5. Sufficient for passive cooling since the Pi is not under sustained heavy load (gateway + kiosk).

## Kingston Canvas Select Plus 32 GB

- **Type:** microSDHC (SDCS2/32GB)
- **Speed class:** Class 10, UHS-I (U1), V10, A1
- **Read:** up to 100 MB/s
- **Write:** up to 85 MB/s

Sources: [Kingston datasheet (PDF)](https://www.kingston.com/datasheets/SDCS2_en.pdf), [Kingston product page](https://www.kingston.com/en/memory-cards/canvas-select-plus-sd-card)
