defmodule StockFetcherWeb.StockController do
  use Phoenix.Controller, formats: [:json]

  alias StockFetcher
  alias StockFetcher.LTTB
  alias StockFetcher.MarketHours

  @watchlist ["AAPL", "AMZN", "GOOGL", "MSFT", "TSLA"]
  @default_threshold 200

  @doc """
  GET /api/stocks
  Returns the current or last opened market hours of LTTB downsampled historical prices 
  (max 200 points each) for core watchlist tickers.
  """
  def index(conn, params) do
    hours = parse_int(Map.get(params, "hours"), 12)
    threshold = parse_int(Map.get(params, "threshold"), @default_threshold)

    data =
      @watchlist
      |> StockFetcher.hydrate_watchlist(hours, threshold)
      |> Map.new(fn {ticker, points} -> {ticker, format_points(points)} end)

    json(conn, %{data: data})
  end

  @doc """
  Returns downsampled ticks for a specific ticker within a time range.
  Defaults to the current trading day's market bounds if no range is specified.
  """
  def intraday(conn, %{"ticker" => ticker} = params) do
    with {:ok, normalized_ticker} <- validate_ticker(ticker),
         {start_time, end_time} <- resolve_time_bounds(params),
         threshold <- parse_int(Map.get(params, "threshold"), @default_threshold) do
      data =
        normalized_ticker
        |> fetch_and_downsample(start_time, end_time, threshold)
        |> format_points()

      json(conn, %{ticker: normalized_ticker, data: data})
    else
      {:error, :unsupported_ticker} ->
        render_unsupported_ticker(conn, ticker)
    end
  end

  # --- Pipeline & Query Steps ---

  defp validate_ticker(ticker) when is_binary(ticker) do
    normalized = String.upcase(ticker)

    if normalized in @watchlist do
      {:ok, normalized}
    else
      {:error, :unsupported_ticker}
    end
  end

  defp resolve_time_bounds(%{"from" => from_str, "to" => to_str})
       when is_binary(from_str) and is_binary(to_str) do
    {parse_timestamp(from_str), parse_timestamp(to_str)}
  end

  defp resolve_time_bounds(_params), do: MarketHours.get_intraday_bounds()

  defp fetch_and_downsample(ticker, start_time, end_time, threshold) do
    StockFetcher.get_ticks_between(ticker, start_time, end_time)
    |> maybe_downsample(threshold)
  end

  defp maybe_downsample(points, threshold) when length(points) > threshold and threshold >= 3 do
    LTTB.downsample(points, threshold)
  end

  defp maybe_downsample(points, _threshold), do: points

  defp render_unsupported_ticker(conn, ticker) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: "not_found",
      message: "Ticker '#{ticker}' is not supported. Supported: #{Enum.join(@watchlist, ", ")}"
    })
  end

  # --- Value Parsers & Formatters ---

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp parse_timestamp(iso_str) when is_binary(iso_str) do
    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp format_points(points) do
    Enum.map(points, fn
      %{inserted_at: %DateTime{} = time, price: price} ->
        %{timestamp: DateTime.to_unix(time, :millisecond), price: price}

      %{inserted_at: time_str, price: price} when is_binary(time_str) ->
        case DateTime.from_iso8601(time_str) do
          {:ok, dt, _offset} ->
            %{timestamp: DateTime.to_unix(dt, :millisecond), price: price}

          _ ->
            %{timestamp: 0, price: price}
        end

      %{timestamp: %DateTime{} = time, price: price} ->
        %{timestamp: DateTime.to_unix(time, :millisecond), price: price}

      %{timestamp: ts, price: price} when is_integer(ts) ->
        %{timestamp: ts, price: price}

      point when is_map(point) ->
        point
    end)
  end
end
