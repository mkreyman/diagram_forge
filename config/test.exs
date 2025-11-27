import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :diagram_forge, DiagramForge.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "diagram_forge_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Disable Oban queues in test mode to prevent DB ownership errors
config :diagram_forge, Oban,
  repo: DiagramForge.Repo,
  testing: :manual

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :diagram_forge, DiagramForgeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7UEll9BoVLHLCMBYh9udyfWD9inf9UDjUK/gIJ71jb4TLJ4P7kR6KW2tmhndpFqU",
  server: false

# In test we don't send emails
config :diagram_forge, DiagramForge.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Use MockAIClient in tests
config :diagram_forge, :ai_client, DiagramForge.MockAIClient

# Use MockUsageTracker in tests to avoid DB connection issues with async Tasks
config :diagram_forge, :usage_tracker, DiagramForge.MockUsageTracker

# Configure AI client for testing
config :diagram_forge, DiagramForge.AI,
  api_key: "test_api_key",
  model: "gpt-4"

# Default superadmin email for tests - prevents race conditions in async tests
config :diagram_forge, :superadmin_email, "admin@example.com"

# Configure Cloak for test environment with a static test key
# This key is ONLY for testing and should never be used in production
# Generated with: :crypto.strong_rand_bytes(32) |> Base.encode64()
config :diagram_forge, DiagramForge.Vault,
  ciphers: [
    default: {
      Cloak.Ciphers.AES.GCM,
      tag: "AES.GCM.V1",
      key: Base.decode64!("RTr9aMWrNkUp2kzRYfSFyoXXSEh5eMd21hJIL/rdfYc="),
      iv_length: 12
    }
  ]

# Disable content moderation in tests (mock it in specific tests)
config :diagram_forge, DiagramForge.Content, moderation_enabled: false

config :diagram_forge, DiagramForge.Content.Moderator, enabled: false

# Enable injection detection in tests so we can test the patterns
config :diagram_forge, DiagramForge.Content.InjectionDetector,
  enabled: true,
  action: :flag_for_review

# Configure GitHub OAuth for tests with dummy values
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: "test_client_id",
  client_secret: "test_client_secret"
