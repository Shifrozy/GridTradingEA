//+------------------------------------------------------------------+
//|                                              GridTradingEA.mq5   |
//|                                        Developed by Murtaza      |
//|                         Grid Trading Bot - Production Ready      |
//+------------------------------------------------------------------+
#property copyright "Murtaza"
#property link      ""
#property version   "4.10"
#property description "Grid Trading EA - Fixed Distance Grid System"
#property description "Works on all symbols: Forex, Gold, Indices"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Grid Settings ==="
input double   InpLotSize           = 0.01;    // Lot Size (min 0.01)
input double   InpLevel0Price       = 0.0;     // Level 0 Price (0 = auto from current price)
input double   InpGridDistPrice     = 0.0;     // Grid Distance in PRICE (e.g. 5.0 for Gold = $5)
input int      InpGridDistPoints    = 0;       // Grid Distance in POINTS (used if Price dist = 0)
input double   InpTPDistPrice       = 0.0;     // TP Distance in PRICE (0 = same as Grid Distance)
input int      InpTPDistPoints      = 0;       // TP Distance in POINTS (used if Price dist = 0)

input group "=== Risk Management ==="
input int      InpMaxOpenPositions  = 5;       // Maximum Open Positions
input int      InpSlippage          = 30;      // Slippage (points)

input group "=== EA Settings ==="
input int      InpMagicNumber       = 123456;  // Magic Number
input bool     InpShowGridLines     = true;    // Show Grid Lines on Chart
input int      InpVisibleLevels     = 15;      // Grid Lines visible above/below price
input color    InpAnchorColor       = clrGold;       // Anchor Level (L0) Color
input color    InpActiveLevelColor  = clrLime;       // Active Trade Level Color
input color    InpInactiveLevelColor= clrGray;       // Inactive Level Color

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define MAX_LEVELS      101  // 50 below + anchor + 50 above
#define LEVELS_PER_SIDE 50

