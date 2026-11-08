defmodule StockFetcher.Trading.SaveFileTest do
  # async: false: SQLite has one write lock (see trading_test.exs).
  use ExUnit.Case, async: false

  alias StockFetcher.{Repo, Trading}
  alias StockFetcher.Trading.{PendingOrder, SaveFile}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    {:ok, portfolio} = Trading.create_session_portfolio(:mock, "50000")
    %{portfolio: portfolio}
  end

  # A long, a short, a filled bracket (two open exits sharing a parent) and a resting entry.
  defp trade!(%{id: id}) do
    {:ok, _} = Trading.place_market_order(id, "buy", "AAPL", 10, 100.0, source: :mock)
    {:ok, _} = Trading.place_market_order(id, "short", "QBTS", 5, 10.0, source: :mock)

    {:ok, :filled, _} =
      Trading.place_limit_order(id, "NVDA", 2, "190", "180",
        take_profit: "200",
        source: :mock,
        current_price: 189.0
      )

    {:ok, :placed, _} =
      Trading.place_limit_order(id, "MSFT", 1, "390", nil, source: :mock, current_price: 400.0)

    id
  end

  test "export then import restores cash, positions, history and open orders", %{portfolio: p} do
    id = trade!(p)
    before = Trading.get_portfolio!(id)

    assert {:ok, restored} = SaveFile.import(SaveFile.export(id, :mock), :mock)

    assert restored.id != id
    assert Trading.session_portfolio?(restored)
    assert restored.cash_cents == before.cash_cents
    assert restored.starting_cash_cents == 5_000_000

    assert Enum.map(restored.positions, &{&1.ticker, &1.quantity, &1.avg_cost_cents}) ==
             Enum.map(before.positions, &{&1.ticker, &1.quantity, &1.avg_cost_cents})

    assert length(Trading.list_orders(restored.id)) == length(Trading.list_orders(id))

    open = Trading.list_pending_orders(restored.id)

    assert Enum.map(open, &Trading.describe/1) |> Enum.sort() ==
             Trading.list_pending_orders(id) |> Enum.map(&Trading.describe/1) |> Enum.sort()

    # The two exits still share a (filled) parent, so OCO keeps working after a restore.
    [stop, tp] = open |> Enum.filter(&Trading.exit?/1) |> Enum.sort_by(& &1.type, :desc)
    assert stop.parent_id == tp.parent_id
    assert Repo.get!(PendingOrder, stop.parent_id).status == "filled"

    assert {:ok, %{cancelled: 1}} = Trading.fill_pending_order(tp.id, 20_000)

    # How each order was placed survives the round trip: the NVDA limit entry filled by a
    # resting order ("limit_entry"), the market orders are manual (nil).
    vias = fn id ->
      id |> Trading.list_orders() |> Enum.map(&{&1.ticker, &1.via}) |> Enum.sort()
    end

    assert {"NVDA", "limit_entry"} in vias.(restored.id)
    assert {"AAPL", "manual"} in vias.(restored.id)
    assert {"NVDA", "take_profit"} in vias.(restored.id)
  end

  test "reformatting the file is fine; editing a value is refused", %{portfolio: p} do
    file = SaveFile.export(trade!(p), :mock)
    decoded = Jason.decode!(file)

    assert {:ok, _} = SaveFile.import(Jason.encode!(decoded), :mock)

    tampered = put_in(decoded, ["capstock_save", "cash_cents"], 100_000_000_000)
    assert SaveFile.import(Jason.encode!(tampered), :mock) == {:error, :bad_signature}

    unsigned = Map.delete(decoded, "signature") |> Map.put("signature", "nope")
    assert SaveFile.import(Jason.encode!(unsigned), :mock) == {:error, :bad_signature}
  end

  test "a mock save doesn't load on the live page", %{portfolio: p} do
    assert SaveFile.import(SaveFile.export(p.id, :mock), :live) == {:error, :wrong_source}
  end

  test "garbage and oversized input" do
    assert SaveFile.import("not json", :mock) == {:error, :invalid_file}
    assert SaveFile.import(~s({"hello": 1}), :mock) == {:error, :invalid_file}

    assert SaveFile.import(String.duplicate("x", SaveFile.max_bytes() + 1), :mock) ==
             {:error, :too_large}

    assert SaveFile.import(nil, :mock) == {:error, :invalid_file}
  end

  test "a failed import writes nothing", %{portfolio: p} do
    count = Repo.aggregate(Trading.Portfolio, :count)
    tampered = String.replace(SaveFile.export(p.id, :mock), "5000000", "5000001")
    assert {:error, _} = SaveFile.import(tampered, :mock)
    assert Repo.aggregate(Trading.Portfolio, :count) == count
  end
end
