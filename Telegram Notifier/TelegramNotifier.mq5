//+------------------------------------------------------------------+
//|                                             TelegramNotifier.mq5  |
//|   Scheduled & Interactive Telegram Trade Notifier                |
//|                                                                  |
//|   Features:                                                      |
//|   - Daily Scheduled Summaries at 8:00 AM IST & 8:00 PM IST        |
//|   - Interactive Commands: /show, /start alerts, /stop alerts,    |
//|     /summary, /help                                              |
//|   - Dynamic Instant Trade Alerts toggle via commands or input    |
//|   - Exact Indian Standard Time (IST, UTC+5:30) date & P&L metrics |
//+------------------------------------------------------------------+
#property copyright "Gold Trade Copier"
#property version   "2.00"
#property strict

//--- Inputs -------------------------------------------------------
input string InpBotToken       = "8770776405:AAEzZJjPgW6I5l51mZEiZRbwbAtB7qs0S04";       // Telegram Bot Token (from @BotFather)
input string InpChatID         = "8725470649";       // Telegram Chat ID (user, group, or channel)
input bool   InpNotifyInstant  = false;    // Default Instant Trade Alerts (Toggleable via /start alerts & /stop alerts)
input bool   InpSendTestMsg    = true;     // Send a test message on startup
input long   InpMagicFilter    = 0;        // Only report this magic number (0 = all magic numbers)
input string InpSymbolFilter   = "";       // Only report this symbol ("" = all symbols)
input int    InpPollIntervalMs = 3000;     // Bot Telegram updates polling interval (ms)

//--- Global State -------------------------------------------------
long   g_telegramOffset = 0;
string g_lastScheduledSlot = "";
bool   g_instantAlertsEnabled = false;
string g_gvAlertsStateName = "TelegramNotifier_InstantAlerts";

//+------------------------------------------------------------------+
//| URL-encode a UTF-8 string                                        |
//+------------------------------------------------------------------+
string UrlEncode(const string text)
{
   string out = "";
   uchar  bytes[];
   int    n = StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   for(int i = 0; i < n; i++)
   {
      uchar c = bytes[i];
      if(c == 0) break;
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
         (c >= '0' && c <= '9') ||
          c == '-' || c == '_' || c == '.' || c == '~')
         out += CharToString(c);
      else if(c == ' ')
         out += "+";
      else
         out += StringFormat("%%%02X", c);
   }
   return out;
}

