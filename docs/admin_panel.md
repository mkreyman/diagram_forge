# Admin Panel

The DiagramForge admin panel provides superadmin users with tools to manage users, diagrams, and documents across the platform.

## Access

- **URL**: `/admin` (redirects to `/admin/dashboard`)
- **Authentication**: Requires superadmin privileges
- **Theme**: Dark theme (daisyUI)

## Features

### Dashboard (`/admin/dashboard`)

The dashboard provides an overview of platform statistics:

- **Summary Cards**: Total users, diagrams, and documents with quick navigation
- **Diagram Statistics**: Breakdown of public vs private diagrams
- **Document Statistics**: Status breakdown (ready, processing, errors)
- **Recent Users**: List of the 5 most recently registered users

### User Management (`/admin/users`)

Backpex-powered CRUD interface for managing users:

- View all users with search functionality
- Edit user details (email, name, avatar URL)
- View user metadata (provider, last sign-in, timestamps)

### Diagram Management (`/admin/diagrams`)

Backpex-powered CRUD interface for managing diagrams:

- View all diagrams with search functionality
- Filter by visibility (public, unlisted, private) and format (mermaid, plantuml)
- Edit diagram details including title, slug, tags, and content
- View associated document and fork relationships

### Document Management (`/admin/documents`)

Backpex-powered CRUD interface for managing documents:

- View all documents with search functionality
- Filter by source type (PDF, markdown) and status
- View document owner and processing status
- Access raw text content and error messages

## Architecture

### Layout Structure

The admin panel uses a two-level layout system:

1. **Root Layout** (`DiagramForgeWeb.Admin.Layouts.root`): HTML document structure with dark theme
2. **Admin Layout** (`DiagramForgeWeb.Admin.Layouts.admin`): Backpex app_shell with navigation

### Key Files

```
lib/diagram_forge_web/
├── admin/
│   ├── layouts.ex                    # Layout module
│   ├── layouts/
│   │   ├── root.html.heex           # HTML document (dark theme)
│   │   └── admin.html.heex          # Backpex app_shell layout
│   └── resources/
│       ├── user_resource.ex         # Backpex LiveResource for users
│       ├── diagram_resource.ex      # Backpex LiveResource for diagrams
│       └── document_resource.ex     # Backpex LiveResource for documents
├── controllers/
│   └── admin_redirect_controller.ex # Redirects /admin to /admin/dashboard
├── live/admin/
│   └── dashboard_live.ex            # Dashboard LiveView
└── plugs/
    ├── require_auth.ex              # Authentication plug
    └── require_superadmin.ex        # Superadmin authorization plug
```

### Router Configuration

```elixir
scope "/admin" do
  pipe_through [:browser, :require_superadmin]

  backpex_routes()

  get "/", DiagramForgeWeb.AdminRedirectController, :index

  live_session :admin,
    root_layout: {DiagramForgeWeb.Admin.Layouts, :root},
    on_mount: [
      Backpex.InitAssigns,
      {DiagramForgeWeb.Plugs.RequireSuperadmin, :ensure_superadmin}
    ] do
    live "/dashboard", DiagramForgeWeb.Admin.DashboardLive
    live_resources("/users", DiagramForgeWeb.Admin.UserResource)
    live_resources("/diagrams", DiagramForgeWeb.Admin.DiagramResource)
    live_resources("/documents", DiagramForgeWeb.Admin.DocumentResource)
  end
end
```

### Backpex Configuration

Required in `config/config.exs`:

```elixir
config :backpex,
  pubsub_server: DiagramForge.PubSub,
  translator_function: {DiagramForgeWeb.CoreComponents, :translate_backpex},
  error_translator_function: {DiagramForgeWeb.CoreComponents, :translate_error}
```

### CSS Configuration

Backpex styles are included via Tailwind source paths in `assets/css/app.css`:

```css
@source "../../deps/backpex/**/*.*ex";
@source "../../deps/backpex/assets/js/**/*.*js";
```

## Navigation

The admin panel provides consistent navigation through:

- **Top bar**: Horizontal navigation links and user dropdown menu
- **Sidebar**: Vertical navigation with icons and active state highlighting
- **User dropdown**: Shows current user email, link back to main app, and logout

## Authorization

Access control is enforced at multiple levels:

1. **Router pipeline**: `require_superadmin` plug blocks non-superadmin users
2. **LiveView on_mount**: `RequireSuperadmin.ensure_superadmin` validates on socket connection
3. **Resource-level**: Each Backpex resource implements `can?/3` callbacks

## Extending the Admin Panel

### Adding a New Resource

1. Create a new Backpex LiveResource in `lib/diagram_forge_web/admin/resources/`
2. Add the route in the router's `:admin` live_session
3. Add navigation links in both `admin.html.heex` and `dashboard_live.ex`

### Customizing Fields

Backpex fields support customization through options:

- `only: [:index, :show]` - Limit field visibility to specific views
- `searchable: true` - Enable search on the field
- `render: fn assigns -> ... end` - Custom rendering function
- `options_query: fn query, assigns -> ... end` - Custom query for BelongsTo fields
