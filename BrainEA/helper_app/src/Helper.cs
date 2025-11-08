using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Globalization;

namespace BrainEA.HelperApp
{
    internal sealed class BrainHelper
    {
        private readonly AppConfig _config;
        private readonly SimpleLogger _logger;
        private readonly ScreenshotService _screenshotService;
        private readonly TelegramClient _telegramClient;
        private readonly string _latestSignalFile;
        private readonly Dictionary<string, DateTime> _lastSignalTimes = new();
        private DateTime _lastFileWriteUtc = DateTime.MinValue;

        public BrainHelper(AppConfig config, SimpleLogger logger)
        {
            _config = config;
            _logger = logger;
            _latestSignalFile = Path.Combine(_config.SignalsFolder, "latest_signal.txt");
            _screenshotService = new ScreenshotService(_config, logger);
            _telegramClient = new TelegramClient(_config, logger);
        }

        public async Task RunAsync()
        {
            _logger.Info("Helper loop started.");
            while (true)
            {
                try
                {
                    await ProcessLatestSignalAsync();
                }
                catch (Exception ex)
                {
                    _logger.Error($"Processing error: {ex}");
                }

                await Task.Delay(TimeSpan.FromSeconds(_config.PollIntervalSeconds));
            }
        }

        private async Task ProcessLatestSignalAsync()
        {
            if (!File.Exists(_latestSignalFile))
            {
                return;
            }

            var info = new FileInfo(_latestSignalFile);
            if (info.LastWriteTimeUtc <= _lastFileWriteUtc)
            {
                return;
            }

            _lastFileWriteUtc = info.LastWriteTimeUtc;
            var raw = await File.ReadAllLinesAsync(_latestSignalFile);
            var signal = SignalInfo.FromLines(raw);
            if (signal is null)
            {
                _logger.Warn("latest_signal.txt exists but could not be parsed.");
                return;
            }

            if (!ShouldProcess(signal))
            {
                return;
            }

            _logger.Info($"New signal detected: {signal.Symbol} {signal.Strategy} {signal.Session}");
            await Task.Delay(TimeSpan.FromSeconds(_config.ScreenshotDelaySeconds));

            string? screenshotPath = null;
            try
            {
                screenshotPath = _screenshotService.Capture(signal);
                _logger.Info($"Screenshot saved to {screenshotPath}");
            }
            catch (Exception ex)
            {
                _logger.Error($"Screenshot failed: {ex.Message}");
            }

            try
            {
                var journalPath = JournalWriter.WriteEntry(_config, signal, screenshotPath);
                _logger.Info($"Journal updated: {journalPath}");
            }
            catch (Exception ex)
            {
                _logger.Error($"Journal update failed: {ex.Message}");
            }

            try
            {
                await _telegramClient.NotifyAsync(signal, screenshotPath);
            }
            catch (Exception ex)
            {
                _logger.Error($"Telegram notification failed: {ex.Message}");
            }
        }

        private bool ShouldProcess(SignalInfo signal)
        {
            var key = $"{signal.Symbol}|{signal.Strategy}";
            if (_lastSignalTimes.TryGetValue(key, out var lastTime))
            {
                if ((signal.Timestamp - lastTime).TotalMinutes < _config.DuplicateMinutes)
                {
                    _logger.Info($"Duplicate signal ignored for {key}.");
                    return false;
                }
            }

            _lastSignalTimes[key] = signal.Timestamp;
            return true;
        }
    }

    internal sealed class AppConfig
    {
        public string Mt5WindowTitle { get; set; } = "MetaTrader 5";
        public string SignalsFolder { get; set; } = string.Empty;
        public string JournalFolder { get; set; } = string.Empty;
        public string TelegramBotToken { get; set; } = string.Empty;
        public string TelegramChatId { get; set; } = string.Empty;
        public int PollIntervalSeconds { get; set; } = 3;
        public double DuplicateMinutes { get; set; } = 5;
        public ScreenshotRegion ScreenshotRegion { get; set; } = new();
        public int ScreenshotDelaySeconds { get; set; } = 2;

