# 🚀 Gold Trade Copier — Complete Beginner-Friendly Setup Guide

Welcome! This guide is written so **anyone (even an 18-year-old student setting this up for the first time)** can set up the Master VPS relay server, connect Supabase Cloud database persistence, attach MT5 EAs, and deploy the Web Dashboard to Cloudflare Pages in less than 20 minutes!

---

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

## Remote Controls & Web Dashboard Usage Guide

Open your live dashboard website (`https://your-app.pages.dev`):

1. **Configure Credentials**:
   - Click **Credentials** button at the top right.
   - Paste your Master VPS Relay URL (`/api` or `http://3.11.8.205:8765`), API Key, Supabase URL, and Supabase Anon Key.
   - Click **Save & Initialize**.
2. **Monitor Slave Terminals**:
   - View live cards for all registered Slave VPS terminals with IP, broker symbol, and heartbeat latency.
3. **Pause / Resume Slave Copying**:
   - Click **⏸ Pause** on any slave card to freeze trade copying on that specific terminal without closing MT5.
   - Click **▶ Resume** to unfreeze.
4. **Close Active Master Trades**:
   - In the **Active Master Open Positions** table, click **Close Ticket** next to any trade to close it remotely on slave accounts.
5. **Emergency Kill Switch**:
   - Click the bright coral **Emergency Stop** button at the top right to instantly close all open positions and pause copying across all online slave VPS terminals.

---

## Troubleshooting & Quick Fixes

### Problem 1: `Relay returned HTTP 401`
- **Cause**: Incorrect API Key sent by Slave EA or old python process locking port.
- **Fix**: Open Command Prompt as Administrator on Master VPS and run:
  ```cmd
  taskkill /F /IM python.exe
  nssm restart GoldRelayServer
  ```

### Problem 2: `WebRequest failed, error 4060` or `error 1001`
- **Cause**: URL missing from MT5's Allowed WebRequest URL list.
- **Fix**: In MT5, go to **Tools > Options > Expert Advisors** $\rightarrow$ Check **Allow WebRequest for listed URL** $\rightarrow$ Add `http://3.11.8.205:8765`.

### Problem 3: Supabase Realtime Stream says `Supabase Keys Missing`
- **Fix**: Click **Credentials** in top right of the Web Dashboard and paste your Supabase Project URL (`https://xyz.supabase.co`) and Anon Key. Click **Save & Initialize**.

---

🎉 **Congratulations!** Your Master VPS, Supabase Cloud Database, Slave VPS Terminals, and Cloudflare Pages Web Dashboard are now fully connected and operating 24/7!
