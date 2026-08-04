defmodule StockFetcherWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      @endpoint StockFetcherWeb.Endpoint
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(StockFetcher.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(StockFetcher.Repo, {:shared, self()})
    end

    :ok
  end
end
