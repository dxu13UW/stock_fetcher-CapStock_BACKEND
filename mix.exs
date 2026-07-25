defmodule StockFetcher.MixProject do
  use Mix.Project

  def project do
    [
      app: :stock_fetcher,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:req, "~> 0.6.2"},
      {:jason, "~> 1.4"},
      {:ecto_sqlite3, "~> 0.17"},
      {:plug, "~> 1.0"},
      {:phoenix, "~> 1.7.10"},
      {:phoenix_ecto, "~> 4.4"},
      {:cors_plug, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"}
    ]
  end
end
