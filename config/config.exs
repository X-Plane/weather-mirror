import Config

# Remove extra newline between each log line
config :logger, :console, format: "$time $metadata[$level] $levelpad$message\n"
