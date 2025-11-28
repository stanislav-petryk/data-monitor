# Data monitor

![data-monitor](https://github.com/user-attachments/assets/7ebf51b0-6d3c-4f6a-9114-91cd528e1d1e)

I made it for myself to monitor important data.

## Tech stack

- Cocoa - display window
- chrono - work with time
- cstdio - input/output
- mach - system info
- sstream - string stream
- string - string type
- thread - updating info

## How it works?

- Program take system info using mach and terminal commands
- It display to screen with Cocoa
- And refresh data like that:
  - CPU Load update every second
  - Battery, MaxCap and Temp every 3 seconds - because it changed rarely
  - GPU Load every 3 second - script that give GPU Load is slow so i make it like that

> window work like overlay so you can't click to it

## thats display

1. Current battery charge - Battery: 100%
2. Max Capacity of you battery - MaxCap: 100%
3. Temperature of you battery - Temp: 30.0°C
4. Percent CPU in use - CPU Load: 42%
5. Percent GPU in use - GPU Load: 42%

## setup GPU usage

MacOS don't give access to gpu using terminal (except apple api but its not for regular peoples) and i don't want use other apis.

So for display gpu usage you will follow this commands -

1. Run - sudo tee /usr/local/bin/gpu_idle > /dev/null <<'EOF'
   #!/bin/bash
   /usr/bin/powermetrics --samplers gpu_power --show-usage-summary -n 1 2>/dev/null \
    | /usr/bin/grep "GPU idle residency" | /usr/bin/head -n 1 | /usr/bin/awk '{print $4}'
   EOF

2. Run - sudo chown root:wheel /usr/local/bin/gpu_idle
   sudo chmod 755 /usr/local/bin/gpu_idle

3. Run - sudo visudo -f /etc/sudoers.d/gpu_idle

4. Paste that with you username - yourUsername ALL=(root) NOPASSWD: /usr/local/bin/gpu_idle

5. Press esc, type :wq and press Enter
