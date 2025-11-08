#property copyright "AI Helper"
#property version   "1.00"
#property strict

#include <Arrays/ArrayObj.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Map.mqh>

input int      TimerSeconds           = 5;        // Timer frequency
input int      DuplicateMinutes       = 5;        // Minimum minutes between identical signals
input string   SessionLondonStart     = "08:00";  // Broker time
input string   SessionLondonEnd       = "11:00";
input string   SessionNYStart         = "15:00";  // Default 10:00 NY adjust for broker offset
input string   SessionNYEnd           = "16:00";
input int      ScreenshotDelaySeconds = 2;        // Wait before arranging charts
input string   TemplateName           = "AI_ICT_Template.tpl";
input double   VolatilityMinATR       = 0.0005;
input double   MaxSpreadPoints        = 35;

//--- constants
enum StrategyType
  {
   STRATEGY_GOLDMINE = 0,
   STRATEGY_SILVERBULLET,
   STRATEGY_UT_LR
  };

string StrategyNames[3] =
  {
   "Goldmine",
   "SilverBullet",
   "UT_LinearRegression"
  };

string SessionNames[3] =
  {
   "London",
   "NewYork",
   "Unknown"
  };

struct SymbolContext
  {
   string symbol;
   ENUM_TIMEFRAMES tfScanning[];
   int h4Trend;
   int h1Trend;
   bool h4InPremium;
   bool h1InDiscount;
   bool asiaRangeDefined;
   bool asiaRangeBroken;
   bool londonSession;
   bool nySession;
   bool liquiditySweptUp;
   bool liquiditySweptDown;
   bool fvgCreatedM5;
   bool displacementM15;
   bool chochM1;
   int utSignalM5;
   int utSignalM15;
   double linRegSlopeM5;
   double linRegSlopeM15;
   bool volatilityOK;
   bool spreadOK;
   datetime lastBarTime; // reference for duplicate control
  };

//--- globals
string g_symbols[] = {"XAUUSD","GBPJPY","NAS100","BTCUSD","EURUSD"};
ENUM_TIMEFRAMES g_timeframes[] = {PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_H1,PERIOD_H4,PERIOD_D1};
CMapStringToString g_lastSignalTimes;

//--- helper prototypes
bool   BuildContext(const string symbol, SymbolContext &ctx);
bool   CheckGoldmine(SymbolContext &ctx, string &sessionName);
bool   CheckSilverBullet(SymbolContext &ctx, string &sessionName);
bool   CheckUTLinear(SymbolContext &ctx, string &sessionName);
int    DetectTrend(const string symbol, ENUM_TIMEFRAMES tf);
bool   IsPremium(const string symbol, ENUM_TIMEFRAMES tf);
bool   IsDiscount(const string symbol, ENUM_TIMEFRAMES tf);
bool   DetectLiquiditySweep(const string symbol, ENUM_TIMEFRAMES tf, bool up);
bool   DetectFVG(const string symbol, ENUM_TIMEFRAMES tf);
bool   DetectDisplacement(const string symbol, ENUM_TIMEFRAMES tf);
bool   DetectCHOCH(const string symbol, ENUM_TIMEFRAMES tf);
int    ReadUTSignal(const string symbol, ENUM_TIMEFRAMES tf);
double ReadLinRegSlope(const string symbol, ENUM_TIMEFRAMES tf);
bool   CheckVolatility(const string symbol, ENUM_TIMEFRAMES tf);
bool   CheckSpread(const string symbol);
void   LogSignal(const string symbol, const string strategy, const string session);
bool   CanEmitSignal(const string symbol, const string strategy, datetime now);
string BuildDuplicateKey(const string symbol, const string strategy);
void   ArrangeCharts(const string symbol);
bool   IsTimeWithin(const datetime current, const string startStr, const string endStr);
string FormatDateTime(const datetime value);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(TimerSeconds);
   g_lastSignalTimes.Init(20);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();

   for(int i=0; i<ArraySize(g_symbols); i++)
     {
      SymbolContext ctx;
      if(!BuildContext(g_symbols[i], ctx))
         continue;

      string sessionName = SessionNames[2];
      if(CheckGoldmine(ctx, sessionName))
        {
         if(CanEmitSignal(ctx.symbol, StrategyNames[STRATEGY_GOLDMINE], now))
           {
            LogSignal(ctx.symbol, StrategyNames[STRATEGY_GOLDMINE], sessionName);
            ArrangeCharts(ctx.symbol);
           }
         continue;
        }
      if(CheckSilverBullet(ctx, sessionName))
        {
         if(CanEmitSignal(ctx.symbol, StrategyNames[STRATEGY_SILVERBULLET], now))
           {
            LogSignal(ctx.symbol, StrategyNames[STRATEGY_SILVERBULLET], sessionName);
            ArrangeCharts(ctx.symbol);
           }
         continue;
        }
      if(CheckUTLinear(ctx, sessionName))
        {
         if(CanEmitSignal(ctx.symbol, StrategyNames[STRATEGY_UT_LR], now))
           {
            LogSignal(ctx.symbol, StrategyNames[STRATEGY_UT_LR], sessionName);
            ArrangeCharts(ctx.symbol);
           }
        }
     }
  }

