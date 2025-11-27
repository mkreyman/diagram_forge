# DiagramForge Deployment Pipeline

Implementation guide for CI/CD pipeline and Fly.io deployment.

## Table of Contents

1. [Environment Variables](#environment-variables)
2. [CI Pipeline](#ci-pipeline)
3. [Fly.io Setup](#flyio-setup)
4. [Deployment Process](#deployment-process)
5. [Post-Deployment](#post-deployment)

---

## Environment Variables

**Note**: Fly.io secrets are app-specific - each app has its own isolated secrets. They are NOT shared across your Fly.io apps.

### Required for Production

| Variable | Description | How to Get |
|----------|-------------|------------|
| `SECRET_KEY_BASE` | Phoenix secret key (64+ chars) | Run `mix phx.gen.secret` |
| `DATABASE_URL` | PostgreSQL connection string | Auto-set by `fly postgres attach` |
| `PHX_HOST` | Production hostname | Your Fly.io app URL (e.g., `diagram-forge.fly.dev`) |
| `PORT` | HTTP port (default: 4000) | Usually `8080` for Fly.io |
| `POOL_SIZE` | Database connection pool | Start with `10`, adjust based on usage |

### Authentication & OAuth

| Variable | Description | How to Get |
|----------|-------------|------------|
| `GITHUB_CLIENT_ID` | GitHub OAuth app ID | Create at github.com/settings/developers > OAuth Apps |
| `GITHUB_CLIENT_SECRET` | GitHub OAuth secret | Same as above, generated when creating OAuth app |

**GitHub OAuth Setup**:
1. Go to GitHub Settings > Developer settings > OAuth Apps
2. Click "New OAuth App"
3. Set Authorization callback URL to: `https://YOUR-APP.fly.dev/auth/github/callback`
4. Copy Client ID and generate Client Secret

### AI Integration

| Variable | Description | How to Get |
|----------|-------------|------------|
| `OPENAI_API_KEY` | OpenAI API key for diagram generation | platform.openai.com/api-keys |

### Security

| Variable | Description | How to Get |
|----------|-------------|------------|
| `CLOAK_KEY` | Encryption key for sensitive data | Run: `32 |> :crypto.strong_rand_bytes() |> Base.encode64()` |

### External Links (Seeds)

These are used by seed scripts to populate site configuration for footer links and support options.

| Variable | Description | How to Get |
|----------|-------------|------------|
| `GITHUB_REPO_URL` | GitHub repository URL | Your repo URL (e.g., `https://github.com/username/diagram_forge`) |
| `GITHUB_ISSUES_URL` | GitHub issues URL | Your issues URL (e.g., `https://github.com/username/diagram_forge/issues`) |
| `GITHUB_SPONSORS_URL` | GitHub sponsors URL | Set up at github.com/sponsors, then use your sponsors URL |
| `LINKEDIN_URL` | LinkedIn profile URL | Your LinkedIn profile URL |
| `STRIPE_TIP_URL` | Stripe tip jar URL | Create a Payment Link at dashboard.stripe.com/payment-links |

### Admin Setup (Seeds)

| Variable | Description | How to Get |
|----------|-------------|------------|
| `DF_SUPERADMIN_USER` | Superadmin email address | Your email address for initial admin account |

### Clustering (Optional - for multi-instance)

Only needed if running multiple instances:

| Variable | Description |
|----------|-------------|
| `DNS_CLUSTER_QUERY` | DNS query for clustering (Fly.io sets this) |
| `ECTO_IPV6` | Enable IPv6 for Ecto |
| `PHX_SERVER` | Start Phoenix server (set to `true`) |

### Email (Future - Not Currently Configured)

Email is not configured for production yet. When needed, uncomment the Mailgun config in `runtime.exs` and set:
- `MAILGUN_API_KEY` - From mailgun.com dashboard
- `MAILGUN_DOMAIN` - Your verified sending domain in Mailgun

---

## CI Pipeline

### Prerequisites

Before creating the CI workflow, ensure these dependencies are in `mix.exs`:

```elixir
# In deps function
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
```

Run `mix deps.get` after adding.

### GitHub Workflow

Create `.github/workflows/ci.yml`:

```yaml
name: DiagramForge CI

on:
  push:
    branches: [main, development]
  pull_request:
    branches: [main, development]

jobs:
  # Quick checks that don't need full setup
  lint:
    name: Format and Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.18.4"
          otp-version: "27.3"

      - name: Cache dependencies
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-mix-deps-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-deps-

      - name: Install dependencies
        run: mix deps.get

      - name: Check formatting
        run: mix format --check-formatted

      - name: Run credo static code analysis
        run: mix credo --strict

  # Main test job
  test:
    name: Tests
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: diagram_forge_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      MIX_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost/diagram_forge_test

    steps:
      - uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.18.4"
          otp-version: "27.3"

      - name: Cache build dependencies
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-

      - name: Cache Node.js dependencies
        uses: actions/cache@v4
        with:
          path: assets/node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: ${{ runner.os }}-node-

      - name: Install dependencies
        run: mix deps.get

      - name: Compile project
        run: mix compile --warnings-as-errors

      - name: Install Node.js dependencies
        run: |
          cd assets
          npm ci

      - name: Run tests
        run: mix test

  # Security scan
  security:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.18.4"
          otp-version: "27.3"

      - name: Cache dependencies
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-mix-deps-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-deps-

      - name: Install dependencies
        run: mix deps.get

      - name: Security scan
        run: mix sobelow --config

  # Type checking with Dialyzer
  dialyzer:
    name: Type Checking (Dialyzer)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.18.4"
          otp-version: "27.3"

      - name: Cache build dependencies
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
          restore-keys: ${{ runner.os }}-mix-

      - name: Cache Dialyxir PLT
        uses: actions/cache@v4
        with:
          path: |
            _build/dev/*.plt
            _build/dev/*.plt.hash
          key: ${{ runner.os }}-dialyxir-plt-dev-${{ hashFiles('mix.lock') }}-v1

      - name: Install dependencies
        run: mix deps.get

      - name: Compile project
        run: mix compile

      - name: Run dialyzer for type checking
        run: mix dialyzer --format short

  # Deploy to Fly.io (only on main branch)
  deploy:
    name: Deploy to Fly.io
    needs: [lint, test, security, dialyzer]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Setup Fly.io CLI
        uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Deploy to Fly.io
        run: flyctl deploy --remote-only
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

---

## Fly.io Setup

### Initial Setup

1. **Install Fly CLI**:
   ```bash
   brew install flyctl
   ```

2. **Login to Fly.io**:
   ```bash
   fly auth login
   ```

3. **Generate Phoenix release files**:
   ```bash
   mix phx.gen.release --docker
   ```
   This creates:
   - `Dockerfile` - Multi-stage Docker build
   - `rel/overlays/bin/server` - Server startup script
   - `rel/overlays/bin/migrate` - Migration script

4. **Launch app on Fly.io**:
   ```bash
   fly launch
   ```
   This creates:
   - `fly.toml` - Fly.io configuration

### Configure Fly.toml

After `fly launch`, update `fly.toml`:

```toml
app = "diagram-forge"
primary_region = "iad"  # Choose your region

[build]

[env]
  PHX_HOST = "diagramforge.dev"
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0
  processes = ["app"]

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1
```

### Set Secrets on Fly.io

```bash
# Generate a new secret key base
mix phx.gen.secret

# Core secrets
fly secrets set SECRET_KEY_BASE="<output-from-phx.gen.secret>"
fly secrets set CLOAK_KEY="<generated-base64-key>"

# OAuth
fly secrets set GITHUB_CLIENT_ID="<from-github-oauth-app>"
fly secrets set GITHUB_CLIENT_SECRET="<from-github-oauth-app>"

# AI
fly secrets set OPENAI_API_KEY="<from-platform.openai.com>"

# Admin
fly secrets set DF_SUPERADMIN_USER="<your-admin-email>"

# External links (for site footer/support)
fly secrets set GITHUB_REPO_URL="https://github.com/yourusername/diagram_forge"
fly secrets set GITHUB_ISSUES_URL="https://github.com/yourusername/diagram_forge/issues"
fly secrets set GITHUB_SPONSORS_URL="https://github.com/sponsors/yourusername"
fly secrets set LINKEDIN_URL="https://linkedin.com/in/yourprofile"
fly secrets set STRIPE_TIP_URL="https://buy.stripe.com/your-link"
```

### Create Postgres Database

```bash
# Create Fly Postgres cluster
fly postgres create --name diagram-forge-db

# Attach to your app (sets DATABASE_URL automatically)
fly postgres attach diagram-forge-db
```

### GitHub Actions Secret

For automated deployment, add `FLY_API_TOKEN` to GitHub repository secrets:

```bash
# Generate a deploy token
fly tokens create deploy -x 999999h

# Add to GitHub: Settings > Secrets and variables > Actions > New repository secret
# Name: FLY_API_TOKEN
# Value: <the token from above>
```

---

## Deployment Process

### Manual Deployment

```bash
# Deploy from local machine
fly deploy
```

### Automated Deployment

Push to `main` branch triggers automatic deployment via GitHub Actions.

### Run Migrations

Migrations run automatically during deployment via the release script. For manual runs:

```bash
fly ssh console -C "/app/bin/migrate"
```

### Run Seeds

First, create `lib/diagram_forge/release.ex`:

```elixir
defmodule DiagramForge.Release do
  @moduledoc """
  Release tasks for running migrations and seeds in production.
  """

  @app :diagram_forge

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo ->
        seeds_file = Application.app_dir(@app, "priv/repo/seeds.exs")

        if File.exists?(seeds_file) do
          Code.eval_file(seeds_file)
        end
      end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

After deployment, run seeds:

```bash
fly ssh console -C "/app/bin/diagram_forge eval 'DiagramForge.Release.seed()'"
```

---

## Post-Deployment

### Verify Deployment

```bash
# Check app status
fly status

# View logs
fly logs

# Open app in browser
fly open
```

### Health Checks

Add to `fly.toml` if needed:

```toml
[[services.tcp_checks]]
  grace_period = "30s"
  interval = "15s"
  timeout = "2s"
```

### Scaling

```bash
# Scale to 2 instances
fly scale count 2

# Scale memory
fly scale memory 2048
```

### SSL/Custom Domain

```bash
# Add custom domain
fly certs add yourdomain.com

# Verify certificate
fly certs show yourdomain.com
```

---

## Checklist

- [ ] Generate release files: `mix phx.gen.release --docker`
- [ ] Launch on Fly.io: `fly launch`
- [ ] Create Postgres: `fly postgres create`
- [ ] Attach database: `fly postgres attach`
- [ ] Set required secrets via `fly secrets set`
- [ ] Create GitHub OAuth App and set credentials
- [ ] Add `FLY_API_TOKEN` to GitHub secrets
- [ ] Create `.github/workflows/ci.yml`
- [ ] Add `sobelow` to mix.exs deps
- [ ] Create `lib/diagram_forge/release.ex`
- [ ] Test deployment: `fly deploy`
- [ ] Run migrations: `fly ssh console -C "/app/bin/migrate"`
- [ ] Run seeds: `fly ssh console -C "/app/bin/diagram_forge eval 'DiagramForge.Release.seed()'"`
- [ ] Verify with `fly status` and `fly logs`
