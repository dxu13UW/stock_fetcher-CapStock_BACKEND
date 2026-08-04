defmodule StockFetcherWeb.ErrorJSON do
  @moduledoc """
  Renders JSON error responses for API endpoints.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