//+------------------------------------------------------------------+
//| Send a message to Telegram via Bot API                          |
//+------------------------------------------------------------------+
bool SendTelegram(const string message)
{
   if(InpBotToken == "" || InpChatID == "")
   {
      Print("Telegram not configured: set InpBotToken and InpChatID.");
      return false;
   }

   string url  = "https://api.telegram.org/bot" + InpBotToken + "/sendMessage";
   string body = "chat_id=" + InpChatID + "&text=" + UrlEncode(message);

   char   post[];
   char   result[];
   string result_headers;

   int len = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0) ArrayResize(post, len - 1);

   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, result, result_headers);

   if(code == -1)
   {
      Print("WebRequest failed, error ", GetLastError(),
            ". Add https://api.telegram.org in Tools>Options>Expert Advisors>Allow WebRequest.");
      return false;
   }
   if(code != 200)
   {
      Print("Telegram API HTTP ", code, ": ", CharArrayToString(result));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get start timestamp of today in GMT for IST (UTC+5:30)           |
//+------------------------------------------------------------------+
datetime GetTodayStartIST()
{
   datetime nowGMT = TimeGMT();
   datetime nowIST = nowGMT + 19800; // 5h 30m = 19800s

   MqlDateTime dt;
   TimeToStruct(nowIST, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime startIST = StructToTime(dt);
   return startIST - 19800; // convert back to GMT timestamp
}

//+------------------------------------------------------------------+
//| Helper: Array contains ulong                                      |
//+------------------------------------------------------------------+
bool ArrayContainsULong(const ulong &arr[], ulong val)
{
   int sz = ArraySize(arr);
   for(int i = 0; i < sz; i++)
   {
      if(arr[i] == val) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Count open positions matching filters                     |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);

      if(InpSymbolFilter != "" && symbol != InpSymbolFilter) continue;
      if(InpMagicFilter != 0 && magic != InpMagicFilter) continue;

      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Human-readable close reason                                      |
//+------------------------------------------------------------------+
string ReasonText(const ENUM_DEAL_REASON reason)
{
   switch(reason)
   {
      case DEAL_REASON_SL:     return "Stop Loss";
      case DEAL_REASON_TP:     return "Take Profit";
      case DEAL_REASON_SO:     return "Stop Out";
      case DEAL_REASON_EXPERT: return "EA Close";
      case DEAL_REASON_CLIENT:
      case DEAL_REASON_MOBILE:
      case DEAL_REASON_WEB:    return "Manual Close";
      default:                 return "Closed";
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check persistent instant alerts toggle state
   if(GlobalVariableCheck(g_gvAlertsStateName))
   {
      g_instantAlertsEnabled = (GlobalVariableGet(g_gvAlertsStateName) > 0.5);
   }
   else
   {
      g_instantAlertsEnabled = InpNotifyInstant;
      GlobalVariableSet(g_gvAlertsStateName, g_instantAlertsEnabled ? 1.0 : 0.0);
   }

   EventSetMillisecondTimer(InpPollIntervalMs);

   if(InpSendTestMsg)
   {
      string alertStatus = g_instantAlertsEnabled ? "ENABLED" : "DISABLED (Scheduled 8 AM/PM summaries active)";
      string msg = "🔔 Telegram Trade Notifier Connected!\n" +
                   "Account: " + (string)AccountInfoInteger(ACCOUNT_LOGIN) +
                   " (" + AccountInfoString(ACCOUNT_COMPANY) + ")\n" +
                   "Instant Alerts: " + alertStatus + "\n\n" +
                   "Available Commands:\n" +
                   "/show - Detailed trade breakdown\n" +
                   "/summary - On-demand trade summary\n" +
                   "/start alerts - Turn ON instant alerts\n" +
                   "/stop alerts - Turn OFF instant alerts";
      if(SendTelegram(msg))
         Print("Telegram test message sent successfully.");
   }

   Print("TelegramNotifier started. Instant alerts=", g_instantAlertsEnabled ? "ON" : "OFF");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("TelegramNotifier stopped.");
}

//+------------------------------------------------------------------+
//| Timer function for polling updates & checking schedule          |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckScheduledSummary();
   PollTelegramUpdates();
}

//+------------------------------------------------------------------+
//| Check and trigger 8:00 AM IST & 8:00 PM IST summary              |
//+------------------------------------------------------------------+
void CheckScheduledSummary()
{
   datetime nowGMT = TimeGMT();
   datetime nowIST = nowGMT + 19800; // IST = GMT + 5:30 (19800 seconds)

   MqlDateTime dt;
   TimeToStruct(nowIST, dt);

   bool isMorningSlot = (dt.hour == 8  && dt.min == 0);
   bool isNightSlot   = (dt.hour == 20 && dt.min == 0);

   if(!isMorningSlot && !isNightSlot)
      return;

   string slotLabel = isMorningSlot ? "08:00_AM" : "08:00_PM";
   string currentSlotKey = StringFormat("%04d.%02d.%02d_%s", dt.year, dt.mon, dt.day, slotLabel);

   if(g_lastScheduledSlot == currentSlotKey)
      return;

   g_lastScheduledSlot = currentSlotKey;

   string header = isMorningSlot ? "🌅 MORNING TRADE SUMMARY (8:00 AM IST)" : "🌙 NIGHT TRADE SUMMARY (8:00 PM IST)";
   SendDailySummary(header);
}

//+------------------------------------------------------------------+
//| Calculate and send daily summary                                 |
//+------------------------------------------------------------------+
void SendDailySummary(string header)
{
   datetime todayStartGMT = GetTodayStartIST();
   datetime nowGMT = TimeGMT();

   HistorySelect(todayStartGMT, nowGMT);

   int totalDeals = HistoryDealsTotal();
   int tradesTakenCount = 0;
   int closedTradesCount = 0;
   double totalClosedProfit = 0.0;

   ulong openedPositions[];
   ArrayResize(openedPositions, 0);

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;

      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long magic    = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

      if(InpSymbolFilter != "" && symbol != InpSymbolFilter) continue;
      if(InpMagicFilter != 0 && magic != InpMagicFilter) continue;

      ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

      if(entry == DEAL_ENTRY_IN && dealTime >= todayStartGMT)
      {
         ulong posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         if(!ArrayContainsULong(openedPositions, posId))
         {
            int sz = ArraySize(openedPositions);
            ArrayResize(openedPositions, sz + 1);
            openedPositions[sz] = posId;
            tradesTakenCount++;
         }
      }
      else if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) && dealTime >= todayStartGMT)
      {
         closedTradesCount++;
         double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         totalClosedProfit += (profit + swap + commission);
      }
   }

   int currentOpenPositions = CountOpenPositions();
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double startingBalance = currentBalance - totalClosedProfit;
   double pctReturn = (startingBalance > 0) ? (totalClosedProfit / startingBalance) * 100.0 : 0.0;

   string ccy = AccountInfoString(ACCOUNT_CURRENCY);

   datetime nowIST = nowGMT + 19800;
   MqlDateTime dtIST;
   TimeToStruct(nowIST, dtIST);
   string dateStr = StringFormat("%04d-%02d-%02d %02d:%02d IST", dtIST.year, dtIST.mon, dtIST.day, dtIST.hour, dtIST.min);

   string profitSign = (totalClosedProfit >= 0) ? "🟢 +" : "🔴 ";
   string returnSign = (pctReturn >= 0) ? "+" : "";

   string msg = header + "\n" +
                "📅 Date: " + dateStr + "\n" +
                "-----------------------------------\n" +
                "📊 Trades Taken Today: " + IntegerToString(tradesTakenCount) + " (Buy/Sell pairs)\n" +
                "🔒 Closed Trades Today: " + IntegerToString(closedTradesCount) + "\n" +
                "⏳ Active Open Trades: " + IntegerToString(currentOpenPositions) + "\n" +
                "-----------------------------------\n" +
                "💰 Today's P&L: " + profitSign + DoubleToString(totalClosedProfit, 2) + " " + ccy + "\n" +
                "📈 Portfolio Growth: " + returnSign + DoubleToString(pctReturn, 2) + "%\n" +
                "🏦 Current Balance: " + DoubleToString(currentBalance, 2) + " " + ccy + "\n" +
                "-----------------------------------\n" +
                "💡 Send /show for full trade breakdown.";

   SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| Detailed trade report for /show command                          |
//+------------------------------------------------------------------+
void SendShowCommandDetails()
{
   datetime todayStartGMT = GetTodayStartIST();
   datetime nowGMT = TimeGMT();
   datetime nowIST = nowGMT + 19800;

   MqlDateTime dtIST;
   TimeToStruct(nowIST, dtIST);
   string dateStr = StringFormat("%04d-%02d-%02d %02d:%02d IST", dtIST.year, dtIST.mon, dtIST.day, dtIST.hour, dtIST.min);
   string ccy = AccountInfoString(ACCOUNT_CURRENCY);

   string report = "📋 DETAILED TRADE REPORT (Today IST)\n" +
                   "📅 Date: " + dateStr + "\n" +
                   "Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " (" + AccountInfoString(ACCOUNT_COMPANY) + ")\n\n";

   // 1. Currently Active Open Positions
   report += "⏳ ACTIVE OPEN POSITIONS:\n";
   int openTotal = PositionsTotal();
   int openCount = 0;

   for(int i = 0; i < openTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic    = PositionGetInteger(POSITION_MAGIC);

      if(InpSymbolFilter != "" && symbol != InpSymbolFilter) continue;
      if(InpMagicFilter != 0 && magic != InpMagicFilter) continue;

      openCount++;
      long posType  = PositionGetInteger(POSITION_TYPE);
      string side   = (posType == POSITION_TYPE_BUY ? "BUY" : "SELL");
      double volume = PositionGetDouble(POSITION_VOLUME);
      double priceOpen  = PositionGetDouble(POSITION_PRICE_OPEN);
      double priceCurr  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double profit     = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      int digits        = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      string plSign = (profit >= 0 ? "🟢 +" : "🔴 ");

      report += StringFormat("#%d Ticket #%d | %s %.2f %s\n", openCount, ticket, side, volume, symbol);
      report += StringFormat("   Open: %.*f | Curr: %.*f\n", digits, priceOpen, digits, priceCurr);
      report += StringFormat("   P&L: %s%.2f %s | SL: %.*f | TP: %.*f\n\n", plSign, profit, ccy, digits, sl, digits, tp);
   }

   if(openCount == 0)
      report += "   (None)\n\n";

   // 2. Today's Closed Trades
   report += "🔒 CLOSED TRADES TODAY:\n";
   HistorySelect(todayStartGMT, nowGMT);
   int dealsTotal = HistoryDealsTotal();
   int closedCount = 0;
   double totalClosedProfit = 0.0;

   for(int i = 0; i < dealsTotal; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;

      string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long magic    = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

      if(InpSymbolFilter != "" && symbol != InpSymbolFilter) continue;
      if(InpMagicFilter != 0 && magic != InpMagicFilter) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

      if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) && dealTime >= todayStartGMT)
      {
         closedCount++;
         ENUM_DEAL_TYPE dtype    = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
         ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
         double volume           = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
         double priceClose       = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         double profit           = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         double swap             = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         double commission       = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         double netProfit        = profit + swap + commission;
         totalClosedProfit      += netProfit;

         ulong posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         double priceOpen = 0.0;
         string side = (dtype == DEAL_TYPE_BUY ? "SELL" : "BUY"); // deal out type is opposite

         // Find matching entry deal for open price
         for(int j = 0; j < dealsTotal; j++)
         {
            ulong d2 = HistoryDealGetTicket(j);
            if(HistoryDealGetInteger(d2, DEAL_POSITION_ID) == posId &&
               HistoryDealGetInteger(d2, DEAL_ENTRY) == DEAL_ENTRY_IN)
            {
               priceOpen = HistoryDealGetDouble(d2, DEAL_PRICE);
               ENUM_DEAL_TYPE entryType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(d2, DEAL_TYPE);
               side = (entryType == DEAL_TYPE_BUY ? "BUY" : "SELL");
               break;
            }
         }

         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         string plSign = (netProfit >= 0 ? "🟢 +" : "🔴 ");

         report += StringFormat("#%d Ticket #%d | %s %.2f %s\n", closedCount, posId, side, volume, symbol);
         report += StringFormat("   Open: %.*f -> Close: %.*f\n", digits, priceOpen, digits, priceClose);
         report += StringFormat("   Result: %s | P&L: %s%.2f %s\n\n", ReasonText(reason), plSign, netProfit, ccy);
      }
   }

   if(closedCount == 0)
      report += "   (None)\n\n";

   // Summary Footer
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double startingBalance = currentBalance - totalClosedProfit;
   double pctReturn = (startingBalance > 0) ? (totalClosedProfit / startingBalance) * 100.0 : 0.0;
   string profitSign = (totalClosedProfit >= 0) ? "🟢 +" : "🔴 ";
   string returnSign = (pctReturn >= 0) ? "+" : "";

   report += "-----------------------------------\n";
   report += StringFormat("📊 Summary: %d Active | %d Closed | P&L: %s%.2f %s (%s%.2f%%)",
                          openCount, closedCount, profitSign, totalClosedProfit, ccy, returnSign, pctReturn);

   // Break into multiple messages if report exceeds Telegram limit (~4000 chars)
   if(StringLen(report) <= 4000)
   {
      SendTelegram(report);
   }
   else
   {
      int startPos = 0;
      int totalLen = StringLen(report);
      while(startPos < totalLen)
      {
         int len = MathMin(3500, totalLen - startPos);
         SendTelegram(StringSubstr(report, startPos, len));
         startPos += len;
      }
   }
}

