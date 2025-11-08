# MT5 ICT/SMC Brain System

The MT5 ICT/SMC Brain System combines a MetaTrader 5 expert advisor with a lightweight Windows helper application to detect institutional trading setups, capture MT5 workspaces, and keep a local trade memory with Telegram alerts.

## Overview

1. **BrainEA.mq5** scans five symbols across six timeframes, evaluates ICT/SMC logic, and writes signal files while arranging a six-chart workspace.
2. **HelperApp** monitors the signal folder, captures the MT5 window, updates the journal, and sends Telegram notifications.
3. Screenshots and metadata are stored locally so they can be reviewed manually or uploaded to ChatGPT for deeper analysis.

## Quickstart

1. **Prepare MT5**
   - Copy `mql5/BrainEA.mq5` into the `MQL5/Experts` folder of your MT5 terminal.
   - Compile the EA in MetaEditor and attach it to any chart.
   - Copy your indicator `.ex5` files and the `AI_ICT_Template.tpl` template into MT5 (template name must match the EA input).

2. **Configure chart template**
   - Make sure the template loads every indicator required by the EA (UT Bot, Linear Regression, ATR, etc.).
   - Save it as `AI_ICT_Template.tpl` in `MQL5/Profiles/Templates`.

3. **Deploy the helper**
   - Copy the entire `helper_app` folder to a Windows machine that runs the same MT5 terminal.
   - Run `dotnet publish` (see **Building the helper**) or use an existing build to create `HelperApp.exe` inside `helper_app\build`.
   - Duplicate `config.sample.json` to `config.json` and edit the paths, Telegram credentials, and MT5 window title.
   - Launch the generated `HelperApp.exe` and keep it running in the background.

4. **Workflow**
   - Leave MT5 and the helper running. When a strategy aligns, the EA writes `latest_signal.txt` and updates `signals_log.csv`.
   - The helper waits for charts to update, captures the MT5 window, saves a screenshot under `journal/YYYY-MM-DD/`, appends `trade_memory.csv`, and sends a Telegram alert.
   - Drag the saved screenshot into ChatGPT for a deeper breakdown and manually update `trade_memory.csv` with outcome notes later.

## Repository Layout

```
BrainEA/
 ├── mql5/
 │    └── BrainEA.mq5
 ├── helper_app/
 │    ├── src/
 │    │    ├── Program.cs
 │    │    └── Helper.cs
 │    ├── build/
 │    │    └── (publish output lives here, e.g. `HelperApp.exe`)
 │    └── config.sample.json
 ├── docs/
 │    └── (reserved for diagrams and supporting documents)
 ├── README_MQL5.md
 └── README_Helper.md
```

## Building the helper (optional)

If you want to rebuild the helper yourself, install the .NET 6 SDK and run:

```powershell
dotnet publish helper_app/src/HelperApp.csproj -r win-x64 -c Release --self-contained true -o helper_app/build
```

The command produces a portable `HelperApp.exe` (and supporting files) inside `helper_app/build/`.

## Support

Refer to `README_MQL5.md` and `README_Helper.md` for detailed setup, configuration, and troubleshooting information.
