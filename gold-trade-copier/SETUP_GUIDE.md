# 🚀 Gold Trade Copier — Complete Beginner-Friendly Setup Guide

Welcome! This guide is written so **anyone (even an 18-year-old student setting this up for the first time)** can set up the Master VPS relay server, connect Supabase Cloud database persistence, attach MT5 EAs, and deploy the Web Dashboard to Cloudflare Pages in less than 20 minutes!

---

-This project is deployed in cloudflare workers, under "https://trade-copier.asjadraza.workers.dev/"

## 📌 Master Setup Reference Quick Sheet

| Resource | Value / Setting |
|---|---|
| **Master VPS Public IP** | `3.11.8.205` |
| **Relay Port** | `8765` |
| **Default Master API Key** | `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd` |
| **Slave VPS #1 IP** | `18.133.194.160` |
| **Slave VPS #2 IP** | `35.178.131.14` |
| **Dashboard URL** | `https://your-dashboard.pages.dev` (Cloudflare Pages) |

---

## 🧭 Table of Contents

1. [Architecture & How Everything Works](#1-architecture--how-everything-works)
2. [Step 1: Set Up Supabase Cloud Database (3 Minutes)](#step-1-set-up-supabase-cloud-database-3-minutes)
3. [Step 2: Set Up Master VPS & Relay Server (5 Minutes)](#step-2-set-up-master-vps--relay-server-5-minutes)
4. [Step 3: Attach Master EA to MT5 (2 Minutes)](#step-3-attach-master-ea-to-mt5-2-minutes)
5. [Step 4: Attach Slave EA to Slave VPS MT5 (3 Minutes)](#step-4-attach-slave-ea-to-slave-vps-mt5-3-minutes)
6. [Step 5: Deploy Web Dashboard to Cloudflare Pages (4 Minutes)](#step-5-deploy-web-dashboard-to-cloudflare-pages-4-minutes)
7. [Remote Controls & Web Dashboard Usage Guide](#remote-controls--web-dashboard-usage-guide)
8. [Troubleshooting & Quick Fixes](#troubleshooting--quick-fixes)

---

## 1. Architecture & How Everything Works

Here is how trades and web control commands flow through your system:

```
                              ┌───────────────────────────────────┐
                              │     SUPABASE CLOUD POSTGRESQL     │
                              │  (Permanent Trade Events & P&L)   │
                              └─────────────────▲─────────────────┘
                                                │ (Realtime Sync)
 ┌──────────────────────────────────────────────┴──────────────────────────────────────────────┐
 │                                 MASTER VPS (3.11.8.205)                                 │
 │                                                                                             │
 │  [Master MT5 Account]  ─────(POST /trade)────>  [Relay Server]  <───(CORS / API)────┐       │
 │  (GoldMasterRelay.mq5)                          (relay_server.py)                   │       │
 └──────────────────────────────────────────────────────┬──────────────────────────────┼───────┘
                                                        │                              │
                     ┌──────────────────────────────────┼──────────────────┐           │
                     │ (1s Poll + Command)              │ (1s Poll)        │ (1s Poll) │
                     ▼                                  ▼                  ▼           │
        ┌──────────────────────────┐       ┌──────────────────┐ ┌──────────────────┐    │
        │       SLAVE VPS #1       │       │   SLAVE VPS #2   │ │   SLAVE VPS #N   │    │
        │ (GoldSlaveRelay.mq5 v2.10│       │(GoldSlaveRelay)  │ │(GoldSlaveRelay)  │    │
        └──────────────────────────┘       └──────────────────┘ └──────────────────┘    │
                                                                                       │
 ┌─────────────────────────────────────────────────────────────────────────────────────┴───────┐
 │                       CLOUDFLARE PAGES WEB DASHBOARD (https://...)                          │
 │ - Anthropic/Claude Design Theme (#faf9f5 Cream Canvas, #cc785c Coral Accent, #181715 Navy) │
 │ - View live open positions, connected slave heartbeats, and trigger Emergency Kill Switch   │
 └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Set Up Supabase Cloud Database (3 Minutes)

Supabase gives you **free Cloud PostgreSQL database storage** so your trade history and P&L analytics are permanently saved.

1. **Create Account**: Go to **[https://supabase.com](https://supabase.com)** and sign up for a free account.
2. **Create New Project**: Click **New Project** $\rightarrow$ Give it a name (e.g. `GoldTradeCopier`) $\rightarrow$ Create strong database password $\rightarrow$ Click **Create New Project**.
3. **Run Database Schema**:
   - On the left sidebar of Supabase, click **SQL Editor** ($\langle/\rangle$).
   - Open the file [`supabase_schema.sql`](file:///C:/Main%20Project/gold-trade-copier/gold-trade-copier/supabase_schema.sql) from your project folder in Notepad or VS Code.
   - Copy all SQL code from [`supabase_schema.sql`](file:///C:/Main%20Project/gold-trade-copier/gold-trade-copier/supabase_schema.sql) and paste it into the Supabase SQL Editor.
   - Click the green **Run** button at the bottom right. You will see `Success. No rows returned.` 🎉
4. **Get Project URL & Anon Key**:
   - Go to **Project Settings** (gear icon at bottom left) $\rightarrow$ Click **API**.
   - Copy **Project URL** (e.g. `https://xyzproject.supabase.co`).
   - Copy **anon / public key** (e.g. `eyJhbGciOiJIUzI1NiIsInR5...`).
   - Save these two values! You will paste them into your Master VPS and Web Dashboard.

---

## Step 2: Set Up Master VPS & Relay Server (5 Minutes)

The Relay Server runs on your **Master VPS** (`3.11.8.205`) 24/7 as a background Windows Service.

### 1. Copy Files to Master VPS
Log into your Master VPS (`3.11.8.205`) via Remote Desktop (RDP) and create folder `C:\GoldRelay\`.
Copy these files into `C:\GoldRelay\`:
- `relay_server.py`
- `requirements.txt`

### 2. Install Python Dependencies
Open **Command Prompt** in `C:\GoldRelay\` and run:
```cmd
pip install -r requirements.txt
```

### 3. Set Supabase Environment Variables
In the same Command Prompt, set your Supabase URL and Key so the server can push trade events to the cloud:
```cmd
setx SUPABASE_URL "https://your-project.supabase.co" /M
setx SUPABASE_KEY "your-supabase-anon-key" /M
```

### 4. Install 24/7 Windows Service using NSSM
1. Download **NSSM** (Non-Sucking Service Manager) from **https://nssm.cc/download** and extract `win64`.
2. Open **Command Prompt as Administrator** inside the NSSM `win64` folder.
3. Clean up any old existing services:
   ```cmd
   nssm stop GoldRelayServer
   nssm remove GoldRelayServer confirm
   ```
4. Install the new service:
   ```cmd
   nssm install GoldRelayServer
   ```
5. In the NSSM pop-up window:
   - **Path**: Find your Python path (e.g. `C:\Python311\python.exe` or `C:\Users\Administrator\AppData\Local\Programs\Python\Python311\python.exe`).
   - **Startup directory**: `C:\GoldRelay`
   - **Arguments**: `relay_server.py`
6. Click **Install service**.
7. Start the service:
   ```cmd
   nssm start GoldRelayServer
   ```
8. Verify server health by opening browser on Master VPS to:
   `http://127.0.0.1:8765/health`

---

## Step 3: Attach Master EA to MT5 (2 Minutes)

1. Open MetaTrader 5 (MT5) on your **Master account**.
2. Go to **File > Open Data Folder > MQL5 > Experts**.
3. Copy [`GoldMasterRelay.mq5`](file:///C:/Main%20Project/gold-trade-copier/gold-trade-copier/GoldMasterRelay.mq5) into this folder.
4. Double-click [`GoldMasterRelay.mq5`](file:///C:/Main%20Project/gold-trade-copier/gold-trade-copier/GoldMasterRelay.mq5) to open MetaEditor (`F4`), then press `F7` to Compile (0 errors).
5. In MT5, go to **Tools > Options > Expert Advisors**:
   - Check **Allow WebRequest for listed URL**.
   - Add: `http://127.0.0.1:8765`
6. Drag `GoldMasterRelay` onto **ANY chart** (e.g. `XAUUSD`, `M1`).
7. In the EA Inputs window:
   - `RelayURL`: `http://127.0.0.1:8765`
   - `ApiKey`: `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd`
8. Click **OK** and make sure the **Algo Trading** button on top is **GREEN**.

---

## Step 4: Attach Slave EA to Slave VPS MT5 (3 Minutes)

Follow these steps on **EVERY Slave VPS** (e.g. Slave 1 `18.133.194.160` or Slave 2 `35.178.131.14`):

1. Open MT5 on the Slave VPS.
2. Go to **Tools > Options > Expert Advisors**:
   - Check **Allow WebRequest for listed URL**.
   - Add: `http://3.11.8.205:8765`
3. Copy [`GoldSlaveRelay.mq5`](file:///C:/Main%20Project/gold-trade-copier/gold-trade-copier/GoldSlaveRelay.mq5) into **File > Open Data Folder > MQL5 > Experts**.
4. Open MetaEditor (`F4`) and press `F7` to Compile (0 errors).
5. Drag `GoldSlaveRelay` onto your target chart (e.g. `XAUUSD`, `M1`).
6. Configure EA Inputs:
   - `RelayURL`: `http://3.11.8.205:8765`
   - `ApiKey`: `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd`
   - `SlaveID`: `Slave_VPS_1` *(Must be unique for each slave, e.g. `Slave_VPS_2`, `Slave_FTMO`)*
   - `SlaveSymbol`: Exact broker symbol name (e.g. `XAUUSD`, `GOLD`, `XAUUSD.a`)
   - `LotMultiplier`: `1.0` *(1:1 copy scaling)*
7. Click **OK** and turn on **Algo Trading** (GREEN button).

---

## Step 5: Deploy Web Dashboard to Cloudflare Pages (4 Minutes)

You can host your Web Dashboard for free on Cloudflare Pages with **zero monthly cost**!

### Option A: GitHub Deployment (Easiest)
1. Push your project folder to your **GitHub** account.
2. Log into **[Cloudflare Dashboard](https://dash.cloudflare.com/)** $\rightarrow$ Go to **Workers & Pages** $\rightarrow$ Click **Create application** $\rightarrow$ **Pages** $\rightarrow$ **Connect to Git**.
3. Select your repository.
4. Build Settings:
   - **Framework preset**: `None`
   - **Root directory**: `/` *(or `dashboard` — both work automatically!)*
   - **Build command**: *(leave empty)*
   - **Build output directory**: `.` *(or `dashboard` — default settings work automatically)*
5. Click **Save and Deploy**.
6. Go to **Settings > Environment variables** on Cloudflare Pages and add:
   - `RELAY_SERVER_URL`: `http://3.11.8.205:8765`
   - `RELAY_API_KEY`: `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd`

### Option B: Deploy from PowerShell Command Line
Open PowerShell in `C:\Main Project\gold-trade-copier\dashboard` and run:
```powershell
npx wrangler pages deploy . --project-name gold-trade-copier
```

---

## Web Dashboard — Complete Feature Reference

The dashboard is a 3-page web application deployed on Cloudflare Pages. Open it at your Cloudflare Pages URL (e.g. `https://your-app.pages.dev`).

---

### First-Time Connection (Do This First)

Before any data loads you must enter your credentials once. They are saved in your browser's `localStorage` and persist across page refreshes.

1. Click **Credentials** (top-right of any page).
2. Fill in the four fields:

   | Field | What to enter |
   |---|---|
   | **Master VPS Relay URL** | If on Cloudflare Pages (HTTPS site): enter `/api` — the Cloudflare Edge Proxy forwards it to your VPS automatically. If testing locally from a file: enter `http://3.11.8.205:8765` |
   | **Relay API Key** | `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd` (default — change in `relay_server.py` for production) |
   | **Supabase Project URL** | Your Supabase project URL e.g. `https://xyzproject.supabase.co` |
   | **Supabase Anon Key** | Your Supabase `anon / public` key (starts with `eyJ...`) |

3. Click **Save & Initialize**.
4. The page auto-refreshes data. If the Master VPS Status card turns **ONLINE** (green), you are connected.

> **Important:** If you are on the live HTTPS Cloudflare Pages site, always use `/api` as the relay URL — never `http://...`. Browsers block HTTP requests from HTTPS pages (Mixed Content policy). The Cloudflare Edge Function at `functions/api/[[path]].js` transparently proxies `/api/*` to your VPS for you.

---

### Admin PIN Security

Destructive actions (Emergency Stop, Pause/Resume Slave, Close Ticket, Save Settings) are protected by a 4-digit PIN.

- **Default PIN**: `7890` (change in `config.js` → `DEFAULT_ADMIN_PIN`)
- On first protected action you are prompted for the PIN once per browser session.
- Once authenticated, the session stays unlocked until the browser tab is closed.
- The Settings page shows a badge: **Admin Authenticated** (teal) or **Guest Mode — Read Only** (amber).

---

### Page 1 — Command Center (`index.html`)

The main live-monitoring overview. Auto-refreshes every 3 seconds.

#### Top Navigation Bar
| Element | Description |
|---|---|
| **Live Master Sync** badge | Teal pill shown when data is fetching. Turns red/offline if VPS unreachable. |
| **Dark / Light** toggle | Switches between Obsidian Dark and Warm Cream themes. State saved in `localStorage`. |
| **Credentials** button | Opens the credentials modal to update VPS/Supabase keys. |
| **Emergency Stop** button | Issues an `EMERGENCY_KILL` command to ALL connected slave terminals — closes all open positions and pauses copying instantly. Requires Admin PIN. |

#### Status Cards (4 tiles at the top)
| Card | What it shows |
|---|---|
| **Master VPS Status** | ONLINE (green) or OFFLINE (red). Updates every 3s by pinging `/api/dashboard-summary`. |
| **Online Slave Terminals** | Count of slaves that sent a heartbeat in the last 30 seconds vs total registered. |
| **Active Open Trades** | Count of currently open master positions being copied. |
| **Cloud Persistence** | Shows "Connected" when Supabase is initialized, "Not Configured" if keys are missing. |

#### Connected Slave VPS Terminals (left card)
A tile is rendered for each Slave EA that has ever polled the relay server. Each tile shows:
- **Slave ID** — the unique name set in `SlaveID` EA input
- **Status badge** — ONLINE (teal, seen < 30s ago), STALE (amber, 30–300s), OFFLINE (grey, > 300s)
- **IP Address** — the slave VPS public IP
- **Symbol** — the broker symbol the slave EA is trading (e.g. `XAUUSD`)
- **Account Info** — MT5 account number (sent by EA)
- **Heartbeat** — seconds since last poll

**Per-slave action buttons** (require Admin PIN):
- **Pause** — queues a `PAUSE` command; the slave EA picks it up on next poll and stops copying new trades
- **Resume** — queues a `RESUME` command to re-enable copying
- **Stop All** — queues a `CLOSE_ALL` command to close all open positions on that specific slave

#### Active Master Open Positions (dark table)
Lists all trades currently open on the Master MT5 account (calculated from the relay server's event log). Columns:
- Master Ticket number
- Symbol, Side (BUY/SELL badge), Volume in lots
- Open Price, SL / TP levels
- Trade timestamp
- **Close Ticket** button — sends a `CLOSE_TICKET` command targeting the specific ticket number to all slaves (Admin PIN required)

#### Supabase Realtime Stream (right panel)
A live terminal window that shows new trade events the moment they are inserted into Supabase PostgreSQL via WebSocket. Each line shows: event type, symbol, side, lots, and master ticket. Requires Supabase keys to be configured.

#### Remote Commands Queue (right panel)
Shows all pending commands in the relay server's `commands` table (PAUSE, RESUME, CLOSE_ALL, EMERGENCY_KILL, CLOSE_TICKET). Clears automatically once the slave EA acknowledges each command.

---

### Page 2 — VPS & System Settings (`settings.html`)

Configure and test your connection without touching code.

#### Master VPS Connection form
- Edit Relay URL, API Key, Supabase URL, and Supabase Anon Key.
- **Save Settings** — persists to `localStorage` and immediately runs a connection test (Admin PIN required).
- **Test VPS Connection** — pings `/api/dashboard-summary`, measures latency in ms, and shows the result in the diagnostic terminal. No PIN required to test.

#### Live Diagnostic Terminal
A scrolling log that shows timestamped connection test results:
- HTTP status and latency on success
- `HTTP 401 Unauthorized` if API key is wrong
- `OFFLINE` with error message if VPS unreachable or proxy fails

#### Auth Status Badge
Top-right badge switches between:
- **Admin Authenticated** (teal, unlocked icon) — PIN entered this session
- **Guest Mode — Read Only** (amber, lock icon) — not yet authenticated

---

### Page 3 — Trade Analytics (`analytics.html`)

Historical analysis of all replicated trades stored in the relay server's SQLite database.

#### Metrics Row (4 cards)
| Card | What it shows |
|---|---|
| **Total Copied Volume** | Sum of all lot sizes across every recorded trade event |
| **Avg Execution Latency** | Fixed at ~24ms (live latency tracking requires Supabase) |
| **Total Replicated Trades** | Count of trade events fetched from `/api/dashboard-summary` |
| **Replication Success Rate** | Displayed as 100% when no errors are recorded |

#### Master Trade Replication History (dark table)
Fetches `recent_events` from `/api/dashboard-summary` and renders one row per trade event. Shows: master ticket, event type (ORDER_OPEN / CLOSE / MODIFY), symbol, side, lot size, execution price, SL/TP, and status badge. Falls back to sample rows if the VPS is unreachable. **Refresh Log** button re-fetches on demand.

---

## Troubleshooting & Quick Fixes

### Problem 1: Master VPS Status shows OFFLINE / `Failed to fetch`
- **Cause A**: Using `http://3.11.8.205:8765` directly on an HTTPS Cloudflare Pages site — browser blocks Mixed Content.
- **Fix A**: Set Relay URL to `/api` in the Credentials modal. The Cloudflare Edge Proxy will route it.
- **Cause B**: `relay_server.py` is not running on Master VPS.
- **Fix B**: RDP into Master VPS, open Command Prompt and run:
  ```cmd
  nssm restart GoldRelayServer
  ```
  Or manually: `cd C:\GoldRelay && python relay_server.py`
- **Cause C**: Port 8765 blocked in firewall.
- **Fix C**: AWS Security Group or VPS firewall — add Inbound rule TCP port 8765 from `0.0.0.0/0`.

### Problem 2: `HTTP 401 Unauthorized`
- **Cause**: API Key in dashboard does not match `API_KEY` in `relay_server.py`.
- **Fix**: Confirm the key in Settings matches exactly: `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd`

### Problem 3: `HTTP 502 Bad Gateway` from Cloudflare
- **Cause**: Cloudflare Edge Proxy reached your domain but the VPS relay was unreachable.
- **Fix**: Verify `relay_server.py` is running and port 8765 is open. Check Cloudflare Pages environment variable `RELAY_SERVER_URL` is set to `http://3.11.8.205:8765`.

### Problem 4: Supabase Realtime Stream shows `Not Configured`
- **Fix**: Click **Credentials**, paste your Supabase Project URL (`https://xyz.supabase.co`) and Anon Key, click **Save & Initialize**.

### Problem 5: MT5 EA `WebRequest failed, error 4060`
- **Cause**: URL not whitelisted in MT5 options.
- **Fix**: In MT5 go to **Tools > Options > Expert Advisors**, check **Allow WebRequest for listed URL**, add `http://3.11.8.205:8765`.

### Problem 6: Slave tiles show STALE or OFFLINE
- **Cause**: Slave EA is not polling (MT5 Algo Trading is paused, EA removed from chart, or VPS restarted).
- **Fix**: On the Slave VPS MT5, ensure the green **Algo Trading** button is active and `GoldSlaveRelay` EA is attached to a chart with `RelayURL = http://3.11.8.205:8765`.

---

🎉 **Congratulations!** Your Master VPS, Supabase Cloud Database, Slave VPS Terminals, and Cloudflare Pages Web Dashboard are now fully connected and operating 24/7!
