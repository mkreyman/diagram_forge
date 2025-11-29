defmodule DiagramForgeWeb.Admin.ItemAction.MakePublic do
  @moduledoc """
  Backpex item action to bulk-set diagram visibility to public.
  """

  use BackpexWeb, :item_action

  alias DiagramForge.Diagrams

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-globe-alt"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-green-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Make Public"

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      "Make #{count} diagrams public? They will be visible to everyone."
    else
      "Make this diagram public? It will be visible to everyone."
    end
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    {:ok, count} = Diagrams.admin_bulk_update_visibility(items, :public)

    socket
    |> clear_flash()
    |> put_flash(:info, "#{count} diagram(s) set to public")
    |> ok()
  end
end