//+------------------------------------------------------------------+
//| Poll Telegram for user commands (/show, /start alerts, etc.)    |
//+------------------------------------------------------------------+
void PollTelegramUpdates()
{
   if(InpBotToken == "") return;

   string url  = "https://api.telegram.org/bot" + InpBotToken + "/getUpdates?offset=" + (string)g_telegramOffset + "&timeout=0";
   char   post[];
   char   result[];
   string result_headers;

   ResetLastError();
   int code = WebRequest("GET", url, "", 4000, post, result, result_headers);
   if(code != 200) return;

   string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   if(StringFind(response, "\"ok\":true") < 0) return;

   // Parse update_id array & text messages
   int p = 0;
   while((p = StringFind(response, "\"update_id\":", p)) >= 0)
   {
      p += 12;
      int q = StringFind(response, ",", p);
      if(q < 0) q = StringFind(response, "}", p);
      if(q < 0) break;

      long updateId = StringToInteger(StringSubstr(response, p, q - p));
      if(updateId >= g_telegramOffset)
         g_telegramOffset = updateId + 1;

      // Extract message text
      int msgPos = StringFind(response, "\"text\":\"", p);
      if(msgPos >= 0 && (q < 0 || msgPos < StringFind(response, "\"update_id\":", p + 1) || StringFind(response, "\"update_id\":", p + 1) < 0))
      {
         msgPos += 8;
         int msgEnd = StringFind(response, "\"", msgPos);
         if(msgEnd > msgPos)
         {
            string text = StringSubstr(response, msgPos, msgEnd - msgPos);
            StringTrimLeft(text);
            StringTrimRight(text);
            ProcessTelegramCommand(text);
         }
      }
      p = q;
   }
}