//+------------------------------------------------------------------+
bool BuildContext(const string symbol, SymbolContext &ctx)
  {
   if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
      if(!SymbolSelect(symbol, true))
         return(false);

  ctx.symbol = symbol;
  ArrayResize(ctx.tfScanning, ArraySize(g_timeframes));
  ArrayCopy(ctx.tfScanning, g_timeframes);

   ctx.h4Trend = DetectTrend(symbol, PERIOD_H4);
   ctx.h1Trend = DetectTrend(symbol, PERIOD_H1);
   ctx.h4InPremium = IsPremium(symbol, PERIOD_H4);
   ctx.h1InDiscount = IsDiscount(symbol, PERIOD_H1);

   ctx.asiaRangeDefined = true; // placeholder, assume defined if data exists
   ctx.asiaRangeBroken = DetectLiquiditySweep(symbol, PERIOD_M15, true) || DetectLiquiditySweep(symbol, PERIOD_M15, false);

   datetime now = TimeCurrent();
   ctx.londonSession = IsTimeWithin(now, SessionLondonStart, SessionLondonEnd);
   ctx.nySession = IsTimeWithin(now, SessionNYStart, SessionNYEnd);

  ctx.liquiditySweptUp = DetectLiquiditySweep(symbol, PERIOD_M15, true);
  ctx.liquiditySweptDown = DetectLiquiditySweep(symbol, PERIOD_M15, false);
   ctx.fvgCreatedM5 = DetectFVG(symbol, PERIOD_M5);
   ctx.displacementM15 = DetectDisplacement(symbol, PERIOD_M15);
   ctx.chochM1 = DetectCHOCH(symbol, PERIOD_M1);
   ctx.utSignalM5 = ReadUTSignal(symbol, PERIOD_M5);
   ctx.utSignalM15 = ReadUTSignal(symbol, PERIOD_M15);
   ctx.linRegSlopeM5 = ReadLinRegSlope(symbol, PERIOD_M5);
   ctx.linRegSlopeM15 = ReadLinRegSlope(symbol, PERIOD_M15);
   ctx.volatilityOK = CheckVolatility(symbol, PERIOD_M15);
   ctx.spreadOK = CheckSpread(symbol);

   datetime timeArray[];
   if(CopyTime(symbol, PERIOD_M1, 0, 1, timeArray) == 1)
      ctx.lastBarTime = timeArray[0];
   else
      ctx.lastBarTime = now;

   return(true);
  }

