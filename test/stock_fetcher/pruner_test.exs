defmodule StockFetcher.PrunerTest do
  use ExUnit.Case, async: false

  alias StockFetcher.{Repo, StockPrice}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "handle_info :prune triggers deletion of old price records" do
    {:ok, recent_price} = StockFetcher.save_price("AAPL", 150.00)
    {:ok, old_price} = StockFetcher.save_price("AAPL", 140.00)

    eight_days_ago = DateTime.utc_now() |> DateTime.add(-8 * 86_400, :second)

    import Ecto.Query

    Repo.update_all(
      from(p in StockPrice, where: p.id == ^old_price.id),
      set: [inserted_at: eight_days_ago]
    )

    {:ok, pid} =
      StockFetcher.Pruner.start_link(
        schedule_timer: false,
        days_to_keep: 7,
        test_pid: self(),
        name: nil
      )

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    send(pid, :prune)

    assert_receive :prune_complete, 1000

    assert Repo.get(StockPrice, old_price.id) == nil
    assert Repo.get(StockPrice, recent_price.id) != nil
  end
end
