# OpenClaw VM Deployment Template

Quick-reference for deploying OpenClaw on a fresh Ubuntu VM with Ollama backend.

## Prerequisites

- Proxmox host with Ollama running (default: port 11434)
- Ubuntu 24.04 cloud image downloaded
- SSH keys configured on Proxmox host

---

## 1. Create VM on Proxmox (run from pve shell)

```bash
# Download image (if not already present)
wget -O /var/lib/vz/template/iso/ubuntu-24.04-cloudimg.qcow2 \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Create VM (adjust ID, name, specs as needed)
/usr/sbin/qm create 102 \
  --name "openclaw-vm" \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --bootdisk scsi0 \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1

# Import disk
/usr/sbin/qm importdisk 102 /var/lib/vz/template/iso/ubuntu-24.04-cloudimg.qcow2 local --format qcow2

# Attach disk and configure
/usr/sbin/qm set 102 --scsi0 local:102/vm-102-disk-0.qcow2
/usr/sbin/qm set 102 --ciuser fahmy
/usr/sbin/qm set 102 --sshkeys /root/.ssh/authorized_keys
/usr/sbin/qm set 102 --ipconfig0 ip=dhcp
/usr/sbin/qm set 102 --ide2 local:cloudinit
/usr/sbin/qm set 102 --boot order=scsi0

# IMPORTANT: Resize disk BEFORE first boot (cloud image is small)
/usr/sbin/qm resize 102 scsi0 20G

# Start VM
/usr/sbin/qm start 102

# Wait ~30s for cloud-init, then find IP
cat /var/lib/misc/dnsmasq.leases | grep -i <MAC-ADDRESS>
# OR
ip neigh show | grep -i <MAC-ADDRESS>
```

---

## 2. Install OpenClaw (run on VM)

```bash
# SSH into VM
ssh fahmy<@VM_IP>

# Install Node.js (Ubuntu 24.04)
sudo apt update && sudo apt install -y nodejs npm
sudo npm install -g npm@latest

# Install OpenClaw
sudo npm install -g openclaw

# Verify
openclaw --version
```

---

## 3. Create Config File

**Location:** `~/.openclaw/openclaw.json` (JSON5 format)

```json5
{
  "env": {
    "OLLAMA_API_KEY": "ollama-local"
  },
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://<OLLAMA_HOST_IP>:11434",
        "apiKey": "ollama-local",
        "models": [
          {
            "id": "<MODEL_NAME>",
            "name": "<MODEL_DISPLAY_NAME>"
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/<MODEL_NAME>"
      },
      "workspace": "~/.openclaw/workspace"
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "botToken": "<YOUR_BOT_TOKEN>",
      "allowFrom": [
        "tg:<YOUR_TELEGRAM_ID>"
      ],
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "auth": {
      "token": "<YOUR_TOKEN>"
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  }
}
```

### Key Config Notes

| Setting | Value | Notes |
|---------|-------|-------|
| `baseUrl` | `http://<HOST_IP>:11434` | Use host IP, NOT `localhost` or `host.docker.internal` |
| `apiKey` | `"ollama-local"` | Required even for local Ollama |
| `env.OLLAMA_API_KEY` | `"ollama-local"` | Must match apiKey |
| Model `id` | Model name exactly as in Ollama | Run `ollama list` on host to verify |
| Config path | `~/.openclaw/openclaw.json` | NOT `/etc/openclaw/config.yaml` |

---

## 4. Create Systemd Service

**File:** `/etc/systemd/system/openclaw.service`

```ini
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=<USERNAME>
Group=<USERNAME>
WorkingDirectory=/home/<USERNAME>
ExecStart=/usr/bin/openclaw gateway run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### ⚠️ Critical: User Must Match Config Location

```bash
# If config is at /home/fahmy/.openclaw/openclaw.json
# Then User=fahmy in systemd service

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw

# Check status
sudo systemctl status openclaw
```

---

## 5. Verify

```bash
# Check service
sudo systemctl status openclaw

# Check logs
journalctl -u openclaw -f

# Test dashboard
curl http://localhost:18789/

# Check config is loaded
openclaw config get gateway.mode
# Should output: "local"
```

---

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| "Missing config" | Service user ≠ config owner | Set `User=<username>` in systemd to match `~/.openclaw/` owner |
| "No API key found" | Missing apiKey for Ollama | Add `apiKey: "ollama-local"` and `env.OLLAMA_API_KEY` |
| "Config path not found" | Wrong config location | Use `~/.openclaw/openclaw.json`, not `/etc/openclaw/` |
| Model not found | Wrong model name | Run `ollama list` on host, use exact name as `id` |
| Can't reach Ollama | Wrong host IP | Use Proxmox host IP (e.g., `192.168.178.38`), not `localhost` |

---

## Current Working Setup (Feb 2026)

| Component | Value |
|-----------|-------|
| VM IP | 192.168.178.110 |
| VM User | fahmy |
| Ollama Host | 192.168.178.38:11434 |
| Model | kimi-k2.5:cloud |
| Dashboard | http://192.168.178.110:18789/ |
| Bot | @Oberwart2Bot |

---

## Quick Deploy Script

For future deployments, you can create a script:

```bash
#!/bin/bash
# save as: deploy-openclaw.sh

VM_IP="<NEW_VM_IP>"
OLLAMA_IP="<OLLAMA_HOST_IP>"
MODEL="<MODEL_NAME>"
BOT_TOKEN="<BOT_TOKEN>"
TELEGRAM_ID="<YOUR_TG_ID>"

# Install OpenClaw
ssh fahmy@$VM_IP 'sudo apt update && sudo apt install -y nodejs npm'
ssh fahmy@$VM_IP 'sudo npm install -g npm@latest openclaw'

# Create config directory
ssh fahmy@$VM_IP 'mkdir -p ~/.openclaw/workspace'

# Create config (use heredoc)
ssh fahmy@$VM_IP "cat > ~/.openclaw/openclaw.json" <<EOF
{
  "env": { "OLLAMA_API_KEY": "ollama-local" },
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://${OLLAMA_IP}:11434",
        "apiKey": "ollama-local",
        "models": [{ "id": "${MODEL}", "name": "${MODEL}" }]
      }
    }
  },
  "agents": { "defaults": { "model": { "primary": "ollama/${MODEL}" }, "workspace": "~/.openclaw/workspace" } },
  "commands": { "native": "auto", "nativeSkills": "auto" },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "botToken": "${BOT_TOKEN}",
      "allowFrom": ["tg:${TELEGRAM_ID}"],
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  },
  "gateway": { "port": 18789, "mode": "local", "auth": { "token": "openclaw-$(date +%s)" } },
  "plugins": { "entries": { "telegram": { "enabled": true } } }
}
EOF

# Create systemd service
ssh fahmy@$VM_IP 'sudo tee /etc/systemd/system/openclaw.service' <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=fahmy
Group=fahmy
WorkingDirectory=/home/fahmy
ExecStart=/usr/bin/openclaw gateway run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
ssh fahmy@$VM_IP 'sudo systemctl daemon-reload && sudo systemctl enable --now openclaw'

echo "Deployed! Dashboard: http://${VM_IP}:18789/"
```

---

*Last updated: 2026-02-19*