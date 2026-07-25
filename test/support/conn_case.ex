defmodule StockFetcherWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import StockFetcherWeb.ConnCase

      use Phoenix.VerifiedRoutes,
        endpoint: StockFetcherWeb.Endpoint,
        router: StockFetcherWeb.Router

      @endpoint StockFetcherWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(StockFetcher.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(StockFetcher.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
