# 📊 Data Monitor

![data-monitor](https://github.com/user-attachments/assets/7ebf51b0-6d3c-4f6a-9114-91cd528e1d1e)

**Data Monitor** is a lightweight macOS overlay application for real-time monitoring of essential system metrics.
Designed for personal use with minimal overhead and an always-visible, non-intrusive UI.

## 🎥 Demo

![Data monitor demo](https://github.com/user-attachments/assets/37c042f8-9c8c-4638-82f4-650478af406f)

## ✨ Features

- Always-on-top overlay window
- Click-through (non-interactive) UI
- Real-time system metrics
- Optimized update intervals for low resource usage

## 📈 Displayed Metrics

1. Battery charge — `Battery: 100%`
2. Battery maximum capacity — `MaxCap: 100%`
3. Battery temperature — `Temp: 30.0°C`
4. CPU usage — `CPU Load: 42%`
5. GPU usage — `GPU Load: 42%`

> The window works as an overlay and does not receive mouse input.

## 🛠 Tech Stack

- **Cocoa** — window rendering and UI
- **mach** — low-level system information
- **chrono** — time handling
- **thread** — periodic data updates
- **cstdio** — input/output
- **sstream** — string streams
- **string** — string handling

## 💻 Platform

- macOS only

## 📚 Developer Documentation

Implementation details, update logic, and GPU usage setup are documented in
[`DEV documentation.md`](./docs/DEV%20documentation.md)
