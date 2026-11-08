defmodule StockFetcherWeb.Layouts do
  @moduledoc """
  Page layouts. `root.html.heex` wraps every browser page (set by the router's
  `put_root_layout`); it is rendered once on the initial HTTP request and is not
  re-rendered by LiveView updates.
  """
  use StockFetcherWeb, :html

  embed_templates "layouts/*"
end
