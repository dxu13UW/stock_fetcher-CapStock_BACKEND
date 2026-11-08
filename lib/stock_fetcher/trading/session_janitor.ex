defmodule StockFetcher.Trading.SessionJanitor do
  @moduledoc """
  Deletes a tab's session portfolio when the tab's LiveView process ends (2026-11-07).

  Why a separate process and not `terminate/2` in `PricesLive`: LiveView only calls
  `terminate/2` in some cases (a crash or a killed connection can skip it). A monitor always
  fires: when the monitored process exits for any reason, the janitor gets `:DOWN` and deletes
  the portfolio (positions, orders and open orders cascade).

  At boot it deletes every leftover session portfolio, because no tab survives a restart (a
  deploy, a crash of the whole node). Open tabs reconnect and restore from the browser's
  autosave, so nothing is lost. The sweep runs only on the first start: if the janitor itself
  crashes and restarts, live tabs still own their portfolios, so it must not delete them (it
  loses its monitors, so those tabs' rows would linger until the next boot; a small leak, not
  lost data).

  Off in tests (`config :stock_fetcher, :enable_session_janitor, false`), where the SQL sandbox
  owns the data; `register/2` is then a no-op.
  """
  use GenServer
  require Logger

  alias StockFetcher.Trading

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Deletes `portfolio_id` when `pid` exits. No-op if the janitor isn't running."
  def register(portfolio_id, pid \\ self(), name \\ __MODULE__) do
    if GenServer.whereis(name), do: GenServer.cast(name, {:register, portfolio_id, pid})
    :ok
  end

  @doc "Stops watching `portfolio_id` (the tab replaced it and deleted it itself)."
  def forget(portfolio_id, name \\ __MODULE__) do
    if GenServer.whereis(name), do: GenServer.cast(name, {:forget, portfolio_id})
    :ok
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :sweep, true) and
         :persistent_term.get({__MODULE__, :swept}, false) == false do
      count = Trading.delete_all_session_portfolios()
      :persistent_term.put({__MODULE__, :swept}, true)

      if count > 0,
        do: Logger.info("[SessionJanitor] removed #{count} leftover session portfolios")
    end

    # monitor ref => portfolio id
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:register, portfolio_id, pid}, state) do
    {:noreply, Map.put(state, Process.monitor(pid), portfolio_id)}
  end

  def handle_cast({:forget, portfolio_id}, state) do
    {refs, rest} = Enum.split_with(state, fn {_ref, id} -> id == portfolio_id end)
    Enum.each(refs, fn {ref, _} -> Process.demonitor(ref, [:flush]) end)
    {:noreply, Map.new(rest)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {portfolio_id, state} = Map.pop(state, ref)
    if portfolio_id, do: Trading.delete_session_portfolio(portfolio_id)
    {:noreply, state}
  end
end
