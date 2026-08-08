# 🚀 Gold Trade Copier — Web Dashboard & Cloudflare Pages Deployment Guide

This directory contains the real-time **Web Dashboard** for monitoring Master VPS trades, tracking connected Slave VPS terminals, and issuing remote commands (Close Trade, Pause/Resume, Emergency Kill Switch, Dynamic Lot Scaling).

---

## 🛠️ Project Structure

```
dashboard/
├── index.html                  # Single Page Web App (Vanilla JS, Glassmorphic Modern UI)
├── functions/
│   └── api/
│       └── [[path]].js          # Cloudflare Pages Function (Edge API Proxy to Master VPS)
└── README.md                   # This Setup & Deployment Guide
```

---

## 🌐 Cloudflare Pages Deployment (Step-by-Step)

### Option 1: Direct GitHub Integration (Recommended)
1. Push your project directory to **GitHub**.
2. Log into **[Cloudflare Dashboard](https://dash.cloudflare.com/)** -> **Workers & Pages** -> **Create application** -> **Pages**.
3. Select **Connect to Git** and pick your GitHub repository.
4. Set **Build settings**:
   - **Framework preset**: `None`
   - **Build output directory**: `dashboard`
5. Click **Save and Deploy**.
6. Under **Settings** -> **Environment variables**, set:
   - `RELAY_SERVER_URL`: `http://18.169.240.111:8765`
   - `RELAY_API_KEY`: `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd`

### Option 2: Command Line Deployment via Wrangler
Open PowerShell in `C:\Main Project\gold-trade-copier\dashboard` and run:
```powershell
npx wrangler pages deploy . --project-name gold-trade-copier
```

---

## ⚡ Features & Remote Controls

1. **Multi-Slave Live Matrix**: Real-time status badges for online/stale/offline Slave VPS instances, IP address, broker gold symbol (`XAUUSD`, `GOLD`, `XAUUSD.a`), and latency.
2. **Per-Slave Control**:
   - ⏸️ **Pause / Resume**: Freeze or unfreeze trade copying on specific slaves.
   - 🛑 **Close All**: Force close all open positions on a selected Slave VPS.
3. **Master Active Trades Table**: View all live Master tickets, lots, side (BUY/SELL), SL/TP, and close individual tickets remotely.
4. **Emergency Kill Switch**: One-click panic button to immediately close all positions across all slave VPS terminals and pause copying.
5. **Edge API Proxy**: Standard Cloudflare Pages Function proxies `https://your-app.pages.dev/api/*` to `http://18.169.240.111:8765`, bypassing Mixed Content and CORS restrictions.

---

## ☁️ Supabase & Cloudflare Workers Optional Upgrade

If you wish to mirror all trade logs and slave heartbeats to **Supabase (PostgreSQL)** for historical persistence and analytics:
1. Connect Supabase Client JS inside `index.html`.
2. Configure Cloudflare Worker edge database triggers.
3. Integrate with custom `design.md` and `skills.md` when provided.
