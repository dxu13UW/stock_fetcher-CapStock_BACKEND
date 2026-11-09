defmodule StockFetcherWeb do
  @moduledoc """
  Shared `use` definitions for the web layer, e.g. `use StockFetcherWeb, :live_view`.

  Each function returns quoted code that is injected into the module that calls `use`,
  so every LiveView and component gets the same imports without repeating them.
  """

  def static_paths, do: ~w(assets favicon.ico favicon.svg apple-touch-icon.png robots.txt)

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0]

      unquote(html_helpers())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: StockFetcherWeb.Endpoint,
        router: StockFetcherWeb.Router,
        statics: StockFetcherWeb.static_paths()
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML

      alias Phoenix.LiveView.JS

      # ~p"/prices" sigil: compile-time checked paths
      unquote(verified_routes())
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
