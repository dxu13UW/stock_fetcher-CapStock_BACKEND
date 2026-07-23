defmodule StockFetcher.MixProject do
  use Mix.Project

  def project do
    [
      app: :stock_fetcher,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {StockFetcher.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.6.0"},
      {:jason, "~> 1.4"},
      {:ecto_sqlite3, "~> 0.17"},
      {:plug, "~> 1.0"}
    ]
  end
end
