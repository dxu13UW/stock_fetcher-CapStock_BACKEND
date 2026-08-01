defmodule StockFetcher.MarketHours do
  @moduledoc """
  Provides functions to check whether standard US Stock Exchanges (NYSE/NASDAQ)
  are currently open for trading (Mon-Fri, 9:30 AM - 4:00 PM Eastern Time).
  """

  @doc """
  Returns `true` if the given DateTime (or current UTC time) falls within standard
  trading hours in America/New_York time.
  """
  def market_open?(datetime \\ DateTime.utc_now()) do
    # automatically handles Daylight Saving Time
    eastern_dt = DateTime.shift_zone!(datetime, "America/New_York")

    # 1 = Monday, 5 = Friday, 6 = Saturday, 7 = Sunday
    day_of_week = Date.day_of_week(eastern_dt)

    time = DateTime.to_time(eastern_dt)

    weekday?(day_of_week) and time_between?(time, ~T[09:30:00], ~T[16:00:00])
  end

  @doc """
  Calculates the milliseconds from `now` until the next market opening
  (9:30 AM ET on the next valid weekday).
  """
  def ms_until_next_open(now \\ DateTime.utc_now()) do
    eastern_dt = DateTime.shift_zone!(now, "America/New_York")
    next_open_dt = calculate_next_open(eastern_dt)

    # Calculate difference in milliseconds
    ms = DateTime.diff(next_open_dt, now, :millisecond)

    # Ensure we never return a negative integer or 0
    max(ms, 1000)
  end

  # --- Helper Functions ---

  defp calculate_next_open(%DateTime{} = dt) do
    time = DateTime.to_time(dt)
    day = Date.day_of_week(dt)
    market_start = ~T[09:30:00]

    if day in 1..5 and Time.compare(time, market_start) == :lt do
      # Set time to 09:30:00 today
      %{dt | hour: 9, minute: 30, second: 0, microsecond: {0, 0}}
    else
      # Otherwise, roll forward to tomorrow at 09:30:00 and search for the next weekday
      dt
      |> add_days(1)
      |> set_time(~T[09:30:00])
      |> advance_to_weekday()
    end
  end

  defp weekday?(day) when day in 1..5, do: true
  defp weekday?(_day), do: false

  defp time_between?(time, start_time, end_time) do
    Time.compare(time, start_time) in [:gt, :eq] and
      Time.compare(time, end_time) in [:lt, :eq]
  end

  defp add_days(dt, days), do: DateTime.add(dt, days * 86_400, :second)

  defp set_time(dt, time) do
    %{dt | hour: time.hour, minute: time.minute, second: time.second, microsecond: {0, 0}}
  end

  # Recursively advances day by day until it lands on Monday (1) through Friday (5)
  defp advance_to_weekday(dt) do
    case Date.day_of_week(dt) do
      day when day in 1..5 -> dt
      _weekend -> dt |> add_days(1) |> advance_to_weekday()
    end
  end
end
