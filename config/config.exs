# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :diagram_forge,
  ecto_repos: [DiagramForge.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :diagram_forge, DiagramForgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DiagramForgeWeb.ErrorHTML, json: DiagramForgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: DiagramForge.PubSub,
  live_view: [signing_salt: "lLb2EZbY"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :diagram_forge, DiagramForge.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  diagram_forge: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  diagram_forge: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    # Error handling metadata
    :error,
    :category,
    :severity,
    :context,
    :attempt,
    :next_delay_ms,
    # AI client metadata
    :reason,
    :model,
    # Content moderation metadata
    :diagram_id,
    :decision,
    :confidence,
    :response,
    # Injection detection metadata
    :reasons,
    :suspicious_fields,
    :patterns,
    :text_preview
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Backpex admin panel
config :backpex,
  pubsub_server: DiagramForge.PubSub,
  translator_function: {DiagramForgeWeb.CoreComponents, :translate_backpex},
  error_translator_function: {DiagramForgeWeb.CoreComponents, :translate_error}

# Configure Oban
config :diagram_forge, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10, documents: 5, diagrams: 10, moderation: 5],
  repo: DiagramForge.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Check usage alerts every hour
       {"0 * * * *", DiagramForge.Usage.Workers.CheckAlertsWorker}
     ]}
  ]

# Configure Ueberauth for GitHub OAuth
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]}
  ]

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

# Configure Cloak for encryption
config :diagram_forge, DiagramForge.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1", key: Base.decode64!(System.get_env("CLOAK_KEY") || ""), iv_length: 12
    }
  ]

# Configure content moderation
config :diagram_forge, DiagramForge.Content, moderation_enabled: true

config :diagram_forge, DiagramForge.Content.Moderator,
  enabled: true,
  auto_approve_threshold: 0.8

config :diagram_forge, DiagramForge.Content.Sanitizer,
  enabled: true,
  strip_urls: true

config :diagram_forge, DiagramForge.Content.MermaidSanitizer, enabled: true

config :diagram_forge, DiagramForge.Content.InjectionDetector,
  enabled: true,
  # Action when injection detected: :flag_for_review | :reject | :log_only
  action: :flag_for_review

# Configure Hammer for rate limiting
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       expiry_ms: 60_000 * 60,
       cleanup_interval_ms: 60_000 * 10
     ]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
