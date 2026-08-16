defmodule StockFetcherWeb.HealthController do
  @moduledoc """
  Lightweight health-check endpoint for load balancers and container monitoring.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  def show(conn, _params) do
    json(conn, %{
      status: "ok",
      timestamp: System.system_time(:second)
    })
  end
end
