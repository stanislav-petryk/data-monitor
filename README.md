<div align="center">
  <h1>Data monitor<h1/>
  <img src="DataMonitorIcon.png" alt="app icon" width="150"/>
</div>


I made it for me for monitoring importand for me data.

## thats display -
1. Current battery charge -       Battery: 100%
2. Max Capacity of you battery -  MaxCap: 100%
3. Temperature of you battery -   Temp: 30.0°C
4. Percent CPU in use -           CPU Load: 42%
5. Percent GPU in use -           GPU Load: 42%

mac dont give access to gpu using terminal (except apple api but its not for regular peoples) and i dont want use other apis

so for display gpu usage you will follow this guide - 

1. Create bach script for get how much GPU idle in /usr/local/bin folder -
```bash
sudo tee /usr/local/bin/gpu_idle > /dev/null <<'EOF'
#!/bin/bash
/usr/bin/powermetrics --samplers gpu_power --show-usage-summary -n 1 2>/dev/null \
  | /usr/bin/grep "GPU idle residency" | /usr/bin/head -n 1 | /usr/bin/awk '{print $4}'
EOF
```

> you can check what do that script like that
> - type sudo to terminal and add 2 rows after #!/bin/bash - thats require password
> - or you can just ask chat jpt - what it does?

2. Grant rights to this script -
```bash
sudo chown root:wheel /usr/local/bin/gpu_idle
sudo chmod 755 /usr/local/bin/gpu_idle
```
check - if give something like -rwxr-xr-x  1 root  wheel  183 Oct  7 22:58 /usr/local/bin/gpu_idle - all good
```bash
ls -l /usr/local/bin/gpu_idle
```
3. Give access to use sudo command without password -
  - type to terminal
  ```bash
  sudo visudo -f /etc/sudoers.d/gpu_idle
  ```
  - then paste that command with you username
  ```bash
  yourUsername ALL=(root) NOPASSWD: /usr/local/bin/gpu_idle
  ```
  - that press esc then type :wq and press Enter
4. Check -
type
```bash
sudo -l
```
in response should be that string
```bash
(root) NOPASSWD: /usr/local/bin/gpu_idle
```

## Congratulations! you can see your GPU load and all other data that provide!
