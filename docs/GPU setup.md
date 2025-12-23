# 🎮 GPU Usage Setup (macOS)

This document describes how to enable GPU usage monitoring for **Data Monitor** on macOS.

macOS does not provide a public, lightweight API for retrieving GPU usage.
To avoid private Apple APIs and third-party libraries, GPU load is derived using `powermetrics`.

---

## ⚠️ Requirements

- macOS
- Administrator privileges
- `powermetrics` available (built-in on macOS)

---

## 🧠 How It Works

- `powermetrics` reports **GPU idle residency**
- GPU usage is calculated as: GPU usage = 100% - GPU idle percentage
- A helper script exposes the idle value for use in the application

---

## 🛠 Setup Steps

### 1. Create helper script

```shell
sudo tee /usr/local/bin/gpu_idle > /dev/null <<'EOF'
#!/bin/bash
/usr/bin/powermetrics --samplers gpu_power --show-usage-summary -n 1 2>/dev/null \
| /usr/bin/grep "GPU idle residency" \
| /usr/bin/head -n 1 \
| /usr/bin/awk '{print $4}'
EOF
```

### 2. Set permissions

```shell
sudo chown root:wheel /usr/local/bin/gpu_idle
sudo chmod 755 /usr/local/bin/gpu_idle
```

### 3. Allow passwordless execution

Edit sudoers file:

```shell
sudo visudo -f /etc/sudoers.d/gpu_idle
```

Add the following line (replace yourUsername with your macOS username):

```shell
yourUsername ALL=(root) NOPASSWD: /usr/local/bin/gpu_idle
```

Save and exit:

- Press Esc
- Type :wq
- Press Enter

## ✅ Verify

Run:

```shell
sudo /usr/local/bin/gpu_idle
```

Expected output is any number

(Value represents GPU idle percentage.)

## 🔐 Security Notes

- Only a single command is allowed to run with sudo
- No shell access or wildcards are permitted
- The script is owned by root and not writable by users

## ❗ Troubleshooting

Ensure powermetrics is available:

```shell
which powermetrics
```

- Make sure the sudoers entry has no syntax errors
- GPU usage may return 0 or something near when the GPU is idle

## 📌 Notes

- This setup is optional
- Without it, GPU usage will not be displayed
- CPU and battery metrics work independently