//+------------------------------------------------------------------+
//| Handle command received from Telegram                            |
//+------------------------------------------------------------------+
void ProcessTelegramCommand(string text)
{
   string lowerText = text;
   StringToLower(lowerText);

   if(StringFind(lowerText, "/show") >= 0)
   {
      SendShowCommandDetails();
   }
   else if(StringFind(lowerText, "/start alerts") >= 0 || StringFind(lowerText, "/startalerts") >= 0 || lowerText == "/alerts on")
   {
      g_instantAlertsEnabled = true;
      GlobalVariableSet(g_gvAlertsStateName, 1.0);
      SendTelegram("🔔 Instant Trade Alerts ENABLED! You will now receive instant alerts on trade open & close.\n(Scheduled 8 AM / 8 PM IST summaries remain active).");
   }
   else if(StringFind(lowerText, "/stop alerts") >= 0 || StringFind(lowerText, "/stopalerts") >= 0 || lowerText == "/alerts off")
   {
      g_instantAlertsEnabled = false;
      GlobalVariableSet(g_gvAlertsStateName, 0.0);
      SendTelegram("🔕 Instant Trade Alerts DISABLED. You will only receive scheduled summaries at 8:00 AM & 8:00 PM IST.\n(Send /show anytime for detailed trade breakdown).");
   }
   else if(StringFind(lowerText, "/summary") >= 0 || StringFind(lowerText, "/status") >= 0)
   {
      SendDailySummary("📊 ON-DEMAND TRADE SUMMARY");
   }
   else if(StringFind(lowerText, "/help") >= 0 || lowerText == "/start")
   {
      string helpMsg = "🤖 Telegram Trade Notifier Commands:\n\n" +
                       "📊 /show - View detailed breakdown of today's trades & open positions\n" +
                       "📈 /summary - Get immediate trade summary & P&L\n" +
                       "🔔 /start alerts - Turn ON instant trade open/close alerts\n" +
                       "🔕 /stop alerts - Turn OFF instant trade alerts (scheduled summaries only)\n" +
                       "❓ /help - Show this help menu";
      SendTelegram(helpMsg);
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler for optional instant notifications      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest     &request,
                         const MqlTradeResult      &result)
{
   if(!g_instantAlertsEnabled)
      return;

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal))
   {
      HistorySelect(0, TimeCurrent());
      if(!HistoryDealSelect(deal))
         return;
   }

   ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
   if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
      return;

   string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
   long   magic  = HistoryDealGetInteger(deal, DEAL_MAGIC);

   if(InpSymbolFilter != "" && symbol != InpSymbolFilter) return;
   if(InpMagicFilter  != 0  && magic  != InpMagicFilter)  return;

   ENUM_DEAL_ENTRY  entry  = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(deal, DEAL_REASON);
   double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
   double price  = HistoryDealGetDouble(deal, DEAL_PRICE);
   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   string ccy    = AccountInfoString(ACCOUNT_CURRENCY);
   string side   = (dtype == DEAL_TYPE_BUY ? "BUY" : "SELL");

   string msg = "";

   if(entry == DEAL_ENTRY_IN)
   {
      msg = "🟢 INSTANT ALERT: TRADE OPENED\n" +
            "Symbol: " + symbol + "\n" +
            "Type: "   + side + "\n" +
            "Volume: " + DoubleToString(volume, 2) + "\n" +
            "Price: "  + DoubleToString(price, digits) + "\n" +
            (magic != 0 ? "Magic: " + (string)magic + "\n" : "");
   }
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      string pl = (profit >= 0 ? "🟢 +" : "🔴 ");
      msg = "🔴 INSTANT ALERT: TRADE CLOSED — " + ReasonText(reason) + "\n" +
            "Symbol: " + symbol + "\n" +
            "Volume: " + DoubleToString(volume, 2) + "\n" +
            "Close Price: " + DoubleToString(price, digits) + "\n" +
            "Profit: " + pl + DoubleToString(profit, 2) + " " + ccy + "\n" +
            (magic != 0 ? "Magic: " + (string)magic + "\n" : "");
   }

   if(msg != "")
      SendTelegram(msg);
}
//+------------------------------------------------------------------+
