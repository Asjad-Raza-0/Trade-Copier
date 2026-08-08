//+------------------------------------------------------------------+
//|                                             GoldSlaveRelay.mq5    |
//|  Polls the relay server for trade events and mirrors them on      |
//|  this account: OPEN, CLOSE, and SL/TP MODIFY.                     |
//|                                                                   |
//|  Supports multi-slave architecture with robust ticket mapping,     |
//|  proportional partial closes, reverse SL/TP, auto-filling mode,    |
//|  server DB reset auto-recovery, and Remote Web Commands.           |
//+------------------------------------------------------------------+
#property copyright "Gold Trade Copier"
#property version   "2.10"

input string RelayURL       = "http://3.11.8.205:8765"; // Relay server URL (Master VPS public IP)
input string ApiKey         = "ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd"; // Must match relay_server.py
input string SlaveID        = "Slave_VPS_1"; // Unique name/ID for this Slave VPS (e.g. Slave_FTMO, Slave_ICMarkets)
input string SlaveSymbol    = "XAUUSD";  // This broker's exact gold symbol name (e.g. XAUUSD, GOLD, XAUUSD.a)
input double LotMultiplier  = 1.0;       // Scale the master's lot size by this factor
input double FixedLot       = 0;         // If > 0, always use this lot size instead of scaling
input bool   ReverseTrade   = false;     // true = mirror opposite direction (BUY<->SELL)
input long   SlaveMagic     = 1111111;   // Magic number to tag trades opened by this EA
input int    PollIntervalMs = 1000;      // How often to poll the relay server (ms)
input int    MaxTradeAgeSec = 3600;      // Ignore trade events older than this (3600 = 1 hour cutoff)
input int    TimeoutMs      = 5000;      // WebRequest timeout (ms)
input int    MaxSlippagePts = 50;        // Allowed slippage in points

long g_lastEventId = 0;
string g_gvName = "";
string g_effectiveSlaveId = "";
string g_gvPrefix = "";
bool g_isPaused = false;
double g_runtimeLotMultiplier = 1.0;

// Forward declaration for commands
void PollCommands();

//+------------------------------------------------------------------+
void CleanupOldGlobalVariables()
{
   int total = GlobalVariablesTotal();
   datetime cutoff = TimeCurrent() - 86400; // Delete cache/mapping older than 24h (previous day)
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, g_gvPrefix) == 0 && name != g_gvName)
      {
         if(GlobalVariableTime(name) < cutoff)
         {
            GlobalVariableDel(name);
         }
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(ApiKey, "CHANGE_ME") >= 0)
      Print("WARNING: ApiKey is still the placeholder. Set a real key here AND in relay_server.py.");
   if(StringFind(RelayURL, "MASTER_VPS_PUBLIC_IP") >= 0)
      Print("WARNING: RelayURL still has the placeholder IP. Set it to the Master VPS's real public IP.");

   g_runtimeLotMultiplier = LotMultiplier;

   // Determine effective Slave ID
   g_effectiveSlaveId = SlaveID;
   StringTrimLeft(g_effectiveSlaveId);
   StringTrimRight(g_effectiveSlaveId);
   if(StringLen(g_effectiveSlaveId) == 0)
   {
      g_effectiveSlaveId = "Slave_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(SlaveMagic);
   }

   // Prefixes for unique Global Variables
   g_gvPrefix = "GSR_" + g_effectiveSlaveId + "_";
   g_gvName = g_gvPrefix + "LastId";

   if(GlobalVariableCheck(g_gvName))
      g_lastEventId = (long)GlobalVariableGet(g_gvName);

   // Clean up previous day cache logs from GlobalVariables
   CleanupOldGlobalVariables();

   if(!SymbolSelect(SlaveSymbol, true))
      Print("WARNING: could not select symbol '", SlaveSymbol, "' - check the exact symbol name for this broker.");

   EventSetMillisecondTimer(PollIntervalMs);
   Print("GoldSlaveRelay v2.10 started. SlaveID='", g_effectiveSlaveId, "', SlaveSymbol='", SlaveSymbol,
         "', Resuming from event id ", g_lastEventId, ", MaxTradeAgeSec=", MaxTradeAgeSec, "s (1h filter)");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("GoldSlaveRelay stopped.");
}

