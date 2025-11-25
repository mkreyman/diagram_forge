defmodule DiagramForgeWeb.Admin.UsageExportController do
  @moduledoc """
  Controller for exporting usage data as CSV.
  """

  use DiagramForgeWeb, :controller

  alias DiagramForge.Usage

  def export_csv(conn, params) do
    case params do
      %{"start_date" => start_str, "end_date" => end_str} ->
        export_custom_range(conn, start_str, end_str)

      _ ->
        export_monthly(conn, params)
    end
  end

  defp export_monthly(conn, params) do
    today = Date.utc_today()
    year = parse_int(params["year"], today.year)
    month = parse_int(params["month"], today.month)

    csv_content = Usage.export_usage_csv(year, month)
    filename = "usage-#{year}-#{String.pad_leading(to_string(month), 2, "0")}.csv"

    send_csv(conn, filename, csv_content)
  end

  defp export_custom_range(conn, start_str, end_str) do
    with {:ok, start_date} <- Date.from_iso8601(start_str),
         {:ok, end_date} <- Date.from_iso8601(end_str) do
      csv_content = Usage.export_usage_csv_for_range(start_date, end_date)
      filename = "usage-#{start_str}-to-#{end_str}.csv"
      send_csv(conn, filename, csv_content)
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid date format")
        |> redirect(to: ~p"/admin/usage/dashboard")
    end
  end

  defp send_csv(conn, filename, content) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, content)
  end

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(int, _default) when is_integer(int), do: int
end
