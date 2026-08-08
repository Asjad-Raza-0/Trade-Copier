//+------------------------------------------------------------------+
//|                                            GoldMasterRelay.mq5    |
//|  Watches this account for trades matching SymbolFilter/           |
//|  MagicFilter and relays OPEN / CLOSE / SL-TP-MODIFY events to     |
//|  the relay server as they happen.                                 |
//|                                                                   |
//|  Broadcasts trade events to relay_server.py on the Master VPS,    |
//|  allowing single or multiple Slave VPS instances to copy trades.  |
//|                                                                   |
//|  Attach to ANY chart on the MASTER account - it reacts to          |
//|  account-wide trade events, not just the chart's own symbol.       |
//+------------------------------------------------------------------+
#property copyright "Gold Trade Copier"
#property version   "1.10"

input string RelayURL     = "http://127.0.0.1:8765"; // Relay server URL (Master VPS)
input string ApiKey       = "ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd"; // Must match relay_server.py
input string SymbolFilter = "";   // Only relay symbols containing this text (blank = all)
input long   MagicFilter  = 0;          // Only relay this magic number (0 = all magic numbers)
input int    TimeoutMs    = 5000;       // WebRequest timeout (ms)

//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(ApiKey, "CHANGE_ME") >= 0)
      Print("WARNING: ApiKey is still the placeholder. Set a real key here AND in relay_server.py.");

   Print("GoldMasterRelay started. SymbolFilter='", SymbolFilter, "' MagicFilter=", MagicFilter,
         " RelayURL=", RelayURL);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("GoldMasterRelay stopped.");
}

//+------------------------------------------------------------------+
//| Fires on every trade transaction on this account                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      HandleDeal(trans.deal);
   else if(trans.type == TRADE_TRANSACTION_POSITION)
      HandlePositionModify(trans.position);
}

//+------------------------------------------------------------------+
//| A deal was added to history -> figure out if it's an open or a    |
//| close and relay it                                                 |
//+------------------------------------------------------------------+
void HandleDeal(ulong dealTicket)
{
   if(!HistoryDealSelect(dealTicket)) return;

   string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(symbol == "") return; // balance/credit ops have no symbol, ignore

   string symbolUpper = symbol;
   string filterUpper = SymbolFilter;
   StringToUpper(symbolUpper);
   StringToUpper(filterUpper);
   if(StringLen(filterUpper) > 0 && StringFind(symbolUpper, filterUpper) < 0)
      return;

   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(MagicFilter != 0 && magic != MagicFilter)
      return;

   long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return; // ignore balance/correction deals etc.

   long entry       = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long positionId  = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double volume    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   double price     = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   datetime dtime   = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);

   string side = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";

   if(entry == DEAL_ENTRY_IN)
      SendEvent("OPEN", symbol, side, volume, price, 0, 0, magic, positionId, dtime);
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      SendEvent("CLOSE", symbol, side, volume, price, 0, 0, magic, positionId, dtime);
}

//+------------------------------------------------------------------+
//| A position's SL/TP (or volume) changed -> relay the new SL/TP     |
//+------------------------------------------------------------------+
void HandlePositionModify(ulong positionTicket)
{
   if(!PositionSelectByTicket(positionTicket)) return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   string symbolUpper = symbol;
   string filterUpper = SymbolFilter;
   StringToUpper(symbolUpper);
   StringToUpper(filterUpper);
   if(StringLen(filterUpper) > 0 && StringFind(symbolUpper, filterUpper) < 0)
      return;

   long magic = PositionGetInteger(POSITION_MAGIC);
   if(MagicFilter != 0 && magic != MagicFilter)
      return;

   double sl      = PositionGetDouble(POSITION_SL);
   double tp      = PositionGetDouble(POSITION_TP);
   double volume  = PositionGetDouble(POSITION_VOLUME);
   long   posType = PositionGetInteger(POSITION_TYPE);
   string side    = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   SendEvent("MODIFY", symbol, side, volume, 0, sl, tp, magic, (long)positionTicket, TimeCurrent());
}

//+------------------------------------------------------------------+
//| Build a small JSON payload and POST it to the relay server        |
//+------------------------------------------------------------------+
void SendEvent(string type, string symbol, string side, double lot, double price,
               double sl, double tp, long magic, long masterTicket, datetime dtime)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 0) digits = 2;
   string timeStr = TimeToString(dtime, TIME_DATE | TIME_SECONDS);

   string json = "{";
   json += "\"type\":\""   + type   + "\",";
   json += "\"symbol\":\"" + symbol + "\",";
   json += "\"side\":\""   + side   + "\",";
   json += "\"lot\":"      + DoubleToString(lot, 2) + ",";
   json += "\"price\":"    + DoubleToString(price, digits) + ",";
   json += "\"sl\":"       + DoubleToString(sl, digits) + ",";
   json += "\"tp\":"       + DoubleToString(tp, digits) + ",";
   json += "\"magic\":"    + IntegerToString(magic) + ",";
   json += "\"master_ticket\":" + IntegerToString(masterTicket) + ",";
   json += "\"time\":\""   + timeStr + "\"";
   json += "}";

   uchar postData[];
   StringToCharArray(json, postData, 0, WHOLE_ARRAY, CP_UTF8);
   if(ArraySize(postData) > 0 && postData[ArraySize(postData) - 1] == 0)
   {
      ArrayResize(postData, ArraySize(postData) - 1);
   }

   string headers = "Content-Type: application/json\r\nX-API-Key: " + ApiKey + "\r\n";
   uchar result[];
   string resultHeaders;

   ResetLastError();
   int res = WebRequest("POST", RelayURL + "/trade", headers, TimeoutMs, postData, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      Print("WebRequest failed, error ", err, ". Add '", RelayURL,
            "' to Tools > Options > Expert Advisors > Allow WebRequest for listed URL.");
   }
   else if(res != 200)
   {
      Print("Relay server returned HTTP ", res, ": ", CharArrayToString(result));
   }
   else
   {
      Print("Relayed ", type, " ", symbol, " ", side, " ", DoubleToString(lot, 2),
            " lots (master ticket ", masterTicket, ")");
   }
}
//+------------------------------------------------------------------+