//+------------------------------------------------------------------+
//| Grid Level Structure                                              |
//+------------------------------------------------------------------+
struct GridLevel
  {
   int               levelIndex;      // -50 to +50
   double            price;           // Price of this level
   double            tpPrice;         // Take profit price
   bool              isActive;        // Has active trade?
   ulong             posTicket;       // Position ticket
   bool              priceWasAbove;   // Was price above this level? (for crossing)
  };

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
GridLevel         g_levels[MAX_LEVELS];
double            g_point;
int               g_digits;
string            g_symbol;
CTrade            g_trade;
double            g_gridDist;          // Grid distance in actual price
double            g_tpDist;            // TP distance in actual price
double            g_anchorPrice;       // Level 0 price
bool              g_stateInitialized;  // Price states initialized?

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Validate lot size
   if(InpLotSize < 0.01)
     {
      Alert("ERROR: Lot Size must be at least 0.01");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpMaxOpenPositions < 1)
     {
      Alert("ERROR: Maximum Open Positions must be at least 1");
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- Symbol info
   g_symbol = _Symbol;
   g_point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   if(g_point <= 0)
     {
      Alert("ERROR: Cannot get point value for ", g_symbol);
      return(INIT_FAILED);
     }

//--- Determine grid distance in PRICE
   if(InpGridDistPrice > 0)
     {
      g_gridDist = NormalizeDouble(InpGridDistPrice, g_digits);
     }
   else if(InpGridDistPoints > 0)
     {
      g_gridDist = NormalizeDouble(InpGridDistPoints * g_point, g_digits);
     }
   else
     {
      //--- Auto-detect reasonable grid distance based on symbol price
      double price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      if(price <= 0) price = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      if(price <= 0)
        {
         Alert("ERROR: Cannot determine price. Set Grid Distance manually.");
         return(INIT_PARAMETERS_INCORRECT);
        }

      //--- Smart auto-distance: ~0.2% of price
      g_gridDist = NormalizeDouble(price * 0.002, g_digits);
      //--- Round to a clean number
      if(g_gridDist >= 10)
         g_gridDist = MathRound(g_gridDist);
      else if(g_gridDist >= 1)
         g_gridDist = MathRound(g_gridDist * 10) / 10.0;

      g_gridDist = NormalizeDouble(g_gridDist, g_digits);
      Print("Auto Grid Distance: ", DoubleToString(g_gridDist, g_digits),
            " (", DoubleToString(g_gridDist / g_point, 0), " points)");
     }

   if(g_gridDist <= 0)
     {
      Alert("ERROR: Grid Distance must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- Determine TP distance in PRICE
   if(InpTPDistPrice > 0)
      g_tpDist = NormalizeDouble(InpTPDistPrice, g_digits);
   else if(InpTPDistPoints > 0)
      g_tpDist = NormalizeDouble(InpTPDistPoints * g_point, g_digits);
   else
      g_tpDist = g_gridDist; // Default: same as grid distance

//--- Determine anchor price
   if(InpLevel0Price > 0)
     {
      g_anchorPrice = NormalizeDouble(InpLevel0Price, g_digits);
     }
   else
     {
      double price = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      if(price <= 0) price = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      if(price <= 0)
        {
         Alert("ERROR: Cannot detect price. Set Level 0 manually.");
         return(INIT_PARAMETERS_INCORRECT);
        }
      //--- Snap to nearest grid level for clean numbers
      g_anchorPrice = MathRound(price / g_gridDist) * g_gridDist;
      g_anchorPrice = NormalizeDouble(g_anchorPrice, g_digits);
      Print("Auto Anchor Price: ", DoubleToString(g_anchorPrice, g_digits));
     }

//--- Setup CTrade
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);

   //--- Auto-detect filling mode
   long fillMode = SymbolInfoInteger(g_symbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

//--- Initialize grid levels
   InitializeGrid();

//--- State not initialized yet (will do on first tick)
   g_stateInitialized = false;

//--- Restore any existing positions
   RestoreStateFromPositions();

//--- Draw grid immediately on chart (so it shows even before first tick)
   if(InpShowGridLines)
     {
      double initBid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      if(initBid <= 0) initBid = g_anchorPrice;
      DrawGrid(initBid);
     }

//--- Print info
   Print("============================================");
   Print("  GRID TRADING EA v4.10 - Initialized");
   Print("============================================");
   Print("Symbol: ", g_symbol, " | Digits: ", g_digits, " | Point: ", DoubleToString(g_point, g_digits + 1));
   Print("Anchor (L0): ", DoubleToString(g_anchorPrice, g_digits));
   Print("Grid Distance: ", DoubleToString(g_gridDist, g_digits), " (", DoubleToString(g_gridDist / g_point, 0), " points)");
   Print("TP Distance: ", DoubleToString(g_tpDist, g_digits), " (", DoubleToString(g_tpDist / g_point, 0), " points)");
   Print("Lot: ", DoubleToString(InpLotSize, 2), " | Max Pos: ", InpMaxOpenPositions);
   Print("Grid Range: ", DoubleToString(g_levels[0].price, g_digits),
         " to ", DoubleToString(g_levels[MAX_LEVELS - 1].price, g_digits));
   Print("============================================");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "GE_");
   Comment("");
  }

//+------------------------------------------------------------------+
//| Initialize Grid Levels                                            |
//+------------------------------------------------------------------+
void InitializeGrid()
  {
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      int idx = i - LEVELS_PER_SIDE;
      g_levels[i].levelIndex    = idx;
      g_levels[i].price         = NormalizeDouble(g_anchorPrice + (idx * g_gridDist), g_digits);
      g_levels[i].tpPrice       = NormalizeDouble(g_levels[i].price + g_tpDist, g_digits);
      g_levels[i].isActive      = false;
      g_levels[i].posTicket     = 0;
      g_levels[i].priceWasAbove = false;
     }
  }

//+------------------------------------------------------------------+
//| Restore state from existing positions                             |
//+------------------------------------------------------------------+
void RestoreStateFromPositions()
  {
   int restored = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      int bestIdx = -1;
      double bestDist = DBL_MAX;
      for(int i = 0; i < MAX_LEVELS; i++)
        {
         double d = MathAbs(g_levels[i].price - openPrice);
         if(d < bestDist) { bestDist = d; bestIdx = i; }
        }

      if(bestIdx >= 0 && bestDist < g_gridDist * 0.5)
        {
         g_levels[bestIdx].isActive  = true;
         g_levels[bestIdx].posTicket = ticket;
         restored++;
         Print("Restored: L", g_levels[bestIdx].levelIndex,
               " @ ", DoubleToString(openPrice, g_digits), " #", ticket);
        }
     }
   if(restored > 0)
      Print("Restored ", restored, " positions");
  }

