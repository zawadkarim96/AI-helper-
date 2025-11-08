# HelperApp.exe — Windows Assistant

The helper application watches the EA's signal files, captures MetaTrader 5 screenshots, updates the local journal, and pushes Telegram alerts.

## Files

- `build/`: publish output location (create via `dotnet publish`).
- `config.sample.json`: template configuration. Copy to `config.json` and edit.
- `src/`: full C# source code if you want to rebuild.

## Configuration

Create `config.json` next to `HelperApp.exe`:

```json
{
  "mt5WindowTitle": "MetaTrader 5 - Terminal",
  "signalsFolder": "C:\\Users\\you\\AppData\\Roaming\\MetaQuotes\\Terminal\\<id>\\MQL5\\Files\\signals",
  "journalFolder": "C:\\AI_Trading_Brain\\journal",
  "telegramBotToken": "123456:ABCDEF",
  "telegramChatId": "123456789",
  "pollIntervalSeconds": 3,
  "duplicateMinutes": 5,
  "screenshotDelaySeconds": 2,
  "screenshotRegion": {
    "x": 0,
    "y": 0,
    "width": 0,
    "height": 0
  }
}
```

### Field reference

| Field | Description |
|-------|-------------|
| `mt5WindowTitle` | Exact title of the MetaTrader 5 terminal window to capture. |
| `signalsFolder` | Path to `MQL5/Files/signals/` created by the EA. |
| `journalFolder` | Destination for screenshots and `trade_memory.csv`. |
| `telegramBotToken` | Bot token from [@BotFather](https://t.me/BotFather). Leave blank to disable Telegram. |
| `telegramChatId` | Chat ID (user or group) that will receive alerts. |
| `pollIntervalSeconds` | How often the helper checks for new signals. |
| `duplicateMinutes` | Minimum minutes between processing identical symbol + strategy combinations. |
| `screenshotDelaySeconds` | Wait period after detecting a signal before capturing MT5 (allows charts to finish loading). |
| `screenshotRegion` | Optional custom region for the screenshot. Use zeros to capture the full window. |

## Telegram setup

1. Talk to **@BotFather**, create a new bot, and copy the token.
2. Send a message to your bot, then use `https://api.telegram.org/bot<TOKEN>/getUpdates` to obtain your chat ID.
3. Insert both values into `config.json`.
4. Keep the helper running; alerts arrive via `sendPhoto` (with screenshot) when a setup fires.

## Output structure

```
<journalFolder>/
 ├── trade_memory.csv
 └── YYYY-MM-DD/
      └── SYMBOL_Strategy_Session_HH-mm-ss.png
```

- `trade_memory.csv` always contains `datetime,symbol,strategy,session,screenshot_path,status,result_R,notes` with default status `pending` and result `0`.
- You can add result metrics later without breaking the helper.

## Troubleshooting

- If you see `MT5 window not found`, confirm the window title matches exactly (including broker name).
- The helper writes `helper_log.txt` beside the executable. Check this log for JSON parsing errors or Telegram API responses.
- Screenshots rely on GDI. Ensure MT5 is visible on the desktop (not minimized) and the helper runs with sufficient permissions.
- Leave `telegramBotToken` or `telegramChatId` empty to temporarily disable Telegram notifications without editing code.

## Rebuilding from source

Install the .NET 6 SDK and run:

```powershell
cd helper_app/src
dotnet publish -r win-x64 -c Release --self-contained true -o ..\build
```

This produces a portable `HelperApp.exe` alongside any required support files inside `build/`.
