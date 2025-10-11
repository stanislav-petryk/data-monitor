# Data monitor

I made it for myself to monitor important data.

## thats display -

1. Current battery charge - Battery: 100%
2. Max Capacity of you battery - MaxCap: 100%
3. Temperature of you battery - Temp: 30.0°C
4. Percent CPU in use - CPU Load: 42%
5. Percent GPU in use - GPU Load: 42%

MacOS don't give access to gpu using terminal (except apple api but its not for regular peoples) and i don't want use other apis.

So for display gpu usage you will follow this guide -

1. Create bach script for get how much GPU idle in /usr/local/bin folder:

```bash
sudo tee /usr/local/bin/gpu_idle > /dev/null <<'EOF'
#!/bin/bash
/usr/bin/powermetrics --samplers gpu_power --show-usage-summary -n 1 2>/dev/null \
  | /usr/bin/grep "GPU idle residency" | /usr/bin/head -n 1 | /usr/bin/awk '{print $4}'
EOF
```

> This script runs powermetrics to get GPU idle residency and outputs only the percentage value.

2. Make the script executable:

```bash
sudo chown root:wheel /usr/local/bin/gpu_idle
sudo chmod 755 /usr/local/bin/gpu_idle
```

3. check:

type:

```bash
ls -l /usr/local/bin/gpu_idle
```

if give something like -rwxr-xr-x 1 root wheel 183 Oct 7 22:58 /usr/local/bin/gpu_idle - all good.

4. Give access to use sudo in script without password:

- type to terminal:

```bash
sudo visudo -f /etc/sudoers.d/gpu_idle
```

- then paste that command with you username:

```bash
yourUsername ALL=(root) NOPASSWD: /usr/local/bin/gpu_idle
```

- that press esc then type :wq and press Enter.

5. Check:

- type:

```bash
sudo -l
```

in response should be that string:

```bash
(root) NOPASSWD: /usr/local/bin/gpu_idle
```

## Congratulations! you can see your GPU load and all other data that provide
