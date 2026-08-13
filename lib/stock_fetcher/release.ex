defmodule StockFetcher.Release do
  @moduledoc """
  Executes database tasks directly inside a compiled release binary. (release)
  """
  @app :stock_fetcher

  def migrate do
    load_app()

    for repo <- repos() do
      if db_path = repo.config()[:database] do
        db_path
        |> Path.dirname()
        |> File.mkdir_p!()
      end

      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
