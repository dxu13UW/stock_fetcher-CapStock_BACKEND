defmodule StockFetcher.Tickers do
  @moduledoc """
  The 50 tickers Capstock trades (2026-11-07), and where each one's live price comes from.

  One live source per ticker (PLAN.md section 5), so two feeds never fight over a price:
    * `finnhub/0`: the original 5, polled by `StockFetcher.Worker`. Unchanged, because the
      React SPA depends on them.
    * `extra/0`: the other 45, polled by `StockFetcher.Alpaca.Poller` from Alpaca's free IEX
      feed (one request covers all of them). They are broadcast on separate topics
      ("stocks:extra" and "stocks:mock:extra"), so the React SPA, which adds every ticker it
      hears about, keeps showing only its 5.

  Picked for liquidity: on the IEX feed a thinly traded name can go many seconds between
  trades, so its last price lags. Big, busy names trade on IEX every second or two. QBTS is
  the exception, kept because it is John's example trade (interview 1).

  `mock_price` is the starting price for the mock stream only: the extra 45 are the last IEX
  trades as of 2026-11-06 (one request), so the mock looks realistic. Not live quotes.
  """

  @finnhub [
    {"AAPL", "Apple", 180.0},
    {"AMZN", "Amazon", 175.0},
    {"GOOGL", "Alphabet", 150.0},
    {"MSFT", "Microsoft", 400.0},
    {"TSLA", "Tesla", 220.0}
  ]

  @extra [
    {"NVDA", "NVIDIA", 187.62},
    {"META", "Meta Platforms", 610.12},
    {"AVGO", "Broadcom", 295.44},
    {"AMD", "Advanced Micro Devices", 445.58},
    {"NFLX", "Netflix", 63.39},
    {"ORCL", "Oracle", 116.15},
    {"CRM", "Salesforce", 213.64},
    {"ADBE", "Adobe", 238.98},
    {"INTC", "Intel", 56.82},
    {"QCOM", "Qualcomm", 165.58},
    {"CSCO", "Cisco", 93.8},
    {"IBM", "IBM", 244.99},
    {"PLTR", "Palantir", 160.35},
    {"UBER", "Uber", 68.6},
    {"SHOP", "Shopify", 148.89},
    {"COIN", "Coinbase", 134.7},
    {"PYPL", "PayPal", 59.24},
    {"JPM", "JPMorgan Chase", 334.46},
    {"BAC", "Bank of America", 49.41},
    {"GS", "Goldman Sachs", 865.97},
    {"V", "Visa", 422.67},
    {"MA", "Mastercard", 652.87},
    {"WMT", "Walmart", 125.47},
    {"COST", "Costco", 1053.46},
    {"KO", "Coca-Cola", 95.67},
    {"PEP", "PepsiCo", 141.31},
    {"MCD", "McDonald's", 276.45},
    {"NKE", "Nike", 38.59},
    {"DIS", "Disney", 116.73},
    {"XOM", "Exxon Mobil", 165.88},
    {"CVX", "Chevron", 212.63},
    {"JNJ", "Johnson & Johnson", 276.33},
    {"PFE", "Pfizer", 29.39},
    {"LLY", "Eli Lilly", 1354.77},
    {"UNH", "UnitedHealth", 394.22},
    {"BA", "Boeing", 173.4},
    {"CAT", "Caterpillar", 558.66},
    {"GE", "GE Aerospace", 323.3},
    {"F", "Ford", 12.45},
    {"GM", "General Motors", 86.18},
    {"T", "AT&T", 21.62},
    {"VZ", "Verizon", 45.71},
    {"SPY", "SPDR S&P 500 ETF", 736.07},
    {"QQQ", "Invesco QQQ ETF", 656.87},
    {"QBTS", "D-Wave Quantum", 10.67}
  ]

  @names Map.new(@finnhub ++ @extra, fn {t, name, _} -> {t, name} end)

  @doc "The 5 tickers the Finnhub Worker polls."
  def finnhub, do: Enum.map(@finnhub, &elem(&1, 0))

  @doc "The 45 tickers the Alpaca poller covers."
  def extra, do: Enum.map(@extra, &elem(&1, 0))

  @doc "All 50, sorted."
  def all, do: Enum.sort(finnhub() ++ extra())

  def known?(ticker), do: Map.has_key?(@names, ticker)

  @doc "Company name for display, or the ticker itself if unknown."
  def name(ticker), do: Map.get(@names, ticker, ticker)

  @doc "Starting prices for a mock stream: `:finnhub` (the original 5) or `:extra` (45)."
  def mock_prices(:finnhub), do: Map.new(@finnhub, fn {t, _, p} -> {t, p} end)
  def mock_prices(:extra), do: Map.new(@extra, fn {t, _, p} -> {t, p} end)
end
