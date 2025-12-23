# 🧩 Developer Documentation

This document describes the internal architecture, data flow, and technical decisions behind **Data Monitor**.

---

## 🏗 Architecture Overview

Data Monitor is a native macOS application built with a minimal architecture:

- Single always-on-top overlay window
- Lightweight rendering without user interaction
- No third-party dependencies

The application prioritizes:

- Low CPU usage
- Predictable update intervals

---

## 🧠 Data Sources

System metrics are collected using a combination of:

### mach APIs

Used for:

- CPU load

### Terminal Commands

Used for:

- GPU usage (via `powermetrics`)
- Battery information

This hybrid approach avoids private Apple APIs and external libraries.

---

## ⏱ Update Strategy

Each metric has its own update interval based on how frequently it changes and how expensive it is to retrieve.

| Metric              | Interval  |
| ------------------- | --------- |
| CPU Load            | 1 second  |
| Battery Charge      | 3 seconds |
| Battery MaxCap      | 3 seconds |
| Battery Temperature | 3 seconds |
| GPU Load            | 3 seconds |

Updates are executed in background threads to avoid blocking the UI.

---

## 🪟 Overlay Window Behavior

The window:

- Is always on top
- Does not accept mouse input
- Acts as a visual overlay only

This is achieved using Cocoa window configuration (non-activating, click-through behavior).

---

## 🧵 Threading Model

- Main thread:
  - Window creation
  - UI rendering
- Background threads:
  - Periodic updates for metrics

Thread separation ensures UI responsiveness and stable refresh rates.

---

## 🎮 GPU Usage Implementation

macOS does not provide simple public APIs for retrieving GPU usage.
To avoid private APIs and third-party libraries, GPU load is calculated via `powermetrics`.

### Approach

- `powermetrics` reports **GPU idle residency**
- GPU usage is calculated as: GPU usage = 100% - GPU idle %
- A helper script (`gpu_idle`) exposes this value

### Security Considerations

- The script runs with elevated privileges
- Passwordless sudo is configured for a single, restricted command
- No additional system access is granted

See the GPU setup instructions in [`GPU setup.md`](./GPU%20setup.md)

---

## ⚠️ Limitations

- macOS only
- GPU usage depends on `powermetrics` availability
- Requires sudo configuration for GPU monitoring
- Not designed for multi-monitor layouts (by default)

---

## 🔧 Extending the Project

Possible improvements:

- Configurable refresh intervals
- Modular metric system
- Font size adjustment

---

## 📌 Design Philosophy

- Prefer native APIs over abstractions
- Avoid unnecessary dependencies
- Keep logic explicit and readable
- Optimize for clarity, not feature count
