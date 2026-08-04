ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(StockFetcher.Repo, :manual)

defmodule StockFetcher.TestHelpers do
  @moduledoc """
  Helper module with single function to extract changeset error messages into a map.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      opt_map = Map.new(opts)

      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        to_string(Map.get(opt_map, String.to_existing_atom(key), key))
      end)
    end)
  end
end