//+------------------------------------------------------------------+
//| Poll trade events & remote web commands on every timer tick       |
//+------------------------------------------------------------------+
void OnTimer()
{
   PollOnce();
   PollCommands();
}

//+------------------------------------------------------------------+
//| URL Encoding Helper                                               |
//+------------------------------------------------------------------+
string UrlEncode(string text)
{
   string result = "";
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
   {
      ushort c = StringGetCharacter(text, i);
      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
      {
         result += ShortToString(c);
      }
      else if(c == ' ')
      {
         result += "+";
      }
      else
      {
         result += StringFormat("%%%02X", c);
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Auto-detect filling mode for the slave broker                     |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
   uint fillMode = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   if((fillMode & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Returns true if events were found and processed                   |
//+------------------------------------------------------------------+
bool PollOnce()
{
   string accountStr = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "@" + AccountInfoString(ACCOUNT_SERVER);
   string url = RelayURL + "/poll?since=" + IntegerToString(g_lastEventId) +
                "&limit=20" +
                "&max_age=" + IntegerToString(MaxTradeAgeSec) +
                "&slave_id=" + UrlEncode(g_effectiveSlaveId) +
                "&symbol=" + UrlEncode(SlaveSymbol) +
                "&account=" + UrlEncode(accountStr);

   string headers = "X-API-Key: " + ApiKey + "\r\n";
   uchar postData[];
   uchar result[];
   string resultHeaders;

   ResetLastError();
   int res = WebRequest("GET", url, headers, TimeoutMs, postData, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      Print("Poll failed, error ", err, ". Add '", RelayURL,
            "' to Tools > Options > Expert Advisors > Allow WebRequest for listed URL, ",
            "and confirm the Master VPS firewall allows this connection.");
      return false;
   }
   if(res != 200)
   {
      Print("Relay returned HTTP ", res);
      return false;
   }

   string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   // Check server database reset signal
   if(JsonGetBool(response, "reset"))
   {
      long maxId = (long)JsonGetNumber(response, "max_id");
      Print("WARNING: Server event DB was reset/purged. Updating slave cursor from ", g_lastEventId, " to ", maxId);
      g_lastEventId = maxId;
      GlobalVariableSet(g_gvName, (double)g_lastEventId);
      return false;
   }

   if(JsonGetBool(response, "empty"))
   {
      long serverLastId = (long)JsonGetNumber(response, "last_id");
      if(serverLastId > g_lastEventId)
      {
         g_lastEventId = serverLastId;
         GlobalVariableSet(g_gvName, (double)g_lastEventId);
      }
      return false;
   }

   // Process single or batch events
   ProcessResponse(response);
   return true;
}

//+------------------------------------------------------------------+
void ProcessResponse(string json)
{
   // Check if response contains array of events
   int eventsStart = StringFind(json, "\"events\":[");
   if(eventsStart >= 0)
   {
      // Extract array contents
      int arrayEnd = StringFind(json, "]", eventsStart);
      if(arrayEnd > eventsStart)
      {
         string eventsArrayStr = StringSubstr(json, eventsStart + 9, arrayEnd - (eventsStart + 9));
         int cur = 0;
         int len = StringLen(eventsArrayStr);
         while(cur < len)
         {
            int objStart = StringFind(eventsArrayStr, "{", cur);
            if(objStart < 0) break;
            int objEnd = StringFind(eventsArrayStr, "}", objStart);
            if(objEnd < 0) break;

            string eventJson = StringSubstr(eventsArrayStr, objStart, objEnd - objStart + 1);
            ProcessEvent(eventJson);
            cur = objEnd + 1;
         }
         return;
      }
   }

   // Single event fallback
   ProcessEvent(json);
}

//+------------------------------------------------------------------+
void ProcessEvent(string json)
{
   long   id           = (long)JsonGetNumber(json, "id");
   string type         = JsonGetString(json, "type");
   string side         = JsonGetString(json, "side");
   double lot          = JsonGetNumber(json, "lot");
   double price        = JsonGetNumber(json, "price");
   double sl           = JsonGetNumber(json, "sl");
   double tp           = JsonGetNumber(json, "tp");
   long   masterTicket = (long)JsonGetNumber(json, "master_ticket");
   string eventTimeStr = JsonGetString(json, "time");

   if(id <= 0) return;

   // Check trade age for ALL event types to prevent executing stale trades older than MaxTradeAgeSec (default 1 hour)
   if(MaxTradeAgeSec > 0 && StringLen(eventTimeStr) > 0)
   {
      datetime eventTime = StringToTime(eventTimeStr);
      datetime now = TimeCurrent();
      if(eventTime > 0 && (now - eventTime) > MaxTradeAgeSec)
      {
         Print("WARNING: Skipping stale ", type, " event #", id, " (Master Ticket ", masterTicket,
               "). Trade age: ", (now - eventTime), "s exceeds MaxTradeAgeSec=", MaxTradeAgeSec, "s (1h cutoff filter)");
         g_lastEventId = id;
         GlobalVariableSet(g_gvName, (double)g_lastEventId);
         return;
      }
   }

   if(ReverseTrade)
      side = (side == "BUY") ? "SELL" : "BUY";

   if(g_isPaused && type == "OPEN")
   {
      Print("Slave '", g_effectiveSlaveId, "' is PAUSED via remote command. Skipping OPEN event #", id);
      g_lastEventId = id;
      GlobalVariableSet(g_gvName, (double)g_lastEventId);
      return;
   }

   double effectiveMultiplier = LotMultiplier * g_runtimeLotMultiplier;
   double lotToUse = (FixedLot > 0) ? FixedLot : NormalizeLot(lot * effectiveMultiplier);

   if(type == "OPEN")
      ExecuteOpen(masterTicket, side, lotToUse, lot, price);
   else if(type == "CLOSE")
      ExecuteClose(masterTicket, lot);
   else if(type == "MODIFY")
      ExecuteModify(masterTicket, sl, tp, price);

   g_lastEventId = id;
   GlobalVariableSet(g_gvName, (double)g_lastEventId);
}

//+------------------------------------------------------------------+
//| Remote Commands Logic (Web Dashboard Control)                     |
//+------------------------------------------------------------------+
void CloseAllSlavePositions()
{
   int total = PositionsTotal();
   int closed = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC) != SlaveMagic) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      long   posType = PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action       = TRADE_ACTION_DEAL;
      request.position     = ticket;
      request.symbol       = symbol;
      request.volume       = volume;
      request.type         = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price        = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      request.deviation    = MaxSlippagePts;
      request.magic        = SlaveMagic;
      request.type_filling = GetFillingMode(symbol);

      if(OrderSend(request, result))
         closed++;
   }
   Print("Remote Command: Closed ", closed, " active slave positions.");
}

void AckCommand(long cmdId, string status)
{
   string url = RelayURL + "/api/command-ack";
   string headers = "Content-Type: application/json\r\nX-API-Key: " + ApiKey + "\r\n";
   string body = "{\"command_id\":" + IntegerToString(cmdId) + ",\"slave_id\":\"" + g_effectiveSlaveId + "\",\"status\":\"" + status + "\"}";

   uchar postData[];
   StringToCharArray(body, postData, 0, WHOLE_ARRAY, CP_UTF8);
   if(ArraySize(postData) > 0 && postData[ArraySize(postData) - 1] == 0)
      ArrayResize(postData, ArraySize(postData) - 1);

   uchar result[];
   string resultHeaders;
   WebRequest("POST", url, headers, TimeoutMs, postData, result, resultHeaders);
}

void ExecuteCommand(long cmdId, string action, string paramsJson)
{
   Print("Executing Remote Command #", cmdId, " Action: ", action, " Params: ", paramsJson);

   if(action == "CLOSE_TICKET")
   {
      long masterTicket = (long)JsonGetNumber(paramsJson, "master_ticket");
      if(masterTicket > 0)
         ExecuteClose(masterTicket, 0); // Full close
      AckCommand(cmdId, "EXECUTED");
   }
   else if(action == "CLOSE_ALL")
   {
      CloseAllSlavePositions();
      AckCommand(cmdId, "EXECUTED");
   }
   else if(action == "PAUSE_SLAVE" || action == "PAUSE")
   {
      g_isPaused = true;
      Print("Slave PAUSED by Web Dashboard.");
      AckCommand(cmdId, "EXECUTED");
   }
   else if(action == "RESUME_SLAVE" || action == "RESUME")
   {
      g_isPaused = false;
      Print("Slave RESUMED by Web Dashboard.");
      AckCommand(cmdId, "EXECUTED");
   }
   else if(action == "SET_LOT_SCALE")
   {
      double mult = JsonGetNumber(paramsJson, "multiplier");
      if(mult > 0)
      {
         g_runtimeLotMultiplier = mult;
         Print("Slave lot scale updated to: ", g_runtimeLotMultiplier);
      }
      AckCommand(cmdId, "EXECUTED");
   }
   else if(action == "EMERGENCY_KILL")
   {
      g_isPaused = true;
      CloseAllSlavePositions();
      Print("EMERGENCY KILL executed! Closed all positions & paused slave.");
      AckCommand(cmdId, "EXECUTED");
   }
   else
   {
      AckCommand(cmdId, "UNKNOWN_ACTION");
   }
}

void PollCommands()
{
   string url = RelayURL + "/api/slave-commands?slave_id=" + UrlEncode(g_effectiveSlaveId);
   string headers = "X-API-Key: " + ApiKey + "\r\n";
   uchar postData[];
   uchar result[];
   string resultHeaders;

   ResetLastError();
   int res = WebRequest("GET", url, headers, TimeoutMs, postData, result, resultHeaders);
   if(res != 200) return;

   string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   int cmdsStart = StringFind(response, "\"commands\":[");
   if(cmdsStart < 0) return;

   int arrayEnd = StringFind(response, "]", cmdsStart);
   if(arrayEnd <= cmdsStart) return;

   string cmdsArrayStr = StringSubstr(response, cmdsStart + 12, arrayEnd - (cmdsStart + 12));
   int cur = 0;
   int len = StringLen(cmdsArrayStr);
   while(cur < len)
   {
      int objStart = StringFind(cmdsArrayStr, "{", cur);
      if(objStart < 0) break;
      int objEnd = StringFind(cmdsArrayStr, "}", objStart);
      if(objEnd < 0) break;

      string cmdJson = StringSubstr(cmdsArrayStr, objStart, objEnd - objStart + 1);
      long cmdId = (long)JsonGetNumber(cmdJson, "id");
      string action = JsonGetString(cmdJson, "action");

      if(cmdId > 0 && StringLen(action) > 0)
      {
         ExecuteCommand(cmdId, action, cmdJson);
      }
      cur = objEnd + 1;
   }
}

//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(SlaveSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(SlaveSymbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(SlaveSymbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;

   lot = MathRound(lot / step) * step;
   if(lot < minLot) lot = minLot;
   if(maxLot > 0 && lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
void ExecuteOpen(long masterTicket, string side, double lot, double masterLot, double masterPrice)
{
   if(!SymbolSelect(SlaveSymbol, true))
   {
      Print("Cannot select symbol ", SlaveSymbol);
      return;
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double askPrice = SymbolInfoDouble(SlaveSymbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(SlaveSymbol, SYMBOL_BID);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = SlaveSymbol;
   request.volume       = lot;
   request.type         = (side == "BUY") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price        = (side == "BUY") ? askPrice : bidPrice;
   request.deviation    = MaxSlippagePts;
   request.magic        = SlaveMagic;
   request.comment      = "MC:" + IntegerToString(masterTicket);
   request.type_filling = GetFillingMode(SlaveSymbol);

   if(!OrderSend(request, result))
   {
      Print("OrderSend (open) failed for master ticket ", masterTicket, ": ", result.retcode, " ", result.comment);
   }
   else
   {
      ulong slaveTicket = result.order;
      Print("Opened ", side, " ", DoubleToString(lot, 2), " ", SlaveSymbol,
            " for master ticket ", masterTicket, " -> slave order/deal ", slaveTicket);

      // Store ticket mapping and initial volumes in MT5 Global Variables
      string mapKey = g_gvPrefix + "TMap_" + IntegerToString(masterTicket);
      string masterVolKey = g_gvPrefix + "MVol_" + IntegerToString(masterTicket);
      string masterPriceKey = g_gvPrefix + "MPrice_" + IntegerToString(masterTicket);

      GlobalVariableSet(mapKey, (double)slaveTicket);
      GlobalVariableSet(masterVolKey, masterLot);
      GlobalVariableSet(masterPriceKey, masterPrice);
   }
}

//+------------------------------------------------------------------+
//| Find slave position using GlobalVariable map first, comment fallback |
//+------------------------------------------------------------------+
ulong FindSlavePosition(long masterTicket)
{
   string mapKey = g_gvPrefix + "TMap_" + IntegerToString(masterTicket);
   if(GlobalVariableCheck(mapKey))
   {
      ulong savedTicket = (ulong)GlobalVariableGet(mapKey);
      if(PositionSelectByTicket(savedTicket))
         return savedTicket;
   }

   // Secondary fallback: search positions by comment tag
   string tag = "MC:" + IntegerToString(masterTicket);
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC) != SlaveMagic) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, tag) >= 0)
         return ticket;
   }

   return 0;
}

