# BrainEA.mq5 — Installation & Configuration

## Installation

1. Open MetaTrader 5 and go to **File → Open Data Folder**.
2. Navigate to `MQL5/Experts/` and copy `BrainEA.mq5` into that folder.
3. Open MetaEditor, refresh the Navigator, and compile `BrainEA.mq5`.
4. Attach **BrainEA** to any MT5 chart. The chart symbol/timeframe does not matter because the EA scans every configured market internally.

## Timer & performance settings

| Input name | Default | Description |
|------------|---------|-------------|
| `TimerSeconds` | `5` | Frequency of the OnTimer scan loop (seconds). |
| `DuplicateMinutes` | `5` | Minimum minutes between identical signals (same symbol + strategy). |
| `SessionLondonStart`/`SessionLondonEnd` | `08:00` / `11:00` | Broker-time definition of the London session used by Goldmine and UT filters. |
| `SessionNYStart`/`SessionNYEnd` | `15:00` / `16:00` | Broker-time definition of the New York "Silver Bullet" session. |
| `ScreenshotDelaySeconds` | `2` | Delay before opening/arranging charts so the helper captures the correct layout. |
| `TemplateName` | `AI_ICT_Template.tpl` | Template applied to each chart when a signal triggers. |
| `VolatilityMinATR` | `0.0005` | Minimum ATR value for the UT + Linear Regression strategy. |
| `MaxSpreadPoints` | `35` | Spread filter in points for UT + Linear Regression. |

## Strategy logic summary

- **Goldmine (Asian Liquidity Trap)**: XAUUSD only. Requires matching H4/H1 trend, London session, Asian range break with liquidity sweep, displacement and FVG confirmation, plus M1 CHoCH.
- **Silver Bullet (NY CRT)**: Active during the configured NY window across all symbols. Looks for prior liquidity grab, displacement, FVG, and M1 CHoCH.
- **UT + Linear Regression**: Works on every symbol. Requires UT Bot signals and linear regression slopes aligned with H1 trend, while volatility/spread filters pass.

Each scan populates a `SymbolContext` struct using built-in price data, custom indicators (`UT_Bot.ex5`, `LinearRegressionSlope.ex5`), and standard ATR. Missing data or indicator handles are handled gracefully (signal is skipped).

## Output files

Signals are written under `MQL5/Files/signals/` (terminal data folder):

- `latest_signal.txt`: overwritten with the most recent signal (key-value pairs).
- `signals_log.csv`: append-only journal of every detected setup.

The EA automatically opens six charts (M1, M5, M15, H1, H4, D1) for the symbol, applies `AI_ICT_Template.tpl`, and arranges them in a 2×3 grid so the helper application can capture a consistent screenshot.

## Troubleshooting

- Ensure all required indicators (`UT_Bot.ex5`, `LinearRegressionSlope.ex5`) are copied to `MQL5/Indicators/`.
- The EA runs on a timer; it does **not** depend on incoming ticks. Keep MT5 connected so historical data loads for every symbol and timeframe.
- If no signals appear, enable the Experts log to confirm that session times and indicator handles are valid.
- Adjust `SessionNYStart`/`SessionNYEnd` to match your broker’s offset from New York time.
