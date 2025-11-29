defmodule DiagramForgeWeb.Admin.ItemAction.MakePrivate do
  @moduledoc """
  Backpex item action to bulk-set diagram visibility to private.
  """

  use BackpexWeb, :item_action

  alias DiagramForge.Diagrams

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-lock-closed"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-red-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Make Private"

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      "Make #{count} diagrams private? Only owners will be able to access them."
    else
      "Make this diagram private? Only the owner will be able to access it."
    end
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    {:ok, count} = Diagrams.admin_bulk_update_visibility(items, :private)

    socket
    |> clear_flash()
    |> put_flash(:info, "#{count} diagram(s) set to private")
    |> ok()
  end
end
