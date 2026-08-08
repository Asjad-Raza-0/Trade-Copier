# 🚀 Gold Trade Copier — Web Dashboard & Cloudflare Pages Setup

This directory contains the real-time **Web Dashboard** designed with the **Anthropic / Claude Editorial Theme** (`#faf9f5` Cream Canvas, `#cc785c` Coral Accent, `#181715` Dark Navy Product Cards) for monitoring Master VPS trades, connected Slave VPS terminals, Supabase Realtime WebSockets, and issuing remote commands (Pause/Resume, Close Ticket, Emergency Stop).

---

## 🛠️ Project Structure

```
dashboard/
├── index.html                  # Anthropic Editorial Single Page Web App (Supabase Realtime WebSockets + API)
├── functions/
│   └── api/
│       └── [[path]].js          # Cloudflare Pages Function (Edge API Proxy to Master VPS)
└── README.md                   # Setup & Deployment Guide
```

---

## 🌐 Cloudflare Pages Deployment (Step-by-Step)

### Option 1: GitHub Integration (Recommended)
1. Push your project directory to **GitHub**.
2. Log into **[Cloudflare Dashboard](https://dash.cloudflare.com/)** $\rightarrow$ **Workers & Pages** $\rightarrow$ **Create application** $\rightarrow$ **Pages**.
3. Select **Connect to Git** and pick your GitHub repository.
4. Set **Build settings**:
   - **Framework preset**: `None`
   - **Build output directory**: `dashboard`
5. Click **Save and Deploy**.
6. Under **Settings** $\rightarrow$ **Environment variables**, set:
   - `RELAY_SERVER_URL`: `http://3.11.8.205:8765`
   - `RELAY_API_KEY`: `ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd`

### Option 2: Command Line Deployment via Wrangler
Open PowerShell in `C:\Main Project\gold-trade-copier\dashboard` and run:
```powershell
npx wrangler pages deploy . --project-name gold-trade-copier
```

---

## ⚡ Web Dashboard Features

1. **Anthropic Claude Theme**: Built with Warm Cream Canvas (`#faf9f5`), Warm Ink text (`#141413`), Serif Display headlines (`Cormorant Garamond`), Warm Coral CTAs (`#cc785c`), and Dark Navy Terminal Cards (`#181715`).
2. **Supabase Realtime Integration**: Uses `@supabase/supabase-js` to connect directly to your Supabase PostgreSQL cloud database and stream real-time trade events over WebSockets.
3. **Multi-Slave Live Controls**:
   - ⏸️ **Pause / Resume**: Freeze or unfreeze trade copying on specific slaves.
   - 🛑 **Stop All**: Force close all open positions on a selected Slave VPS.
4. **Master Active Trades Table**: View all live Master tickets, lots, side (BUY/SELL), SL/TP, and close individual tickets remotely.
5. **Emergency Stop**: Bright coral panic button to immediately close all positions across all slave VPS terminals and pause copying.
6. **Edge API Proxy**: Standard Cloudflare Pages Function proxies `https://your-app.pages.dev/api/*` to `http://3.11.8.205:8765`, bypassing Mixed Content and CORS restrictions.