        public void Validate()
        {
            if (string.IsNullOrWhiteSpace(SignalsFolder))
            {
                throw new InvalidOperationException("signalsFolder must be set in config.json");
            }

            SignalsFolder = Path.GetFullPath(SignalsFolder);

            if (!Directory.Exists(SignalsFolder))
            {
                throw new DirectoryNotFoundException($"signalsFolder does not exist: {SignalsFolder}");
            }

            if (string.IsNullOrWhiteSpace(JournalFolder))
            {
                throw new InvalidOperationException("journalFolder must be set in config.json");
            }

            JournalFolder = Path.GetFullPath(JournalFolder);
            Directory.CreateDirectory(JournalFolder);

            if (PollIntervalSeconds < 1)
            {
                throw new InvalidOperationException("pollIntervalSeconds must be >= 1");
            }
        }
    }

    internal sealed class ScreenshotService
    {
        private readonly AppConfig _config;
        private readonly SimpleLogger _logger;

        public ScreenshotService(AppConfig config, SimpleLogger logger)
        {
            _config = config;
            _logger = logger;
        }

        public string Capture(SignalInfo signal)
        {
            var windowHandle = NativeMethods.FindWindow(null, _config.Mt5WindowTitle);
            if (windowHandle == IntPtr.Zero)
            {
                throw new InvalidOperationException($"MT5 window not found: {_config.Mt5WindowTitle}");
            }

            NativeMethods.GetWindowRect(windowHandle, out var rect);
            var region = ResolveRegion(rect);

            using var bitmap = new Bitmap(region.Width, region.Height, PixelFormat.Format32bppArgb);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                using var hdcDest = new DeviceContext(graphics);
                using var hdcSrc = new DeviceContext(windowHandle);
                if (!NativeMethods.BitBlt(hdcDest.Hdc, 0, 0, region.Width, region.Height, hdcSrc.Hdc, region.X, region.Y, NativeMethods.SRCCOPY))
                {
                    throw new InvalidOperationException("BitBlt failed while capturing MT5 window.");
                }
            }

            var folder = PrepareJournalFolder(signal.Timestamp);
            var filename = $"{signal.Symbol}_{signal.Strategy}_{signal.Session}_{signal.Timestamp:HH-mm-ss}.png";
            var fullPath = Path.Combine(folder, filename);
            bitmap.Save(fullPath, ImageFormat.Png);
            return fullPath;
        }

        private Rectangle ResolveRegion(NativeMethods.RECT rect)
        {
            if (_config.ScreenshotRegion.Width > 0 && _config.ScreenshotRegion.Height > 0)
            {
                return new Rectangle(
                    _config.ScreenshotRegion.X,
                    _config.ScreenshotRegion.Y,
                    _config.ScreenshotRegion.Width,
                    _config.ScreenshotRegion.Height);
            }

            return new Rectangle(0, 0, rect.Right - rect.Left, rect.Bottom - rect.Top);
        }