//+------------------------------------------------------------------+
//| OnTick - Main EA logic                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   if(bid <= 0) return;

//--- First tick: initialize price-above states for all levels
//--- This prevents triggering everything on startup
//--- But do NOT return - continue to draw grid
   if(!g_stateInitialized)
     {
      for(int i = 0; i < MAX_LEVELS; i++)
        {
         g_levels[i].priceWasAbove = (bid > g_levels[i].price);
        }
      g_stateInitialized = true;
      Print("Price states initialized at Bid: ", DoubleToString(bid, g_digits));
      //--- Draw grid and status on first tick, then return (no trading yet)
      int openCount = CountOpenPositions();
      ShowStatus(bid, openCount);
      if(InpShowGridLines)
         DrawGrid(bid);
      return;
     }

//--- Step 1: Check for closed positions
   ScanClosedPositions();

//--- Step 2: Count open positions
   int openCount = CountOpenPositions();

//--- Step 3: Check for level triggers
   if(openCount < InpMaxOpenPositions)
     {
      CheckLevelTriggers(bid, openCount);
     }

//--- Step 4: Update price-above state for ALL levels (for next tick)
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      if(!g_levels[i].isActive) // Only update non-active levels
         g_levels[i].priceWasAbove = (bid > g_levels[i].price);
     }

//--- Step 5: Update display
   static datetime lastUpdate = 0;
   if(TimeCurrent() != lastUpdate)
     {
      ShowStatus(bid, openCount);
      if(InpShowGridLines)
         DrawGrid(bid);
      lastUpdate = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
//| Scan for closed positions                                        |
//+------------------------------------------------------------------+
void ScanClosedPositions()
  {
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      if(!g_levels[i].isActive || g_levels[i].posTicket == 0)
         continue;

      if(!PositionSelectByTicket(g_levels[i].posTicket))
        {
         Print("<<< CLOSED: L", g_levels[i].levelIndex,
               " | Ticket: ", g_levels[i].posTicket, " | Level unlocked");
         g_levels[i].isActive      = false;
         g_levels[i].posTicket     = 0;
         g_levels[i].priceWasAbove = true; // Reset: needs to come from above again
        }
     }
  }