//+------------------------------------------------------------------+
void ExecuteClose(long masterTicket, double masterCloseLot)
{
   ulong slaveTicket = FindSlavePosition(masterTicket);
   if(slaveTicket == 0)
   {
      Print("No matching open position found for master ticket ", masterTicket,
            " (already closed manually, or was opened before this EA started).");
      return;
   }

   if(!PositionSelectByTicket(slaveTicket)) return;

   string symbol  = PositionGetString(POSITION_SYMBOL);
   double posVolume = PositionGetDouble(POSITION_VOLUME);
   long   posType = PositionGetInteger(POSITION_TYPE);

   // Calculate proportional volume for partial closes
   string masterVolKey = g_gvPrefix + "MVol_" + IntegerToString(masterTicket);
   double initialMasterVol = GlobalVariableCheck(masterVolKey) ? GlobalVariableGet(masterVolKey) : 0;

   double closeLot = posVolume; // default full close
   if(masterCloseLot > 0 && initialMasterVol > 0 && masterCloseLot < (initialMasterVol - 0.001))
   {
      // Proportional partial close
      double portion = masterCloseLot / initialMasterVol;
      closeLot = (FixedLot > 0) ? (FixedLot * portion) : (posVolume * portion);
      closeLot = NormalizeLot(closeLot);
      if(closeLot >= posVolume) closeLot = posVolume;
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   double closePrice = (posType == POSITION_TYPE_BUY)
                           ? SymbolInfoDouble(symbol, SYMBOL_BID)
                           : SymbolInfoDouble(symbol, SYMBOL_ASK);

   request.action       = TRADE_ACTION_DEAL;
   request.position     = slaveTicket;
   request.symbol       = symbol;
   request.volume       = closeLot;
   request.type         = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price        = closePrice;
   request.deviation    = MaxSlippagePts;
   request.magic        = SlaveMagic;
   request.type_filling = GetFillingMode(symbol);

   if(!OrderSend(request, result))
   {
      Print("Close failed for master ticket ", masterTicket, ": ", result.retcode, " ", result.comment);
   }
   else
   {
      Print("Closed ", DoubleToString(closeLot, 2), " lots on slave position ", slaveTicket, " for master ticket ", masterTicket);
      // Clean up Global Variables if position fully closed
      if(closeLot >= (posVolume - 0.001))
      {
         string mapKey = g_gvPrefix + "TMap_" + IntegerToString(masterTicket);
         string masterPriceKey = g_gvPrefix + "MPrice_" + IntegerToString(masterTicket);
         GlobalVariableDel(mapKey);
         GlobalVariableDel(masterVolKey);
         GlobalVariableDel(masterPriceKey);
      }
   }
}

//+------------------------------------------------------------------+
void ExecuteModify(long masterTicket, double sl, double tp, double masterPrice)
{
   ulong slaveTicket = FindSlavePosition(masterTicket);
   if(slaveTicket == 0) return;

   if(!PositionSelectByTicket(slaveTicket)) return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long posType = PositionGetInteger(POSITION_TYPE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits <= 0) digits = 2;

   double slavePrice = PositionGetDouble(POSITION_PRICE_OPEN);

   // Adjust SL/TP for Reverse Trade mode
   if(ReverseTrade && masterPrice > 0)
   {
      if(posType == POSITION_TYPE_SELL)
      {
         // Master BUY -> Slave SELL
         double slDist = (sl > 0) ? MathAbs(masterPrice - sl) : 0;
         double tpDist = (tp > 0) ? MathAbs(masterPrice - tp) : 0;
         sl = (slDist > 0) ? NormalizeDouble(slavePrice + slDist, digits) : 0;
         tp = (tpDist > 0) ? NormalizeDouble(slavePrice - tpDist, digits) : 0;
      }
      else if(posType == POSITION_TYPE_BUY)
      {
         // Master SELL -> Slave BUY
         double slDist = (sl > 0) ? MathAbs(sl - masterPrice) : 0;
         double tpDist = (tp > 0) ? MathAbs(tp - masterPrice) : 0;
         sl = (slDist > 0) ? NormalizeDouble(slavePrice - slDist, digits) : 0;
         tp = (tpDist > 0) ? NormalizeDouble(slavePrice + tpDist, digits) : 0;
      }
   }

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = slaveTicket;
   request.symbol   = symbol;
   request.sl       = NormalizeDouble(sl, digits);
   request.tp       = NormalizeDouble(tp, digits);

   if(!OrderSend(request, result))
      Print("SL/TP update failed for master ticket ", masterTicket, ": ", result.retcode);
   else
      Print("Updated SL/TP for slave position ", slaveTicket, " (SL: ", sl, ", TP: ", tp, ")");
}

//+------------------------------------------------------------------+
//| Minimal JSON field extraction - safe here because keys are quoted |
//+------------------------------------------------------------------+
string JsonGetString(string json, string key)
{
   string pattern = "\"" + key + "\"";
   int p = StringFind(json, pattern);
   if(p < 0) return "";
   p += StringLen(pattern);
   while(p < StringLen(json) && (StringGetCharacter(json, p) == ' ' || StringGetCharacter(json, p) == ':' || StringGetCharacter(json, p) == '\t' || StringGetCharacter(json, p) == '\r' || StringGetCharacter(json, p) == '\n'))
      p++;
   if(p >= StringLen(json) || StringGetCharacter(json, p) != '"')
      return "";
   p++;
   int q = StringFind(json, "\"", p);
   if(q < 0) return "";
   return StringSubstr(json, p, q - p);
}

double JsonGetNumber(string json, string key)
{
   string pattern = "\"" + key + "\"";
   int p = StringFind(json, pattern);
   if(p < 0) return 0;
   p += StringLen(pattern);
   while(p < StringLen(json) && (StringGetCharacter(json, p) == ' ' || StringGetCharacter(json, p) == ':' || StringGetCharacter(json, p) == '\t' || StringGetCharacter(json, p) == '\r' || StringGetCharacter(json, p) == '\n'))
      p++;
   int q = p;
   while(q < StringLen(json))
   {
      ushort c = StringGetCharacter(json, q);
      if(c == ',' || c == '}' || c == ']' || c == ' ' || c == '\r' || c == '\n') break;
      q++;
   }
   return StringToDouble(StringSubstr(json, p, q - p));
}

bool JsonGetBool(string json, string key)
{
   string pattern = "\"" + key + "\"";
   int p = StringFind(json, pattern);
   if(p < 0) return false;
   p += StringLen(pattern);
   while(p < StringLen(json) && (StringGetCharacter(json, p) == ' ' || StringGetCharacter(json, p) == ':' || StringGetCharacter(json, p) == '\t' || StringGetCharacter(json, p) == '\r' || StringGetCharacter(json, p) == '\n'))
      p++;
   return StringSubstr(json, p, 4) == "true";
}
//+------------------------------------------------------------------+