        private string PrepareJournalFolder(DateTime timestamp)
        {
            var day = timestamp.ToString("yyyy-MM-dd");
            var folder = Path.Combine(_config.JournalFolder, day);
            Directory.CreateDirectory(folder);
            return folder;
        }
    }

    internal sealed class TelegramClient
    {
        private readonly AppConfig _config;
        private readonly SimpleLogger _logger;
        private readonly HttpClient _httpClient;

        public TelegramClient(AppConfig config, SimpleLogger logger)
        {
            _config = config;
            _logger = logger;
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(10)
            };
        }

        public async Task NotifyAsync(SignalInfo signal, string? screenshotPath)
        {
            if (string.IsNullOrWhiteSpace(_config.TelegramBotToken) || string.IsNullOrWhiteSpace(_config.TelegramChatId))
            {
                _logger.Warn("Telegram credentials missing. Skipping notification.");
                return;
            }

            var caption = $"⚠ New Setup: {signal.Symbol} – {signal.Strategy} – {signal.Session} – {signal.Timestamp:HH:mm}";

            if (!string.IsNullOrWhiteSpace(screenshotPath) && File.Exists(screenshotPath))
            {
                await SendPhotoAsync(caption, screenshotPath);
            }
            else
            {
                await SendMessageAsync(caption);
            }
        }

        private async Task SendMessageAsync(string message)
        {
            var url = $"https://api.telegram.org/bot{_config.TelegramBotToken}/sendMessage";
            var content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["chat_id"] = _config.TelegramChatId,
                ["text"] = message
            });

            var response = await _httpClient.PostAsync(url, content);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync();
                throw new InvalidOperationException($"Telegram sendMessage failed: {response.StatusCode} {body}");
            }
        }

        private async Task SendPhotoAsync(string caption, string screenshotPath)
        {
            var url = $"https://api.telegram.org/bot{_config.TelegramBotToken}/sendPhoto";
            await using var stream = File.OpenRead(screenshotPath);
            using var content = new MultipartFormDataContent();
            content.Add(new StringContent(_config.TelegramChatId), "chat_id");
            content.Add(new StringContent(caption), "caption");
            content.Add(new StreamContent(stream), "photo", Path.GetFileName(screenshotPath));

            var response = await _httpClient.PostAsync(url, content);
            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync();
                throw new InvalidOperationException($"Telegram sendPhoto failed: {response.StatusCode} {body}");
            }
        }
    }

    internal sealed class JournalWriter
    {
        private const string JournalFileName = "trade_memory.csv";

        public static string WriteEntry(AppConfig config, SignalInfo signal, string? screenshotPath)
        {
            var dayFolder = Path.Combine(config.JournalFolder, signal.Timestamp.ToString("yyyy-MM-dd"));
            Directory.CreateDirectory(dayFolder);

            var journalFile = Path.Combine(config.JournalFolder, JournalFileName);
            var line = string.Join(',', new[]
            {
                signal.Timestamp.ToString("yyyy-MM-dd HH:mm:ss"),
                signal.Symbol,
                signal.Strategy,
                signal.Session,
                screenshotPath ?? string.Empty,
                "pending",
                "0",
                string.Empty
            });

            var builder = new StringBuilder();
            if (!File.Exists(journalFile))
            {
                builder.AppendLine("datetime,symbol,strategy,session,screenshot_path,status,result_R,notes");
            }
            builder.AppendLine(line);
            File.AppendAllText(journalFile, builder.ToString());
            return journalFile;
        }
    }

    internal sealed record SignalInfo(DateTime Timestamp, string Symbol, string Strategy, string Session)
    {
        public static SignalInfo? FromLines(string[] lines)
        {
            if (lines.Length == 0)
            {
                return null;
            }

            var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in lines)
            {
                var parts = line.Split('=', 2);
                if (parts.Length == 2)
                {
                    dict[parts[0].Trim()] = parts[1].Trim();
                }
            }

            if (!dict.TryGetValue("timestamp", out var tsString) ||
                !dict.TryGetValue("symbol", out var symbol) ||
                !dict.TryGetValue("strategy", out var strategy))
            {
                return null;
            }

            dict.TryGetValue("session", out var session);

            var formats = new[] { "yyyy.MM.dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss" };
            if (!DateTime.TryParseExact(tsString, formats, CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeLocal, out var timestamp))
            {
                return null;
            }

            return new SignalInfo(timestamp, symbol, strategy, session ?? string.Empty);
        }
    }

    internal sealed class SimpleLogger
    {
        private readonly string _logFile;
        private readonly object _lock = new();

        public SimpleLogger(string logFile)
        {
            _logFile = logFile;
        }

        public void Info(string message) => Write("INFO", message);

        public void Warn(string message) => Write("WARN", message);

        public void Error(string message) => Write("ERROR", message);

        private void Write(string level, string message)
        {
            var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] {message}";
            lock (_lock)
            {
                File.AppendAllText(_logFile, line + Environment.NewLine);
            }
            Console.WriteLine(line);
        }
    }

    internal sealed class DeviceContext : IDisposable
    {
        public IntPtr Hdc { get; }
        private readonly IntPtr _windowHandle;
        private readonly Graphics? _graphics;

        public DeviceContext(IntPtr windowHandle)
        {
            _windowHandle = windowHandle;
            Hdc = NativeMethods.GetWindowDC(windowHandle);
            if (Hdc == IntPtr.Zero)
            {
                throw new InvalidOperationException("Unable to acquire window DC.");
            }
        }

        public DeviceContext(Graphics graphics)
        {
            _graphics = graphics;
            Hdc = graphics.GetHdc();
        }

        public void Dispose()
        {
            if (_graphics is not null)
            {
                _graphics.ReleaseHdc(Hdc);
            }
            else if (_windowHandle != IntPtr.Zero)
            {
                NativeMethods.ReleaseDC(_windowHandle, Hdc);
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct ScreenshotRegion
    {
        public int X { get; init; }
        public int Y { get; init; }
        public int Width { get; init; }
        public int Height { get; init; }
    }

    internal static class NativeMethods
    {
        public const int SRCCOPY = 0x00CC0020;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr FindWindow(string? lpClassName, string? lpWindowName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern IntPtr GetWindowDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        public static extern bool BitBlt(IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight,
            IntPtr hdcSrc, int nXSrc, int nYSrc, int dwRop);
    }
}
