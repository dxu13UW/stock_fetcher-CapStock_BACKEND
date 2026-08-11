defmodule StockFetcher.LTTB do
  @moduledoc """
  Implements the Largest-Triangle-Three-Buckets (LTTB) algorithm
  for time-series data downsampling.
  """

  @doc """
  Downsamples a time-series dataset to a target `threshold` length using the
  Largest-Triangle-Three-Bucket (LTTB) algorithm.

  ## Behavior
  * `length(data) <= threshold` — Returns `data` unmodified because downsampling is unnecessary.
  * `threshold < 3`             — Returns `data` unmodified because forming LTTB triangles requires K >= 3
  * `length(data) > threshold`  — Splits middle data into `threshold - 2` buckets, preserves the first
                          and last points, and selects peak/valley points that maximize triangle area.
  """
  def downsample(data, threshold) when length(data) <= threshold or threshold < 3 do
    data
  end

  def downsample(data, threshold) do
    [first_pt | rest] = data
    last_pt = List.last(rest)
    middle_data = Enum.slice(rest, 0..(length(rest) - 2))

    bucket_size = length(middle_data) / (threshold - 2)
    buckets = Enum.chunk_every(middle_data, ceil(bucket_size))

    processed_middle = process_buckets(buckets, first_pt)
    [first_pt | processed_middle] ++ [last_pt]
  end

  # --- Internal Helpers ---

  defp process_buckets([], _prev_pt), do: []

  defp process_buckets([curr_bucket | remaining_buckets], prev_pt) do
    next_avg = avg_pt(List.first(remaining_buckets, []))

    best_pt =
      Enum.max_by(curr_bucket, fn pt ->
        triangle_area(prev_pt, pt, next_avg)
      end)

    [best_pt | process_buckets(remaining_buckets, best_pt)]
  end

  defp triangle_area(p_a, p_b, p_c) do
    x_a = point_x(p_a)
    y_a = point_y(p_a)
    x_b = point_x(p_b)
    y_b = point_y(p_b)
    x_c = point_x(p_c)
    y_c = point_y(p_c)

    0.5 * abs(x_a * (y_b - y_c) + x_b * (y_c - y_a) + x_c * (y_a - y_b))
  end

  defp avg_pt([]), do: %{x: 0, y: 0}

  defp avg_pt(bucket) do
    count = length(bucket)
    sum_x = Enum.reduce(bucket, 0, fn p, acc -> acc + point_x(p) end)
    sum_y = Enum.reduce(bucket, 0, fn p, acc -> acc + point_y(p) end)

    %{x: sum_x / count, y: sum_y / count}
  end

  # Polymorphic extraction for Ecto structs, maps with DateTime, or raw map x/y
  defp point_x(%{inserted_at: %DateTime{} = dt}), do: DateTime.to_unix(dt, :millisecond)
  defp point_x(%{x: %DateTime{} = dt}), do: DateTime.to_unix(dt, :millisecond)
  defp point_x(%{x: x}) when is_number(x), do: x

  defp point_y(%{price: %Decimal{} = p}), do: Decimal.to_float(p)
  defp point_y(%{price: p}) when is_number(p), do: p
  defp point_y(%{y: %Decimal{} = p}), do: Decimal.to_float(p)
  defp point_y(%{y: y}) when is_number(y), do: y
end
