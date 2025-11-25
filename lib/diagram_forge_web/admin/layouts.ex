defmodule DiagramForgeWeb.Admin.Layouts do
  @moduledoc """
  Custom layouts for the admin panel.
  """

  use DiagramForgeWeb, :html

  embed_templates "layouts/*"

  @doc """
  Navigation link component for admin panel.
  """
  attr :navigate, :string, required: true
  slot :inner_block, required: true

  def admin_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="rounded-md px-3 py-2 text-sm font-medium hover:bg-base-200"
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
