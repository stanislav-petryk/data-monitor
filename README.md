##Data monitor detach info like battery charge, CPU load etc. to your screen

#thats display -
1. Current battery charge - Battery: 100%
2. Max Capacity of you battery - MaxCap: 100%
3. Temperature of you battery - Temp: 30.0°C
4. Percent CPU in use - CPU Load: 42%
5. Percent GPU in use - CPU Load: 42%

for display gpu usage you will follow this guide - 
1. create bach script in /usr/local/bin folder -
```bash
sudo tee /usr/local/bin/gpu_idle > /dev/null <<'EOF'
#!/bin/bash
/usr/bin/powermetrics --samplers gpu_power --show-usage-summary -n 1 2>/dev/null \
  | /usr/bin/grep "GPU idle residency" | /usr/bin/head -n 1 | /usr/bin/awk '{print $4}'
EOF
```
2. grant rights to this script -
```bash
sudo chown root:wheel /usr/local/bin/gpu_idle
sudo chmod 755 /usr/local/bin/gpu_idle
```
check - if give something like -rwxr-xr-x  1 root  wheel  183 Oct  7 22:58 /usr/local/bin/gpu_idle - all good
```bash
ls -l /usr/local/bin/gpu_idle
```
3. give access to use sudo command without password -
  - type to terminal
  ```bash
  sudo visudo -f /etc/sudoers.d/gpu_idle
  ```
  - then paste that command with you username
  ```bash
  yourUsername ALL=(root) NOPASSWD: /usr/local/bin/gpu_idle
  ```
  - that press esc then type :wq and press Enter
4. check -
type
```bash
sudo -l
```
in response should be that string
```bash
(root) NOPASSWD: /usr/local/bin/gpu_idle
```

congratulations! you can see your GPU load
