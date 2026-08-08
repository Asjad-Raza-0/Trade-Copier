# 🤖 Claude Developer Handbook & Reference Guide (CLAUDE.md)

This handbook provides a structured reference for Claude AI agents working on the **Gold Trade Copier** project repository.

---

## 🛠️ Project Design Tokens & Anthropic Editorial Aesthetic

The Web Dashboard follows the **Anthropic / Claude Editorial Theme**:

- **Warm Cream Canvas**: `#faf9f5` (Light Mode) / `#0e0d0c` (Obsidian Dark Mode)
- **Signature Accent**: `#cc785c` (Warm Coral)
- **Text Color**: `#141413` (Ink) / `#f3efe6` (Warm Parchment)
- **Card Surfaces**: `#efe9de` (Light Cream Card) / `#181715` (Dark Slate Card)
- **Typography**: `Cormorant Garamond` (Serif Display Headlines), `Inter` (Humanist Body), `JetBrains Mono` (Code & Terminal)

---

## ⚙️ Core Architecture & Codebase Map

```text
C:\Main Project\gold-trade-copier/
├── index.html                   # Command Center Dashboard (Page 1)
├── settings.html                # VPS Credentials & Health Tester (Page 2)
├── analytics.html               # Trade Analytics & History (Page 3)
├── config.js                    # Central System Settings & Security
├── functions/
│   └── api/
│       └── [[path]].js          # Cloudflare Pages Function (HTTPS API Proxy)
├── dashboard/                   # Synchronized Web Dashboard Source Directory
│   ├── index.html
│   ├── settings.html
│   ├── analytics.html
│   ├── config.js
│   └── functions/api/[[path]].js
├── gold-trade-copier/
│   ├── relay_server.py          # Python Master VPS Relay Server (Flask + SQLite)
│   ├── GoldMasterRelay.mq5      # Master MT5 EA (Captures & Pushes Trades)
│   ├── GoldSlaveRelay.mq5       # Slave MT5 EA (Polls & Executes Trades)
│   ├── SETUP_GUIDE.md           # Step-by-Step Installation Manual
│   ├── supabase_schema.sql      # Supabase Cloud Database SQL Schema
│   └── requirements.txt         # Python Dependencies (Flask, requests, supabase)
├── Telegram Notifier/
│   ├── TelegramNotifier.mq5     # Optional Telegram Trade Alerts EA
│   └── SETUP_GUIDE.md
└── GEMINI.md                    # Detailed System Architecture & Troubleshooting Guide
```

---

## 🔐 Security & Admin PIN Authentication Rules

- **Default Passcode**: `7890` *(configured in `config.js`)*.
- **Sensitive Operations Protection**:
  - `triggerEmergencyKill()`: Requires `requireAdminAuth()` validation.
  - `postCommand()`: Requires `requireAdminAuth()` validation.
  - `saveAllSettings()`: Requires `requireAdminAuth()` validation.
- **Session Auth Persistence**: Authenticated status stored in `sessionStorage.getItem('ADMIN_AUTH')`.

---

## 🐞 Common Bugs & Resolution Directory

### 1. Mixed Content CORS Block (`TypeError: Failed to fetch`)
- **Fix**: Never issue direct browser `fetch()` to `http://YOUR_VPS_IP:8765` from HTTPS pages. Route through `/api/dashboard-summary` which triggers the Cloudflare Edge Proxy.

### 2. Cloudflare Submodule Build Failure (`error occurred while updating repository submodules`)
- **Fix**: Remove Git submodule pointer from git cache: `git rm --cached gold-trade-copier`. Ensure all files are tracked as regular mode `100644`.

### 3. Master VPS Offline / HTTP 502
- **Fix**: Verify `python relay_server.py` is running on Master VPS and firewall port 8765 is open (`sudo ufw allow 8765/tcp` or AWS Inbound Rule).

---

## 🚀 GitHub Push Checklist

Before pushing to GitHub:

1. **Verify No Submodules**: `git ls-files -s | Select-String "160000"` (Must output empty).
2. **Sync Dashboard Files**: Ensure `/index.html`, `/settings.html`, `/analytics.html`, `/config.js` match `dashboard/`.
3. **Commit & Push**:
   ```bash
   git add .
   git commit -m "Update dashboard features"
   git push origin main
   ```
