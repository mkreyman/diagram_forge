# DiagramForge

AI-powered technical diagram generation and sharing platform. Create beautiful Mermaid diagrams from natural language prompts or by extracting concepts from your documents.

## Features

### Diagram Creation
- **AI-Powered Generation**: Create diagrams from natural language prompts (e.g., "Create a diagram showing how OAuth2 works")
- **Document Ingestion**: Upload PDF, Markdown, or text files to extract concepts and generate diagrams automatically
- **Mermaid Syntax Auto-Fix**: AI automatically corrects invalid Mermaid syntax
- **Diagram Formats**: Supports Mermaid (flowcharts, sequence, class, state diagrams, etc.) and PlantUML

### Organization & Discovery
- **Tag-Based Organization**: Flexible tagging system for organizing diagrams
- **Saved Filters**: Create custom filter combinations for quick access to diagram collections
- **Visibility Controls**: Public, unlisted, or private diagrams
- **SEO Optimized**: Public diagrams are indexed with proper meta tags, Open Graph, and JSON-LD

### Authentication & Security
- **GitHub OAuth**: Sign in with your GitHub account
- **Content Moderation**: AI-powered moderation prevents inappropriate content
- **Prompt Injection Protection**: Hardened prompts protect against manipulation attempts

### Administration
- **Admin Dashboard**: Platform statistics and overview
- **User Management**: Backpex-powered admin interface
- **Token Usage Tracking**: Monitor AI API usage and costs

## Tech Stack

- **Phoenix 1.8** with LiveView for real-time UI
- **Elixir 1.15+** on the BEAM
- **PostgreSQL** with Ecto
- **Oban** for background job processing
- **OpenAI API** for AI-powered features
- **Mermaid** for diagram rendering
- **Backpex** for admin panel

## Getting Started

### Prerequisites

- Elixir 1.15+
- PostgreSQL 14+
- Node.js (for assets)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/mkreyman/diagram_forge.git
   cd diagram_forge
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   cd assets && npm install && cd ..
   ```

3. Set up your database:
   ```bash
   mix ecto.setup
   ```

4. Configure environment variables (see [Configuration](#configuration))

5. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

## Configuration

Set these environment variables for development:

```bash
export OPENAI_API_KEY="your-openai-api-key"
export GITHUB_CLIENT_ID="your-github-oauth-client-id"
export GITHUB_CLIENT_SECRET="your-github-oauth-client-secret"
export CLOAK_KEY="your-base64-encoded-encryption-key"
```

Generate a CLOAK_KEY with: `mix run -e "32 |> :crypto.strong_rand_bytes() |> Base.encode64() |> IO.puts()"`

For production configuration, see [docs/deployment-pipeline.md](docs/deployment-pipeline.md).

## Development

### Running Tests

```bash
mix test
```

All tests use Mox for mocking external dependencies (no API keys needed for testing).

### Code Quality

Run all quality checks:

```bash
mix precommit
```

This runs:
- Compilation with warnings as errors
- Code formatting check
- Credo static analysis
- Dialyzer type checking
- Full test suite

### Project Structure

```
lib/diagram_forge/
├── accounts/           # User authentication
├── ai/                 # LLM integration
├── content/            # Content moderation & injection detection
├── diagrams/           # Core diagram domain
│   ├── diagram.ex
│   ├── document.ex
│   ├── saved_filter.ex
│   └── workers/        # Oban background jobs
└── usage/              # Token usage tracking

lib/diagram_forge_web/
├── admin/              # Backpex admin resources
├── components/         # Phoenix components
├── controllers/        # Auth & sitemap controllers
└── live/               # LiveView modules (including admin dashboard)
```

## Contributing

We welcome contributions! Here's how to get started:

1. **Check existing issues**: [GitHub Issues](https://github.com/mkreyman/diagram_forge/issues)
2. **Fork the repository**
3. **Create a feature branch**: `git checkout -b feature/your-feature`
4. **Write tests** for your changes
5. **Ensure `mix precommit` passes**
6. **Submit a pull request**

### Reporting Issues

Found a bug or have a feature request? [Open an issue](https://github.com/mkreyman/diagram_forge/issues/new) with:
- A clear description of the problem or feature
- Steps to reproduce (for bugs)
- Expected vs actual behavior

### Code Standards

- Follow existing code patterns
- Write tests for new functionality
- Keep commits focused and well-described
- Ensure all quality checks pass before submitting

## Documentation

- [Deployment Pipeline](docs/deployment-pipeline.md) - CI/CD and Fly.io deployment
- [Admin Panel](docs/admin_panel.md) - Admin interface documentation
- [Content Moderation](docs/content-moderation.md) - Moderation system details

## License

This project is open source and available under the MIT License.
