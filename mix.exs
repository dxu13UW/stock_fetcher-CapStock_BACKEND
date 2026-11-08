defmodule StockFetcher.MixProject do
  use Mix.Project

  def project do
    [
      app: :stock_fetcher,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
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
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_ecto, "~> 4.4"},
      {:cors_plug, "~> 3.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},
      {:credo, "~>1.7", only: [:dev, :test], runtime: false},
      {:tz, "~> 0.26"},
      {:hammer, "~> 6.1"},
      {:corsica, "~> 2.1"}
    ]
  end

  # Asset build steps. `assets.deploy` runs in the Dockerfile before `mix release`.
  defp aliases do
    [
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind stock_fetcher", "esbuild stock_fetcher"],
      "assets.deploy": [
        "tailwind stock_fetcher --minify",
        "esbuild stock_fetcher --minify",
        "phx.digest"
      ],
      # Keep the test DB's schema current (new migrations, e.g. the trading tables).
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
