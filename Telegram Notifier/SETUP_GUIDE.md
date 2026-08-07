# Telegram Trade Notifier — Setup & User Guide

An interactive Telegram Trade Notifier for MetaTrader 5 (MT5). Provides scheduled daily trade summaries at **8:00 AM IST** and **8:00 PM IST**, interactive Telegram commands (`/show`, `/summary`, `/start alerts`, `/stop alerts`), and full portfolio metrics.

---

## Key Features

- **Scheduled Summaries**: Automatically sends daily performance reports at **8:00 AM IST** (UTC+5:30) and **8:00 PM IST** (UTC+5:30).
- **Daily Performance Metrics**:
  - Total trades taken today (Buy & Sell entry/exit pairs counted as 1 trade).
  - Total Closed P&L (Profit/Loss in account currency).
  - Portfolio percentage return today (`%` growth calculated against starting balance of today).
  - Active open positions count.
- **Interactive Bot Commands**:
  - `/show`: Displays a full detailed report of all currently active open positions AND today's closed trades (open/close prices, P&L, SL/TP levels).
  - `/summary`: Instantly delivers an on-demand daily trade summary.
  - `/start alerts`: Enables instant notifications on every single trade open and close.
  - `/stop alerts`: Disables instant per-trade notifications (default behavior; only 8 AM & 8 PM IST summaries are sent).
  - `/help`: Displays available commands.

---

## Step 1 — Create Your Telegram Bot & Get Chat ID

1. Open Telegram and search for **@BotFather**.
2. Send `/newbot` and follow the prompts to name your bot.
3. Copy the HTTP API **Bot Token** (e.g. `7123456789:AAFx...`).
4. Open Telegram and search for **@userinfobot** (or invite your new bot to a group/channel).
5. Send any message to **@userinfobot** to get your numeric **Chat ID** (e.g. `987654321`).
6. Start a chat with your newly created bot by clicking **START**.

---

## Step 2 — Enable WebRequest in MT5

1. Open MetaTrader 5.
2. Go to **Tools > Options** (or press `Ctrl + O`).
3. Click the **Expert Advisors** tab.
4. Check **Allow WebRequest for listed URL**.
5. Double-click the list below it and add:
   ```
   https://api.telegram.org
   ```
6. Click **OK**.

---

## Step 3 — Install & Attach EA in MT5

1. Copy `TelegramNotifier.mq5` into your MT5 `MQL5/Experts` folder:
   - MT5 Menu: **File > Open Data Folder > MQL5 > Experts**.
2. Open `TelegramNotifier.mq5` in MetaEditor (`F4`), then click **Compile** (`F7`).
3. Drag `TelegramNotifier` onto **ANY chart** in MT5 (it monitors account-wide trades regardless of chart symbol).
4. In the EA Inputs tab:
   - `InpBotToken`: Paste your Telegram Bot Token.
   - `InpChatID`: Paste your Telegram Chat ID.
   - `InpNotifyInstant`: `false` (default for scheduled 8 AM & 8 PM IST summaries only). Set `true` if you want instant alerts enabled on startup.
   - `InpSymbolFilter`: Leave empty `""` for all symbols, or enter e.g. `XAUUSD`.
   - `InpMagicFilter`: Leave `0` for all magic numbers, or enter a specific EA magic number.
5. Click **OK** and ensure **AutoTrading** is enabled (Green button on MT5 toolbar).
6. You will receive a connection confirmation message in Telegram!

---

## Telegram Bot Commands Reference

You can send any of these commands directly to your Telegram bot at any time:

| Command | Action |
| :--- | :--- |
| `/show` | Displays a detailed breakdown of all active open positions AND today's closed trades (Open/Close prices, P&L, SL/TP). |
| `/summary` | Instantly sends the current daily P&L and trade metrics on demand. |
| `/start alerts` | Turns **ON** instant alerts for every trade open and close. |
| `/stop alerts` | Turns **OFF** instant trade alerts (switches back to 8 AM & 8 PM IST summaries only). |
| `/help` | Shows the interactive commands menu. |

---

## How Metrics Are Calculated

- **Today's Time Boundary**: "Today" is calculated according to **Indian Standard Time (IST, UTC+5:30)** starting at 00:00:00 IST.
- **Trades Taken Today**: Counted as distinct positions opened today. A Buy/Sell pair is counted as **1 single trade**.
- **Today's Closed P&L**: Net sum of `Profit + Swap + Commission` for all trades closed today in account currency.
- **Portfolio Growth (%)**:
  $$\text{Portfolio Return (\%)} = \left(\frac{\text{Today's Closed P\&L}}{\text{Starting Balance Today}}\right) \times 100\%$$
  where $\text{Starting Balance Today} = \text{Current Balance} - \text{Today's Closed P\&L}$.

---

## Troubleshooting

- **No messages received on `/show` or commands**:
  - Make sure you clicked **START** in your bot's chat.
  - Confirm `https://api.telegram.org` is added to MT5 WebRequest URL list.
  - Check the MT5 **Experts** log tab for error messages.
- **WebRequest error 4060**:
  - You haven't added `https://api.telegram.org` to MT5 Expert Advisors allowed URLs list (Step 2).
- **Timezone alignment**:
  - The scheduled summaries automatically convert UTC/Broker time to **IST (+5:30)** using `TimeGMT() + 19800`, ensuring exact 8:00 AM and 8:00 PM IST delivery regardless of broker server location.
