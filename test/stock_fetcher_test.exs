defmodule StockFetcherTest do
  @moduledoc """
  Unit and integration test suite for the core `StockFetcher` module and Ecto changeset validations.
  Verifies proper record persistence in SQLite, ticker normalization, and edge-case handling for invalid inputs.
  Usage:
  docker compose exec -e MIX_ENV=test stock_runner mix test
  """

  use ExUnit.Case, async: true

  alias StockFetcher.{Repo, StockPrice}

  setup do
    # Explicitly checkout a sandbox database connection for this test run
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Allow all spawned tasks/processes in the test to share Req.Test stubs!
    Req.Test.set_req_test_to_shared(self())

    :ok
  end

  # Helper function to extract changeset error messages into a map.
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      opt_map = Map.new(opts)

      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        to_string(Map.get(opt_map, String.to_existing_atom(key), key))
      end)
    end)
  end

  describe "save_price/2" do
    test "lowercased tickers are upcased before saving" do
      assert {:ok, record} = StockFetcher.save_price("msft", 410.25)
      assert record.ticker == "MSFT"
      assert record.price == 410.25
    end

    test "fails to save when attributes are invalid" do
      assert {:error, changeset} = StockFetcher.save_price("AAPL", nil)
      refute changeset.valid?
    end

    test "fails to save when price is negative" do
      assert {:error, changeset} = StockFetcher.save_price("AAPL", -200.12)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).price
    end

    test "fails to save when price is zero" do
      assert {:error, changeset} = StockFetcher.save_price("AAPL", 0.0)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).price
    end
  end

  describe "fetch_stock_data/2 with Req.Test" do
    test "returns {:ok, ticker, price} on successful HTTP 200 response" do
      Req.Test.stub(StockFetcher, fn conn ->
        Req.Test.json(conn, %{"c" => 182.50, "h" => 185.00, "l" => 180.00})
      end)

      assert {:ok, "AAPL", 182.50} = StockFetcher.fetch_stock_data("AAPL")
    end

    test "returns {:error, ticker, 'Invalid API Key'} on HTTP 401 response" do
      Req.Test.stub(StockFetcher, fn conn ->
        Plug.Conn.send_resp(conn, 401, "Unauthorized")
      end)

      assert {:error, "AAPL", "Invalid API Key"} = StockFetcher.fetch_stock_data("AAPL")
    end

    test "returns {:error, ticker, 'Rate Limit Reached'} on HTTP 429 response" do
      Req.Test.stub(StockFetcher, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Too Many Requests")
      end)

      assert {:error, "TSLA", "Rate Limit Reached"} = StockFetcher.fetch_stock_data("TSLA")
    end

    test "returns {:error, ticker, 'HTTP Error 500'} on server crash" do
      Req.Test.stub(StockFetcher, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, "NVDA", "HTTP Error 500"} = StockFetcher.fetch_stock_data("NVDA")
    end
  end

  describe "prune_old_prices/1" do
    test "deletes records older than the specified number of days" do
      {:ok, recent_price} = StockFetcher.save_price("APPL", 120.67)
      {:ok, old_price} = StockFetcher.save_price("AAPL", 140.00)

      thirty_one_days_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-31 * 86_400, :second)

      import Ecto.Query

      Repo.update_all(
        from(p in StockPrice, where: p.id == ^old_price.id),
        set: [inserted_at: thirty_one_days_ago]
      )

      {deleted_count, _} = StockFetcher.prune_old_prices(30)

      assert deleted_count == 1
      assert Repo.get(StockPrice, old_price.id) == nil
      assert Repo.get(StockPrice, recent_price.id) != nil
    end
  end
end
