defmodule StockFetcher.Mock.Hydration do
  @moduledoc """
  Generates deterministic, time-series mock data payload for frontend development and testing.
  """

  alias StockFetcher.LTTB

  @tickers ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]
  @base_prices %{
    "AAPL" => 180.0,
    "AMZN" => 175.0,
    "GOOGL" => 150.0,
    "MSFT" => 400.0,
    "TSLA" => 220.0
  }

  @doc """
  Generates mock stock records for a single `ticker` over the past `hours`,
  and downsamples the result set using `LTTB.downsample/2`.
  """
  def get_hydrated_prices(ticker, hours \\ 12, target_points \\ 100) do
    normalized_ticker = String.upcase(ticker)
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -hours, :hour)

    generate_raw_series(normalized_ticker, cutoff, now, raw_count: 250)
    |> LTTB.downsample(target_points)
  end

  @doc """
  Generates a full watchlist map of hydrated mock prices across all default tickers.
  """
  def hydrate_watchlist(hours \\ 12, target_points \\ 100) do
    Map.new(@tickers, fn ticker ->
      {ticker, get_hydrated_prices(ticker, hours, target_points)}
    end)
  end

  # --- Internal Helpers ---

  defp generate_raw_series(ticker, start_time, end_time, raw_count: count) do
    initial_price = Map.get(@base_prices, ticker, 100.0)
    total_seconds = DateTime.diff(end_time, start_time, :second)
    step_seconds = div(total_seconds, max(count - 1, 1))

    timestamps =
      for i <- 0..(count - 1) do
        {i, DateTime.add(start_time, i * step_seconds, :second)}
      end

    {points, _final_price} =
      Enum.map_reduce(timestamps, initial_price, fn {i, timestamp}, current_price ->
        # Calculate random price delta: range [-0.75, +0.75]
        delta = (:rand.uniform() - 0.49) * 1.50
        next_price = Float.round(max(1.0, current_price + delta), 2)

        point = %{
          id: 1000 + i,
          ticker: ticker,
          price: next_price,
          inserted_at: timestamp
        }

        {point, next_price}
      end)

    points
  end
end
