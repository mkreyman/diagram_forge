defmodule DiagramForgeWeb.Admin.ItemAction.MakeUnlisted do
  @moduledoc """
  Backpex item action to bulk-set diagram visibility to unlisted.
  """

  use BackpexWeb, :item_action

  alias DiagramForge.Diagrams

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-link"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-yellow-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Make Unlisted"

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      "Make #{count} diagrams unlisted? They will be accessible via direct link only."
    else
      "Make this diagram unlisted? It will be accessible via direct link only."
    end
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    {:ok, count} = Diagrams.admin_bulk_update_visibility(items, :unlisted)

    socket
    |> clear_flash()
    |> put_flash(:info, "#{count} diagram(s) set to unlisted")
    |> ok()
  end
end
