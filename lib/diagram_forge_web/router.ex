defmodule DiagramForgeWeb.Router do
  use DiagramForgeWeb, :router
  import Backpex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DiagramForgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug DiagramForgeWeb.Plugs.Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug DiagramForgeWeb.Plugs.RequireAuth
  end

  pipeline :require_superadmin do
    plug DiagramForgeWeb.Plugs.RequireAuth
    plug DiagramForgeWeb.Plugs.RequireSuperadmin
  end

  scope "/auth", DiagramForgeWeb do
    pipe_through :browser

    get "/github", AuthController, :request
    get "/github/callback", AuthController, :callback
    get "/logout", AuthController, :logout
  end

  scope "/", DiagramForgeWeb do
    pipe_through :browser

    live "/", DiagramStudioLive
    live "/d/:id", DiagramStudioLive
    live "/terms", TermsLive
    live "/privacy", PrivacyLive
    get "/home", PageController, :home
  end

  # Admin panel - superadmin only
  scope "/admin" do
    pipe_through [:browser, :require_superadmin]

    # Backpex required routes for cookies
    backpex_routes()

    # Redirect /admin to /admin/dashboard
    get "/", DiagramForgeWeb.AdminRedirectController, :index

    # CSV export (regular controller, not LiveView)
    get "/usage/export.csv", DiagramForgeWeb.Admin.UsageExportController, :export_csv

    # Admin live session - includes dashboard and Backpex resources
    live_session :admin,
      root_layout: {DiagramForgeWeb.Admin.Layouts, :root},
      on_mount: [
        Backpex.InitAssigns,
        {DiagramForgeWeb.Plugs.RequireSuperadmin, :ensure_superadmin}
      ] do
      # Dashboard
      live "/dashboard", DiagramForgeWeb.Admin.DashboardLive

      # Content Moderation Queue
      live "/moderation", DiagramForgeWeb.Admin.ModerationQueueLive

      # User management
      live_resources("/users", DiagramForgeWeb.Admin.UserResource)

      # Diagram management
      live_resources("/diagrams", DiagramForgeWeb.Admin.DiagramResource)

      # Document management
      live_resources("/documents", DiagramForgeWeb.Admin.DocumentResource)

      # AI Prompts management (custom LiveView, not Backpex)
      live "/prompts", DiagramForgeWeb.Admin.PromptLive, :index
      live "/prompts/:key/edit", DiagramForgeWeb.Admin.PromptEditLive, :edit

      # AI Provider/Model/Pricing management
      live_resources("/ai-providers", DiagramForgeWeb.Admin.AIProviderResource)
      live_resources("/ai-models", DiagramForgeWeb.Admin.AIModelResource)
      live_resources("/ai-model-prices", DiagramForgeWeb.Admin.AIModelPriceResource)

      # Usage alert threshold management
      live_resources("/alert-thresholds", DiagramForgeWeb.Admin.AlertThresholdResource)

      # Usage Dashboard and Alerts (custom LiveViews)
      live "/usage/dashboard", DiagramForgeWeb.Admin.UsageDashboardLive, :index
      live "/usage/alerts", DiagramForgeWeb.Admin.AlertHistoryLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", DiagramForgeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:diagram_forge, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DiagramForgeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