//+------------------------------------------------------------------+
bool CheckGoldmine(SymbolContext &ctx, string &sessionName)
  {
   if(ctx.symbol != "XAUUSD")
      return(false);

   if(!ctx.londonSession)
      return(false);

   sessionName = SessionNames[0];

   if(ctx.h4Trend == 0 || ctx.h4Trend != ctx.h1Trend)
      return(false);

   bool biasBull = (ctx.h4Trend > 0);

   if(biasBull)
     {
      if(!(ctx.asiaRangeBroken && ctx.liquiditySweptDown))
         return(false);
     }
   else
     {
      if(!(ctx.asiaRangeBroken && ctx.liquiditySweptUp))
         return(false);
     }

   if(!(ctx.displacementM15 && ctx.fvgCreatedM5))
      return(false);

   if(!ctx.chochM1)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
bool CheckSilverBullet(SymbolContext &ctx, string &sessionName)
  {
   if(!ctx.nySession)
      return(false);

   sessionName = SessionNames[1];

   if(!(ctx.liquiditySweptUp || ctx.liquiditySweptDown))
      return(false);

   if(!(ctx.displacementM15 && ctx.fvgCreatedM5))
      return(false);

   if(!ctx.chochM1)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
bool CheckUTLinear(SymbolContext &ctx, string &sessionName)
  {
   if(!(ctx.volatilityOK && ctx.spreadOK))
      return(false);

   int trend = ctx.h1Trend;
   bool slopeAligned = (trend > 0 && ctx.linRegSlopeM5 > 0 && ctx.linRegSlopeM15 > 0) ||
                       (trend < 0 && ctx.linRegSlopeM5 < 0 && ctx.linRegSlopeM15 < 0);

   if(!slopeAligned)
      return(false);

   bool utAligned = (trend > 0 && ctx.utSignalM5 > 0 && ctx.utSignalM15 > 0) ||
                    (trend < 0 && ctx.utSignalM5 < 0 && ctx.utSignalM15 < 0);

   if(!utAligned)
      return(false);

   sessionName = ctx.londonSession ? SessionNames[0] : (ctx.nySession ? SessionNames[1] : SessionNames[2]);

   return(true);
  }

//+------------------------------------------------------------------+
int DetectTrend(const string symbol, ENUM_TIMEFRAMES tf)
  {
   int periodFast = 20;
   int periodSlow = 50;
   int handleFast = iMA(symbol, tf, periodFast, 0, MODE_EMA, PRICE_CLOSE);
   int handleSlow = iMA(symbol, tf, periodSlow, 0, MODE_EMA, PRICE_CLOSE);
   if(handleFast == INVALID_HANDLE || handleSlow == INVALID_HANDLE)
     {
      if(handleFast != INVALID_HANDLE)
         IndicatorRelease(handleFast);
      if(handleSlow != INVALID_HANDLE)
         IndicatorRelease(handleSlow);
      return(0);
     }

   double maFast[3];
   double maSlow[3];
   if(CopyBuffer(handleFast, 0, 0, 3, maFast) < 1 || CopyBuffer(handleSlow, 0, 0, 3, maSlow) < 1)
     {
      IndicatorRelease(handleFast);
      IndicatorRelease(handleSlow);
      return(0);
     }
   IndicatorRelease(handleFast);
   IndicatorRelease(handleSlow);

   if(maFast[0] > maSlow[0])
      return(1);
   if(maFast[0] < maSlow[0])
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
bool IsPremium(const string symbol, ENUM_TIMEFRAMES tf)
  {
   double high[], low[];
   if(CopyHigh(symbol, tf, 0, 50, high) < 50)
      return(false);
   if(CopyLow(symbol, tf, 0, 50, low) < 50)
      return(false);

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   double current = iClose(symbol, tf, 0);
   int idxMax = ArrayMaximum(high, 0, 50);
   int idxMin = ArrayMinimum(low, 0, 50);
   double range = high[idxMax];
   double minv = low[idxMin];
   double mid = (range + minv)/2.0;
   return(current > mid);
  }

bool IsDiscount(const string symbol, ENUM_TIMEFRAMES tf)
  {
   double high[], low[];
   if(CopyHigh(symbol, tf, 0, 50, high) < 50)
      return(false);
   if(CopyLow(symbol, tf, 0, 50, low) < 50)
      return(false);

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   double current = iClose(symbol, tf, 0);
   int idxMax = ArrayMaximum(high, 0, 50);
   int idxMin = ArrayMinimum(low, 0, 50);
   double range = high[idxMax];
   double minv = low[idxMin];
   double mid = (range + minv)/2.0;
   return(current < mid);
  }

//+------------------------------------------------------------------+
bool DetectLiquiditySweep(const string symbol, ENUM_TIMEFRAMES tf, bool up)
  {
   double highs[], lows[];
   if(CopyHigh(symbol, tf, 0, 5, highs) < 5)
      return(false);
   if(CopyLow(symbol, tf, 0, 5, lows) < 5)
      return(false);

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if(up)
     {
      double prevHigh = highs[1];
      double currentHigh = highs[0];
      double currentClose = iClose(symbol, tf, 0);
      return(currentHigh > prevHigh && currentClose < prevHigh);
     }
   else
     {
      double prevLow = lows[1];
      double currentLow = lows[0];
      double currentClose = iClose(symbol, tf, 0);
      return(currentLow < prevLow && currentClose > prevLow);
     }
  }

//+------------------------------------------------------------------+
bool DetectFVG(const string symbol, ENUM_TIMEFRAMES tf)
  {
   double highs[3], lows[3];
   if(CopyHigh(symbol, tf, 0, 3, highs) < 3)
      return(false);
   if(CopyLow(symbol, tf, 0, 3, lows) < 3)
      return(false);

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   bool bullishGap = lows[0] > highs[2];
   bool bearishGap = highs[0] < lows[2];
   return(bullishGap || bearishGap);
  }

//+------------------------------------------------------------------+
bool DetectDisplacement(const string symbol, ENUM_TIMEFRAMES tf)
  {
   double close[];
   if(CopyClose(symbol, tf, 0, 6, close) < 6)
      return(false);
   ArraySetAsSeries(close, true);
   double body = MathAbs(close[0] - close[1]);
   double avgBody = 0.0;
   for(int i=1; i<5; i++)
      avgBody += MathAbs(close[i] - close[i+1]);
   avgBody /= 4.0;
   return(body > 1.5 * avgBody);
  }

//+------------------------------------------------------------------+
bool DetectCHOCH(const string symbol, ENUM_TIMEFRAMES tf)
  {
   double highs[], lows[];
   if(CopyHigh(symbol, tf, 0, 5, highs) < 5)
      return(false);
   if(CopyLow(symbol, tf, 0, 5, lows) < 5)
      return(false);

   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   bool breakUp = highs[0] > highs[2] && lows[0] > lows[2];
   bool breakDown = lows[0] < lows[2] && highs[0] < highs[2];
   return(breakUp || breakDown);
  }

//+------------------------------------------------------------------+
int ReadUTSignal(const string symbol, ENUM_TIMEFRAMES tf)
  {
   int handle = iCustom(symbol, tf, "UT_Bot", 1.5, 1.7, false);
   if(handle == INVALID_HANDLE)
      return(0);

   double buffer[];
   if(CopyBuffer(handle, 0, 0, 3, buffer) < 1)
     {
      IndicatorRelease(handle);
      return(0);
     }
   IndicatorRelease(handle);

   if(buffer[0] > 0.0)
      return(1);
   if(buffer[0] < 0.0)
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
double ReadLinRegSlope(const string symbol, ENUM_TIMEFRAMES tf)
  {
   int handle = iCustom(symbol, tf, "LinearRegressionSlope", 34);
   if(handle == INVALID_HANDLE)
      return(0.0);
   double buffer[];
   if(CopyBuffer(handle, 0, 0, 2, buffer) < 1)
     {
      IndicatorRelease(handle);
      return(0.0);
     }
   IndicatorRelease(handle);
   return(buffer[0]);
  }

//+------------------------------------------------------------------+
bool CheckVolatility(const string symbol, ENUM_TIMEFRAMES tf)
  {
   int handle = iATR(symbol, tf, 14);
   if(handle == INVALID_HANDLE)
      return(false);
   double buffer[2];
   if(CopyBuffer(handle, 0, 0, 2, buffer) < 1)
     {
      IndicatorRelease(handle);
      return(false);
     }
   IndicatorRelease(handle);
   return(buffer[0] >= VolatilityMinATR);
  }

//+------------------------------------------------------------------+
bool CheckSpread(const string symbol)
  {
   double spread = SymbolInfoDouble(symbol, SYMBOL_SPREAD);
   if(spread == 0.0)
      spread = (SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID)) / SymbolInfoDouble(symbol, SYMBOL_POINT);
   return(spread <= MaxSpreadPoints || spread == 0.0);
  }

//+------------------------------------------------------------------+
bool CanEmitSignal(const string symbol, const string strategy, datetime now)
  {
   string key = BuildDuplicateKey(symbol, strategy);
   string prev;
   if(g_lastSignalTimes.Get(key, prev))
     {
      datetime prevTime = StringToTime(prev);
      if(now - prevTime < DuplicateMinutes * 60)
         return(false);
     }
   g_lastSignalTimes.SetAt(key, FormatDateTime(now));
   return(true);
  }

//+------------------------------------------------------------------+
string BuildDuplicateKey(const string symbol, const string strategy)
  {
   return(symbol + "|" + strategy);
  }

//+------------------------------------------------------------------+
void LogSignal(const string symbol, const string strategy, const string session)
  {
   datetime now = TimeCurrent();
   string formatted = FormatDateTime(now);

   string folder = "signals";
   string latestFile = folder + "\\latest_signal.txt";
   string logFile = folder + "\\signals_log.csv";

   FolderCreate(folder);

   int handleLatest = FileOpen(latestFile, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(handleLatest != INVALID_HANDLE)
     {
      FileWrite(handleLatest, "timestamp=" + formatted);
      FileWrite(handleLatest, "symbol=" + symbol);
      FileWrite(handleLatest, "strategy=" + strategy);
      FileWrite(handleLatest, "session=" + session);
      FileClose(handleLatest);
     }

   bool exists = FileIsExist(logFile, FILE_COMMON);
   int handleLog = FileOpen(logFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(handleLog != INVALID_HANDLE)
     {
      if(!exists)
         FileWrite(handleLog, "timestamp,symbol,strategy,session");
      FileSeek(handleLog, 0, SEEK_END);
      FileWrite(handleLog, formatted + "," + symbol + "," + strategy + "," + session);
      FileClose(handleLog);
     }
  }

//+------------------------------------------------------------------+
void ArrangeCharts(const string symbol)
  {
   Sleep(ScreenshotDelaySeconds * 1000);

   long charts[6];
   ArrayInitialize(charts, 0);
   for(int i=0; i<ArraySize(g_timeframes); i++)
     {
      long chartID = ChartOpen(symbol, g_timeframes[i]);
      if(chartID == 0)
         continue;
      charts[i] = chartID;
      ChartApplyTemplate(chartID, TemplateName);
     }

   int screenWidth = 1600;
   int screenHeight = 900;
   int cellWidth = screenWidth / 3;
   int cellHeight = screenHeight / 2;

   for(int i=0; i<ArraySize(g_timeframes); i++)
     {
      long chartID = charts[i];
      if(chartID == 0)
         continue;
      int row = i / 3;
      int col = i % 3;
      ChartSetInteger(chartID, CHART_WIDTH_IN_PIXELS, cellWidth);
      ChartSetInteger(chartID, CHART_HEIGHT_IN_PIXELS, cellHeight);
      ChartSetInteger(chartID, CHART_WINDOW_X, col * cellWidth);
      ChartSetInteger(chartID, CHART_WINDOW_Y, row * cellHeight);
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
bool IsTimeWithin(const datetime current, const string startStr, const string endStr)
  {
   string dateStr = TimeToString(current, TIME_DATE);
   datetime startTime = StringToTime(dateStr + " " + startStr);
   datetime endTime = StringToTime(dateStr + " " + endStr);
   if(startTime == 0 || endTime == 0)
      return(false);
   if(endTime < startTime)
     {
      // session crosses midnight
      if(current >= startTime)
         return(true);
      return(current <= endTime);
     }
   return(current >= startTime && current <= endTime);
  }

//+------------------------------------------------------------------+
string FormatDateTime(const datetime value)
  {
   return(TimeToString(value, TIME_DATE|TIME_SECONDS));
  }

//+------------------------------------------------------------------+
