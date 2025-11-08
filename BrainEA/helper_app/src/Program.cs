using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace BrainEA.HelperApp
{
    internal static class Program
    {
        private const string DefaultConfigFile = "config.json";

        private static async Task<int> Main(string[] args)
        {
            Console.Title = "AI ICT Brain Helper";
            var logger = new SimpleLogger(Path.Combine(AppContext.BaseDirectory, "helper_log.txt"));

            try
            {
                var configPath = args.Length > 0 ? args[0] : DefaultConfigFile;
                if (!Path.IsPathRooted(configPath))
                {
                    configPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, configPath));
                }

                if (!File.Exists(configPath))
                {
                    logger.Error($"Config file not found: {configPath}");
                    Console.Error.WriteLine($"Config file not found: {configPath}");
                    return 1;
                }

                await using var configStream = File.OpenRead(configPath);
                var config = await JsonSerializer.DeserializeAsync<AppConfig>(configStream, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true,
                    ReadCommentHandling = JsonCommentHandling.Skip,
                    AllowTrailingCommas = true
                });

                if (config is null)
                {
                    logger.Error("Failed to parse configuration file.");
                    return 1;
                }

                config.Validate();
                logger.Info("Configuration loaded. Starting helper loop...");

                var helper = new BrainHelper(config, logger);
                await helper.RunAsync();
                return 0;
            }
            catch (Exception ex)
            {
                logger.Error($"Fatal error: {ex}");
                Console.Error.WriteLine(ex);
                return -1;
            }
        }
    }
}