//+------------------------------------------------------------------+
//| Count open positions for this EA                                  |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Check level triggers - price crossing DOWN through a level       |
//+------------------------------------------------------------------+
void CheckLevelTriggers(double bid, int &openCount)
  {
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      //--- Skip active levels
      if(g_levels[i].isActive) continue;

      //--- Skip invalid prices
      if(g_levels[i].price <= 0) continue;

      double levelPrice = g_levels[i].price;

      //--- TRIGGER CONDITION:
      //--- Price WAS above this level before, and NOW is at or below it
      //--- This means price has come DOWN to this level = time to Buy
      if(g_levels[i].priceWasAbove && bid <= levelPrice)
        {
         //--- Check max positions
         if(openCount >= InpMaxOpenPositions)
           {
            Print("MAX POS reached. Skipping L", g_levels[i].levelIndex);
            return; // Stop checking more levels
           }

         //--- Open Buy
         if(ExecuteBuy(i))
           {
            openCount++;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute Buy order at a grid level                                 |
//+------------------------------------------------------------------+
bool ExecuteBuy(int idx)
  {
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   if(ask <= 0) return false;

   double tp = g_levels[idx].tpPrice;
   double lotSize = ValidateLotSize(InpLotSize);
   if(lotSize <= 0) return false;

   string comment = "Grid_L" + IntegerToString(g_levels[idx].levelIndex);

   Print(">>> BUY ATTEMPT: L", g_levels[idx].levelIndex,
         " | Level: ", DoubleToString(g_levels[idx].price, g_digits),
         " | Ask: ", DoubleToString(ask, g_digits),
         " | TP: ", DoubleToString(tp, g_digits));

   if(g_trade.Buy(lotSize, g_symbol, ask, 0, tp, comment))
     {
      ulong posTicket = g_trade.ResultOrder();
      if(posTicket == 0) posTicket = g_trade.ResultDeal();

      g_levels[idx].isActive  = true;
      g_levels[idx].posTicket = posTicket;

      Print(">>> BUY SUCCESS: L", g_levels[idx].levelIndex,
            " | Filled: ", DoubleToString(g_trade.ResultPrice(), g_digits),
            " | TP: ", DoubleToString(tp, g_digits),
            " | Ticket: ", posTicket);
      return true;
     }
   else
     {
      Print(">>> BUY FAILED: L", g_levels[idx].levelIndex,
            " | Error: ", GetLastError(),
            " | Code: ", g_trade.ResultRetcode(),
            " | ", g_trade.ResultComment());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Validate lot size                                                 |
//+------------------------------------------------------------------+
double ValidateLotSize(double lots)
  {
   double minLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0) lotStep = 0.01;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Get the time of the right edge of the visible chart              |
//+------------------------------------------------------------------+
datetime GetChartRightTime()
  {
   //--- Get the time of the right visible edge of the chart
   int firstBar  = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int visBars   = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   int rightBar  = firstBar - visBars;
   if(rightBar < 0) rightBar = 0;

   //--- Get the time of a bar near the right edge (a few bars from right)
   datetime barTimes[];
   int copied = CopyTime(g_symbol, Period(), rightBar, 1, barTimes);
   if(copied > 0)
      return barTimes[0];

   //--- Fallback: use current time + a few periods
   return TimeCurrent() + PeriodSeconds() * 3;
  }

//+------------------------------------------------------------------+
//| Draw grid lines on chart                                          |
//+------------------------------------------------------------------+
void DrawGrid(double bid)
  {
   int visLevels = InpVisibleLevels;
   if(visLevels <= 0) visLevels = 10;
   if(visLevels > LEVELS_PER_SIDE) visLevels = LEVELS_PER_SIDE;

//--- Find the level index closest to current bid
   int centerIdx = 0;
   double minD = DBL_MAX;
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      double d = MathAbs(bid - g_levels[i].price);
      if(d < minD) { minD = d; centerIdx = i; }
     }

//--- Calculate visible range
   int startIdx = MathMax(0, centerIdx - visLevels);
   int endIdx   = MathMin(MAX_LEVELS - 1, centerIdx + visLevels);

//--- Remove lines outside visible range
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      if(i < startIdx || i > endIdx)
        {
         ObjectDelete(0, "GE_H" + IntegerToString(g_levels[i].levelIndex));
         ObjectDelete(0, "GE_T" + IntegerToString(g_levels[i].levelIndex));
        }
     }

//--- Get right edge time for text label placement
   datetime rightTime = GetChartRightTime();

//--- Draw visible levels
   for(int i = startIdx; i <= endIdx; i++)
     {
      if(g_levels[i].price <= 0) continue;

      int lvl = g_levels[i].levelIndex;
      string hName = "GE_H" + IntegerToString(lvl);
      string tName = "GE_T" + IntegerToString(lvl);

      //--- Determine style based on level state
      color  lColor;
      int    lWidth;
      ENUM_LINE_STYLE lStyle;
      string lLabel;
      string shortLabel;

      if(lvl == 0)
        {
         lColor = InpAnchorColor;
         lWidth = 2;
         lStyle = STYLE_SOLID;
         lLabel = "ANCHOR L0 [" + DoubleToString(g_levels[i].price, g_digits) + "]";
         shortLabel = "  << L0 ANCHOR >>";
        }
      else if(g_levels[i].isActive)
        {
         lColor = InpActiveLevelColor;
         lWidth = 2;
         lStyle = STYLE_SOLID;
         lLabel = "L" + IntegerToString(lvl) + " [ACTIVE] TP:" + DoubleToString(g_levels[i].tpPrice, g_digits);
         shortLabel = "  L" + IntegerToString(lvl) + " [ACTIVE]";
        }
      else
        {
         lColor = InpInactiveLevelColor;
         lWidth = 1;
         lStyle = STYLE_DOT;
         lLabel = "L" + IntegerToString(lvl) + " [" + DoubleToString(g_levels[i].price, g_digits) + "]";
         shortLabel = "  L" + IntegerToString(lvl);
        }

      //--- HORIZONTAL LINE (always visible across entire chart)
      if(ObjectFind(0, hName) < 0)
        {
         ObjectCreate(0, hName, OBJ_HLINE, 0, 0, g_levels[i].price);
        }
      ObjectSetDouble(0, hName, OBJPROP_PRICE, g_levels[i].price);
      ObjectSetInteger(0, hName, OBJPROP_COLOR, lColor);
      ObjectSetInteger(0, hName, OBJPROP_WIDTH, lWidth);
      ObjectSetInteger(0, hName, OBJPROP_STYLE, lStyle);
      ObjectSetInteger(0, hName, OBJPROP_BACK, false);  // FOREGROUND so always visible
      ObjectSetInteger(0, hName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, hName, OBJPROP_HIDDEN, true); // Hide from object list
      ObjectSetInteger(0, hName, OBJPROP_RAY, true);
      ObjectSetString(0, hName, OBJPROP_TEXT, lLabel);
      ObjectSetString(0, hName, OBJPROP_TOOLTIP, lLabel);

      //--- TEXT LABEL at right edge of visible chart
      if(ObjectFind(0, tName) < 0)
        {
         ObjectCreate(0, tName, OBJ_TEXT, 0, rightTime, g_levels[i].price);
        }
      ObjectSetDouble(0, tName, OBJPROP_PRICE, g_levels[i].price);
      ObjectSetInteger(0, tName, OBJPROP_TIME, rightTime);
      ObjectSetString(0, tName, OBJPROP_TEXT, shortLabel);
      ObjectSetInteger(0, tName, OBJPROP_COLOR, lColor);
      ObjectSetInteger(0, tName, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, tName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, tName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, tName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tName, OBJPROP_HIDDEN, true);
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Show status comment on chart                                      |
//+------------------------------------------------------------------+
void ShowStatus(double bid, int openCount)
  {
   //--- Nearest level
   int nearLvl = 0;
   double minD = DBL_MAX;
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      double d = MathAbs(bid - g_levels[i].price);
      if(d < minD) { minD = d; nearLvl = g_levels[i].levelIndex; }
     }

   //--- Active levels
   string actStr = "";
   int ac = 0;
   for(int i = 0; i < MAX_LEVELS; i++)
     {
      if(g_levels[i].isActive)
        {
         if(ac > 0) actStr += ", ";
         actStr += "L" + IntegerToString(g_levels[i].levelIndex);
         ac++;
        }
     }
   if(ac == 0) actStr = "None";

   string st = (openCount >= InpMaxOpenPositions) ? "PAUSED (Max reached)" : "ACTIVE";

   string txt = "\n";
   txt += "  ==========================================\n";
   txt += "         GRID TRADING EA v4.10\n";
   txt += "  ==========================================\n";
   txt += "  Symbol: " + g_symbol + "\n";
   txt += "  Anchor (L0): " + DoubleToString(g_anchorPrice, g_digits) + "\n";
   txt += "  Bid: " + DoubleToString(bid, g_digits) + "\n";
   txt += "  Nearest: L" + IntegerToString(nearLvl) + "\n";
   txt += "  ------------------------------------------\n";
   txt += "  Positions: " + IntegerToString(openCount) + "/" + IntegerToString(InpMaxOpenPositions) + "\n";
   txt += "  Active: " + actStr + "\n";
   txt += "  ------------------------------------------\n";
   txt += "  Lot: " + DoubleToString(InpLotSize, 2) + "\n";
   txt += "  Grid Dist: " + DoubleToString(g_gridDist, g_digits) + "\n";
   txt += "  TP Dist: " + DoubleToString(g_tpDist, g_digits) + "\n";
   txt += "  Status: " + st + "\n";
   txt += "  ==========================================\n";

   Comment(txt);
  }

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == g_symbol)
      Print("Deal event: #", trans.deal, " | ", EnumToString(trans.deal_type));
  }

//+------------------------------------------------------------------+
