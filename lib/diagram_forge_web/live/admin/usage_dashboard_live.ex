defmodule DiagramForgeWeb.Admin.UsageDashboardLive do
  @moduledoc """
  Admin dashboard for API usage monitoring and cost tracking.
  """

  use DiagramForgeWeb, :live_view

  alias DiagramForge.Usage

  @impl true
  def render(assigns) do
    ~H"""
    <Backpex.HTML.Layout.app_shell fluid={false}>
      <:topbar>
        <Backpex.HTML.Layout.topbar_branding title="DiagramForge Admin" />

        <div class="flex items-center gap-2">
          <.link navigate={~p"/admin/dashboard"} class="btn btn-ghost btn-sm">
            Dashboard
          </.link>
          <.link navigate={~p"/admin/users"} class="btn btn-ghost btn-sm">
            Users
          </.link>
          <.link navigate={~p"/admin/diagrams"} class="btn btn-ghost btn-sm">
            Diagrams
          </.link>
          <.link navigate={~p"/admin/documents"} class="btn btn-ghost btn-sm">
            Documents
          </.link>
          <.link navigate={~p"/admin/prompts"} class="btn btn-ghost btn-sm">
            Prompts
          </.link>
          <.link navigate={~p"/admin/usage/dashboard"} class="btn btn-ghost btn-sm btn-active">
            Usage
          </.link>
        </div>

        <Backpex.HTML.Layout.topbar_dropdown>
          <:label>
            <div class="btn btn-square btn-ghost">
              <Backpex.HTML.CoreComponents.icon name="hero-user" class="size-6" />
            </div>
          </:label>
          <li>
            <span class="text-sm text-base-content/70">
              {if assigns[:current_user], do: assigns.current_user.email}
            </span>
          </li>
          <li>
            <.link navigate={~p"/"} class="flex justify-between hover:bg-base-200">
              <p>Back to App</p>
              <Backpex.HTML.CoreComponents.icon name="hero-arrow-left" class="size-5" />
            </.link>
          </li>
          <li>
            <.link href="/auth/logout" class="text-error flex justify-between hover:bg-base-200">
              <p>Logout</p>
              <Backpex.HTML.CoreComponents.icon name="hero-arrow-right-on-rectangle" class="size-5" />
            </.link>
          </li>
        </Backpex.HTML.Layout.topbar_dropdown>
      </:topbar>
      <:sidebar>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/dashboard"}>
          <Backpex.HTML.CoreComponents.icon name="hero-home" class="size-5" /> Dashboard
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/users"}>
          <Backpex.HTML.CoreComponents.icon name="hero-users" class="size-5" /> Users
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/diagrams"}>
          <Backpex.HTML.CoreComponents.icon name="hero-rectangle-group" class="size-5" /> Diagrams
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/documents"}>
          <Backpex.HTML.CoreComponents.icon name="hero-document-text" class="size-5" /> Documents
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/prompts"}>
          <Backpex.HTML.CoreComponents.icon name="hero-chat-bubble-bottom-center-text" class="size-5" />
          Prompts
        </Backpex.HTML.Layout.sidebar_item>

        <div class="divider my-2 text-xs text-base-content/50">API Usage</div>

        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/usage/dashboard"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-chart-bar" class="size-5" /> Usage Dashboard
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/usage/alerts"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-bell-alert" class="size-5" /> Alerts
          <span :if={@unacknowledged_count > 0} class="badge badge-error badge-sm ml-auto">
            {@unacknowledged_count}
          </span>
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/ai-providers"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-server" class="size-5" /> AI Providers
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item current_url={@current_url} navigate={~p"/admin/ai-models"}>
          <Backpex.HTML.CoreComponents.icon name="hero-cpu-chip" class="size-5" /> AI Models
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/ai-model-prices"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-currency-dollar" class="size-5" /> Model Prices
        </Backpex.HTML.Layout.sidebar_item>
        <Backpex.HTML.Layout.sidebar_item
          current_url={@current_url}
          navigate={~p"/admin/alert-thresholds"}
        >
          <Backpex.HTML.CoreComponents.icon name="hero-adjustments-horizontal" class="size-5" />
          Thresholds
        </Backpex.HTML.Layout.sidebar_item>
      </:sidebar>
      <Backpex.HTML.Layout.flash_messages flash={@flash} />

      <div class="space-y-8">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 class="text-2xl font-bold text-base-content">API Usage</h1>
            <p class="mt-1 text-sm text-base-content/70">
              <%= if @custom_range do %>
                {Calendar.strftime(@start_date, "%b %d, %Y")} - {Calendar.strftime(
                  @end_date,
                  "%b %d, %Y"
                )}
              <% else %>
                {@month_name} {@year} - Token usage and cost tracking
              <% end %>
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-4">
            <.link
              href={export_url(@year, @month, @custom_range, @start_date, @end_date)}
              class="btn btn-outline btn-sm"
            >
              <Backpex.HTML.CoreComponents.icon name="hero-arrow-down-tray" class="size-4" />
              Export CSV
            </.link>
            <!-- Monthly Navigation -->
            <div :if={!@custom_range} class="flex items-center gap-2">
              <.link
                navigate={~p"/admin/usage/dashboard?#{%{year: @prev_year, month: @prev_month}}"}
                class="btn btn-ghost btn-sm"
              >
                <Backpex.HTML.CoreComponents.icon name="hero-chevron-left" class="size-4" />
              </.link>
              <span class="text-sm font-medium">{@month_name} {@year}</span>
              <.link
                navigate={~p"/admin/usage/dashboard?#{%{year: @next_year, month: @next_month}}"}
                class={["btn btn-ghost btn-sm", @is_current_month && "btn-disabled"]}
              >
                <Backpex.HTML.CoreComponents.icon name="hero-chevron-right" class="size-4" />
              </.link>
            </div>
            <!-- Toggle Custom Range -->
            <button
              type="button"
              phx-click="toggle_custom_range"
              class={["btn btn-sm", (@custom_range && "btn-primary") || "btn-ghost"]}
            >
              <Backpex.HTML.CoreComponents.icon name="hero-calendar-days" class="size-4" />
              Custom Range
            </button>
          </div>
        </div>
        <!-- Custom Date Range Picker -->
        <div :if={@custom_range} class="bg-base-100 rounded-lg border border-base-300 p-4 shadow-sm">
          <form phx-submit="apply_date_range" class="flex flex-wrap items-end gap-4">
            <div>
              <label class="label">
                <span class="label-text">Start Date</span>
              </label>
              <input
                type="date"
                name="start_date"
                value={Date.to_iso8601(@start_date)}
                class="input input-bordered input-sm"
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text">End Date</span>
              </label>
              <input
                type="date"
                name="end_date"
                value={Date.to_iso8601(@end_date)}
                class="input input-bordered input-sm"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Apply</button>
            <.link
              navigate={~p"/admin/usage/dashboard"}
              class="btn btn-ghost btn-sm"
            >
              Reset to Monthly
            </.link>
          </form>
        </div>
        <!-- Alert Banner -->
        <div
          :if={@unacknowledged_count > 0}
          class="alert alert-warning shadow-lg"
          role="alert"
          id="usage-alert-banner"
        >
          <Backpex.HTML.CoreComponents.icon name="hero-exclamation-triangle" class="size-6" />
          <span>
            {@unacknowledged_count} usage alert(s) require attention
          </span>
          <.link navigate={~p"/admin/usage/alerts"} class="btn btn-sm">View Alerts</.link>
        </div>
        <!-- Summary Cards -->
        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          <.stat_card
            title="Total Cost"
            value={"$#{Usage.format_cents(@summary.cost_cents || 0)}"}
            icon="hero-currency-dollar"
            color="primary"
          />
          <.stat_card
            title="Requests"
            value={format_number(@summary.request_count || 0)}
            icon="hero-arrow-path"
            color="secondary"
          />
          <.stat_card
            title="Input Tokens"
            value={format_tokens(@summary.input_tokens || 0)}
            icon="hero-arrow-up-tray"
            color="accent"
          />
          <.stat_card
            title="Output Tokens"
            value={format_tokens(@summary.output_tokens || 0)}
            icon="hero-arrow-down-tray"
            color="info"
          />
        </div>
        <!-- Daily Cost Chart -->
        <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
          <h2 class="text-lg font-semibold text-base-content mb-4">Daily Cost Breakdown</h2>
          <div class="overflow-x-auto" id="daily-chart">
            <div class="flex items-end h-48 gap-1 min-w-[600px]">
              <div
                :for={day <- @daily_costs}
                class="flex flex-col items-center flex-1"
                title={"#{day.date}: $#{Usage.format_cents(day.cost_cents || 0)}"}
              >
                <div
                  class="w-full bg-primary rounded-t"
                  style={"height: #{bar_height(day.cost_cents, @max_daily_cost)}px"}
                >
                </div>
                <span class="text-xs text-base-content/50 mt-1">
                  {Calendar.strftime(day.date, "%d")}
                </span>
              </div>
            </div>
          </div>
        </div>
        <!-- Model Breakdown -->
        <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
          <h2 class="text-lg font-semibold text-base-content mb-4">Usage by Model</h2>
          <div :if={@model_breakdown == []} class="text-center py-8 text-base-content/50">
            No usage data for this period
          </div>
          <div :if={@model_breakdown != []} class="overflow-x-auto">
            <table class="table table-sm" id="model-breakdown-table">
              <thead>
                <tr>
                  <th>Model</th>
                  <th class="text-right">Requests</th>
                  <th class="text-right">Input Tokens</th>
                  <th class="text-right">Output Tokens</th>
                  <th class="text-right">Cost</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={model <- @model_breakdown}>
                  <td>
                    <div class="flex flex-col">
                      <span class="font-medium">{model.model_name}</span>
                      <span class="text-xs text-base-content/50">{model.api_name}</span>
                    </div>
                  </td>
                  <td class="text-right font-mono">{format_number(model.request_count || 0)}</td>
                  <td class="text-right font-mono">{format_tokens(model.input_tokens || 0)}</td>
                  <td class="text-right font-mono">{format_tokens(model.output_tokens || 0)}</td>
                  <td class="text-right font-mono font-semibold">
                    ${Usage.format_cents(model.cost_cents || 0)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Top Users Table -->
        <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
          <h2 class="text-lg font-semibold text-base-content mb-4">Top Users by Cost</h2>
          <div :if={@top_users == []} class="text-center py-8 text-base-content/50">
            No usage data for this period
          </div>
          <div :if={@top_users != []} class="overflow-x-auto">
            <table class="table table-sm" id="top-users-table">
              <thead>
                <tr>
                  <th>User</th>
                  <th class="text-right">Requests</th>
                  <th class="text-right">Tokens</th>
                  <th class="text-right">Cost</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={user <- @top_users}>
                  <td>
                    <.link
                      :if={user.user_id}
                      navigate={~p"/admin/users/#{user.user_id}/show"}
                      class="link link-primary"
                    >
                      {user_email(user.user_id)}
                    </.link>
                    <span :if={!user.user_id} class="text-base-content/50">Anonymous</span>
                  </td>
                  <td class="text-right font-mono">{format_number(user.request_count || 0)}</td>
                  <td class="text-right font-mono">{format_tokens(user.total_tokens || 0)}</td>
                  <td class="text-right font-mono font-semibold">
                    ${Usage.format_cents(user.cost_cents || 0)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <!-- Quick Links -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <.link
            navigate={~p"/admin/ai-providers"}
            class="bg-base-100 rounded-lg border border-base-300 p-4 shadow-sm hover:shadow-md transition-shadow flex items-center gap-3"
          >
            <Backpex.HTML.CoreComponents.icon name="hero-server" class="size-8 text-primary" />
            <div>
              <p class="font-medium">AI Providers</p>
              <p class="text-sm text-base-content/70">Manage providers</p>
            </div>
          </.link>
          <.link
            navigate={~p"/admin/ai-models"}
            class="bg-base-100 rounded-lg border border-base-300 p-4 shadow-sm hover:shadow-md transition-shadow flex items-center gap-3"
          >
            <Backpex.HTML.CoreComponents.icon name="hero-cpu-chip" class="size-8 text-secondary" />
            <div>
              <p class="font-medium">AI Models</p>
              <p class="text-sm text-base-content/70">Configure models</p>
            </div>
          </.link>
          <.link
            navigate={~p"/admin/alert-thresholds"}
            class="bg-base-100 rounded-lg border border-base-300 p-4 shadow-sm hover:shadow-md transition-shadow flex items-center gap-3"
          >
            <Backpex.HTML.CoreComponents.icon
              name="hero-adjustments-horizontal"
              class="size-8 text-accent"
            />
            <div>
              <p class="font-medium">Alert Thresholds</p>
              <p class="text-sm text-base-content/70">Configure alerts</p>
            </div>
          </.link>
        </div>
      </div>
    </Backpex.HTML.Layout.app_shell>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "primary"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
      <div class="flex items-center">
        <div class={"shrink-0 p-3 rounded-lg bg-#{@color}/10"}>
          <.icon name={@icon} class={"h-6 w-6 text-#{@color}"} />
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-base-content/70">{@title}</p>
          <p class="text-2xl font-bold text-base-content">{@value}</p>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    today = Date.utc_today()

    # Check if custom range is specified
    custom_range = params["start_date"] != nil && params["end_date"] != nil

    {start_date, end_date, year, month} =
      if custom_range do
        start_date = Date.from_iso8601!(params["start_date"])
        end_date = Date.from_iso8601!(params["end_date"])
        {start_date, end_date, start_date.year, start_date.month}
      else
        year = parse_int(params["year"], today.year)
        month = parse_int(params["month"], today.month)
        start_date = Date.new!(year, month, 1)
        end_date = Date.end_of_month(start_date)
        {start_date, end_date, year, month}
      end

    {prev_year, prev_month} = prev_month(year, month)
    {next_year, next_month} = next_month(year, month)

    socket =
      socket
      |> assign(:page_title, "API Usage")
      |> assign(:current_url, ~p"/admin/usage/dashboard")
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:month_name, month_name(month))
      |> assign(:prev_year, prev_year)
      |> assign(:prev_month, prev_month)
      |> assign(:next_year, next_year)
      |> assign(:next_month, next_month)
      |> assign(:is_current_month, year == today.year && month == today.month)
      |> assign(:custom_range, custom_range)
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> load_data_for_range(start_date, end_date)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_custom_range", _params, socket) do
    if socket.assigns.custom_range do
      # Switch back to monthly view
      {:noreply, push_navigate(socket, to: ~p"/admin/usage/dashboard")}
    else
      # Enable custom range with current month as default
      {:noreply, assign(socket, :custom_range, true)}
    end
  end

  @impl true
  def handle_event(
        "apply_date_range",
        %{"start_date" => start_str, "end_date" => end_str},
        socket
      ) do
    {:noreply,
     push_navigate(socket,
       to: ~p"/admin/usage/dashboard?#{%{start_date: start_str, end_date: end_str}}"
     )}
  end

  defp load_data_for_range(socket, start_date, end_date) do
    summary = Usage.get_summary_for_range(start_date, end_date)
    daily_costs = Usage.get_daily_costs_for_range(start_date, end_date)
    top_users = Usage.get_top_users_for_range(start_date, end_date)
    model_breakdown = Usage.get_usage_by_model_for_range(start_date, end_date)
    unacknowledged_count = Usage.count_unacknowledged_alerts()

    max_daily_cost =
      daily_costs
      |> Enum.map(& &1.cost_cents)
      |> Enum.max(fn -> 0 end)

    socket
    |> assign(:summary, summary)
    |> assign(:daily_costs, daily_costs)
    |> assign(:top_users, top_users)
    |> assign(:model_breakdown, model_breakdown)
    |> assign(:max_daily_cost, max_daily_cost)
    |> assign(:unacknowledged_count, unacknowledged_count)
  end

  defp export_url(_year, _month, true, start_date, end_date) do
    ~p"/admin/usage/export.csv?#{%{start_date: Date.to_iso8601(start_date), end_date: Date.to_iso8601(end_date)}}"
  end

  defp export_url(year, month, false = _custom_range, _start_date, _end_date) do
    ~p"/admin/usage/export.csv?#{%{year: year, month: month}}"
  end

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(int, _default) when is_integer(int), do: int

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp month_name(1), do: "January"
  defp month_name(2), do: "February"
  defp month_name(3), do: "March"
  defp month_name(4), do: "April"
  defp month_name(5), do: "May"
  defp month_name(6), do: "June"
  defp month_name(7), do: "July"
  defp month_name(8), do: "August"
  defp month_name(9), do: "September"
  defp month_name(10), do: "October"
  defp month_name(11), do: "November"
  defp month_name(12), do: "December"

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}K"
  end

  defp format_number(num), do: to_string(num)

  defp format_tokens(tokens) do
    format_number(tokens)
  end

  defp bar_height(_cost, 0), do: 4
  defp bar_height(nil, _max), do: 4

  defp bar_height(cost, max) do
    min(max(round(cost / max * 160), 4), 160)
  end

  defp user_email(user_id) do
    case DiagramForge.Repo.get(DiagramForge.Accounts.User, user_id) do
      nil -> "Unknown"
      user -> user.email
    end
  end
end
