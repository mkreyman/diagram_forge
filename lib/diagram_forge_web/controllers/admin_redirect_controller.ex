defmodule DiagramForgeWeb.AdminRedirectController do
  @moduledoc """
  Redirects /admin to /admin/dashboard.
  """

  use DiagramForgeWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/admin/dashboard")
  end
end
