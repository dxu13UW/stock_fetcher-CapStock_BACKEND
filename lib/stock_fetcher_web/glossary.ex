defmodule StockFetcherWeb.Glossary do
  @moduledoc """
  Trading words for people who don't trade, shown by the glossary popup on `/prices`
  (Space Space opens it, Esc closes it; 2026-11-08).

  Plain data, so the definitions are easy to review in one place. Each term has:
    * `:id` - stable slug, used for the row's DOM id and in `:related`
    * `:term` - the word as the app shows it
    * `:aliases` - other spellings searched by the filter ("TP", "slippage")
    * `:short` - one line, shown in the list
    * `:body` - the full explanation
    * `:in_app` - how Capstock uses it (nil when there's nothing app-specific to say)
    * `:related` - ids of terms worth reading next

  The filter matches `:term` and `:aliases` only, not the explanations: matching every word of
  every definition would match almost anything and leave the flash labels no free letters.
  """

  @terms [
    %{
      id: "account-value",
      term: "Account value",
      aliases: ["equity", "net worth"],
      short: "What the whole portfolio is worth right now.",
      body:
        "Your cash plus what your positions are worth at current prices. It moves with every " <>
          "price tick, even when you don't trade.",
      in_app:
        "The big number on the portfolio card. A short counts as the cash set aside for it plus " <>
          "its profit or loss.",
      related: ["p-l", "buying-power", "position"]
    },
    %{
      id: "avg-cost",
      term: "Avg cost",
      aliases: ["average cost", "average price", "cost basis"],
      short: "The average price you paid per share.",
      body:
        "If you buy 10 shares at $100 and 10 more at $110, your average cost is $105. Profit and " <>
          "loss are measured from this price.",
      in_app: "A column in Positions. For a short, it's the average price you sold at.",
      related: ["position", "p-l", "break-even"]
    },
    %{
      id: "bracket",
      term: "Bracket",
      aliases: ["bracket order"],
      short: "An entry with its take-profit and stop-loss attached.",
      body:
        "Three orders planned together: the entry, a take-profit above it and a stop-loss below " <>
          "it (the other way round for a short). The two exits 'bracket' the price.",
      in_app:
        "An exit-strategy panel places a bracket. Open orders groups each bracket as a small price " <>
          "ladder with the live price between its exits.",
      related: ["limit-entry", "take-profit", "stop-loss", "oco"]
    },
    %{
      id: "break-even",
      term: "Break-even",
      aliases: ["breakeven"],
      short: "The price where a trade neither makes nor loses money.",
      body:
        "For a simple trade, your entry price. Traders often move their stop to break-even once a " <>
          "trade is going well, so it can no longer lose.",
      in_app: "Use Move on an open stop-loss to raise it to your entry price.",
      related: ["stop-loss", "entry", "avg-cost"]
    },
    %{
      id: "buying-power",
      term: "Buying power",
      aliases: ["starting cash"],
      short: "How much cash you have to trade with.",
      body:
        "The money available for new trades. Buying shares, or setting cash aside for a short, " <>
          "uses it up; selling gives it back.",
      in_app:
        "You choose it when you start a new portfolio ($1,000 to $2,000,000). P/L is measured " <>
          "from it.",
      related: ["account-value", "cash-secured-short", "paper-trading"]
    },
    %{
      id: "candlestick",
      term: "Candlestick",
      aliases: ["candle", "ohlc"],
      short: "One bar of the chart: open, high, low and close for a period.",
      body:
        "The thick body runs from the opening price to the closing price; the thin wicks show the " <>
          "highest and lowest prices. Green means it closed higher than it opened, red lower.",
      in_app: "Each candle is 5 minutes on live prices and 1 minute on the mock stream.",
      related: ["ticker", "market-hours"]
    },
    %{
      id: "cash-secured-short",
      term: "Cash-secured short",
      aliases: ["set aside", "margin"],
      short: "A short whose full value is held back from your cash.",
      body:
        "Real brokers lend you shares to short on margin, with rules about how much you must " <>
          "keep. Capstock keeps it simple: shorting sets aside the short's whole value from cash.",
      in_app: "The cash comes back, plus or minus the profit or loss, when you cover.",
      related: ["short", "cover", "buying-power"]
    },
    %{
      id: "cover",
      term: "Cover",
      aliases: ["buy to cover"],
      short: "Buying shares back to close a short.",
      body:
        "A short sells shares you don't own; covering buys them back. If you cover below the price " <>
          "you shorted at, you made money.",
      in_app:
        "The Cover button in Short selling. A short's take-profit and stop-loss also cover.",
      related: ["short", "exit", "position"]
    },
    %{
      id: "day-trading",
      term: "Day trading",
      aliases: ["day trader", "intraday"],
      short: "Opening and closing trades within the same day.",
      body:
        "Day traders try to profit from moves during the day and usually hold nothing overnight. " <>
          "Most lose money, which is why practising on paper first is worth it.",
      in_app: nil,
      related: ["paper-trading", "market-hours", "risk"]
    },
    %{
      id: "entry",
      term: "Entry",
      aliases: ["entry price", "open"],
      short: "The order, or price, where a trade starts.",
      body:
        "Buying to go long, or shorting to go short, is your entry. Its price is the base for " <>
          "your risk and target.",
      in_app: "In an exit-strategy panel the entry is a limit price: the order waits for it.",
      related: ["exit", "limit-entry", "risk"]
    },
    %{
      id: "exit",
      term: "Exit",
      aliases: ["close"],
      short: "The order that ends a trade.",
      body:
        "Selling a long position, or covering a short. An exit planned in advance is either a " <>
          "take-profit (you were right) or a stop-loss (you were wrong).",
      in_app: nil,
      related: ["entry", "take-profit", "stop-loss", "exit-strategy"]
    },
    %{
      id: "exit-strategy",
      term: "Exit strategy",
      aliases: ["trade plan"],
      short: "Deciding how a trade ends before you enter it.",
      body:
        "Where you'll take profit and where you'll admit you're wrong, set before emotions get " <>
          "involved. It's the habit that separates a plan from a gamble.",
      in_app:
        "The four sidebar panels: Long or Short, each with a take-profit or a stop-loss to learn " <>
          "and place.",
      related: ["take-profit", "stop-loss", "bracket", "r-r"]
    },
    %{
      id: "fill",
      term: "Fill",
      aliases: ["filled", "execution"],
      short: "When an order actually happens, and at what price.",
      body:
        "An order is a request; a fill is the trade. A market order fills right away; a limit or " <>
          "stop order fills later, if the price gets there.",
      in_app:
        "Strict fills: a limit fills only when the price trades through it, and a stop fills at " <>
          "the next price, which can be worse than the stop.",
      related: ["market-order", "limit-order", "stop", "gap"]
    },
    %{
      id: "gap",
      term: "Gap",
      aliases: ["slippage"],
      short: "The price jumps past a level without trading in between.",
      body:
        "News or a quiet open can move the price from $50 straight to $47. A stop at $49 then " <>
          "fills at $47, not $49: the difference is slippage.",
      in_app: "Capstock fills stops at the tick price, so gaps cost you here too.",
      related: ["stop", "stop-loss", "fill"]
    },
    %{
      id: "iex",
      term: "IEX",
      aliases: ["exchange", "investors exchange"],
      short: "One US stock exchange, whose prices are free in real time.",
      body:
        "A stock trades on many exchanges at once. IEX handles a few percent of the volume, so its " <>
          "last price is usually within a cent or so of the whole market's.",
      in_app: "Where 45 of the 50 live tickers get their prices (through Alpaca).",
      related: ["sip", "ticker"]
    },
    %{
      id: "limit-entry",
      term: "Limit entry",
      aliases: [],
      short: "A limit order that opens a position.",
      body:
        "Instead of buying now, you wait for a better price: a long limit below today's price, a " <>
          "short limit above it. If the price never gets there, you never get in.",
      in_app:
        "What every exit-strategy panel places. Its take-profit and stop-loss are created when it " <>
          "fills.",
      related: ["limit-order", "entry", "bracket"]
    },
    %{
      id: "limit-order",
      term: "Limit order",
      aliases: ["limit"],
      short: "An order that fills only at your price or better.",
      body:
        "A buy limit at $100 never pays more than $100; a sell limit at $110 never takes less than " <>
          "$110. You control the price, but the order may never fill.",
      in_app: "Take-profits and limit entries are limit orders.",
      related: ["market-order", "limit-entry", "take-profit", "fill"]
    },
    %{
      id: "long",
      term: "Long",
      aliases: ["go long", "buy"],
      short: "Owning shares, betting the price goes up.",
      body:
        "Buy low, sell high. The most you can lose is what you paid; the gain has no ceiling.",
      in_app: "Buy opens a long position, Sell closes it.",
      related: ["short", "position", "entry"]
    },
    %{
      id: "market-hours",
      term: "Market hours",
      aliases: ["market closed", "regular session", "trading hours"],
      short: "9:30 a.m. to 4:00 p.m. Eastern, Monday to Friday.",
      body:
        "US stocks trade mainly in these hours. Outside them prices barely move, or trade thinly in " <>
          "pre-market and after-hours sessions.",
      in_app:
        "Live orders are refused while the market is closed. The mock stream trades around the " <>
          "clock.",
      related: ["day-trading", "candlestick"]
    },
    %{
      id: "market-order",
      term: "Market order",
      aliases: ["market"],
      short: "An order that fills now, at the current price.",
      body:
        "You get in or out right away but don't choose the price. In fast markets it can be worse " <>
          "than the last price you saw.",
      in_app: "Buy, Sell, Short and Cover are market orders, filled at the price on screen.",
      related: ["limit-order", "fill"]
    },
    %{
      id: "oco",
      term: "OCO",
      aliases: ["one cancels the other", "one-cancels-other"],
      short: "One-cancels-the-other: when one exit fills, the other is cancelled.",
      body:
        "A take-profit and a stop-loss guard the same shares. Once one of them closes the trade, " <>
          "the other must go, or it could open a new position by accident.",
      in_app: "Every bracket's two exits are OCO.",
      related: ["bracket", "take-profit", "stop-loss"]
    },
    %{
      id: "open-order",
      term: "Open order",
      aliases: ["pending order", "resting order", "working order"],
      short: "An order waiting for its price.",
      body: "A limit or stop order that hasn't filled yet. It can still be moved or cancelled.",
      in_app:
        "The Open orders panel. They're watched only while this tab is open; click one to see its " <>
          "exits on the chart.",
      related: ["limit-order", "stop", "bracket"]
    },
    %{
      id: "p-l",
      term: "P/L",
      aliases: ["profit and loss", "pnl", "p&l", "unrealized", "realized"],
      short: "Profit and loss: how much you're up or down.",
      body:
        "Unrealized P/L is on positions you still hold and changes with the price; realized P/L is " <>
          "locked in once you exit.",
      in_app:
        "Positions shows each position's unrealized P/L. The portfolio card shows the total since " <>
          "you started.",
      related: ["avg-cost", "account-value", "position"]
    },
    %{
      id: "paper-trading",
      term: "Paper trading",
      aliases: ["simulated", "simulator", "paper"],
      short: "Practice trading with fake money and real prices.",
      body:
        "Every trade is simulated, so you can test a strategy and keep an honest record of whether " <>
          "it works before risking real money.",
      in_app: "Everything in Capstock. No real orders, brokers or money.",
      related: ["day-trading", "buying-power"]
    },
    %{
      id: "position",
      term: "Position",
      aliases: ["positions", "holding"],
      short: "The shares you hold, or owe if short, in one stock.",
      body:
        "Buying 10 shares opens a long position of 10; shorting 10 opens a short position of -10. " <>
          "Exiting closes it.",
      in_app: "The Positions panel, with quantity, average cost, price and P/L.",
      related: ["long", "short", "avg-cost", "p-l"]
    },
    %{
      id: "position-size",
      term: "Position size",
      aliases: ["size"],
      short: "How big a trade is: price times shares.",
      body:
        "100 shares at $20 is a $2,000 position. Sizing a trade so a stop-loss costs only a small " <>
          "slice of your account is how traders survive losing streaks.",
      in_app: "The risk preview under each exit-strategy form shows it before you place.",
      related: ["risk", "r-r", "account-value"]
    },
    %{
      id: "r-r",
      term: "R:R",
      aliases: ["risk reward", "risk to reward", "reward risk"],
      short: "Risk-to-reward ratio: what you could lose versus what you could make.",
      body:
        "Risk $100 to make $200 and the R:R is 1:2. With 1:2 you can be wrong more often than " <>
          "right and still come out ahead.",
      in_app: "Shown in the risk preview once both a stop-loss and a take-profit are filled in.",
      related: ["risk", "target", "stop-loss", "take-profit"]
    },
    %{
      id: "risk",
      term: "Risk",
      aliases: ["at risk"],
      short: "What you lose if the stop-loss is hit.",
      body:
        "(Entry - stop) × shares for a long, the other way round for a short. Traders often keep it " <>
          "to 1-2% of the account per trade.",
      in_app: "The risk preview shows it in dollars and as a percent of your account.",
      related: ["stop-loss", "r-r", "position-size", "target"]
    },
    %{
      id: "share",
      term: "Share",
      aliases: ["stock", "quantity", "qty"],
      short: "One unit of a company's stock.",
      body:
        "A share's price is what the last buyer and seller agreed on. Quantity (Qty) is how many " <>
          "shares an order or position has.",
      in_app: "Capstock trades whole shares only.",
      related: ["ticker", "position"]
    },
    %{
      id: "short",
      term: "Short",
      aliases: ["short selling", "go short", "shorting"],
      short: "Selling shares you don't own, betting the price goes down.",
      body:
        "Sell high now, buy back (cover) lower later. The gain is capped at the share price falling " <>
          "to zero, but a rising price can lose more than the short was worth.",
      in_app: "The Short selling card. Shorts are cash-secured.",
      related: ["cover", "long", "cash-secured-short", "stop-loss"]
    },
    %{
      id: "sip",
      term: "SIP",
      aliases: ["consolidated feed", "securities information processor"],
      short: "The combined price feed from every US exchange.",
      body:
        "The official 'whole market' view. Real-time SIP data costs money; delayed history is free.",
      in_app: "The chart's 5-minute history comes from SIP; the live ticks on top come from IEX.",
      related: ["iex", "candlestick"]
    },
    %{
      id: "stop",
      term: "Stop",
      aliases: ["stop order", "stop price"],
      short: "An order that turns into a market order when the price reaches it.",
      body:
        "It waits at a trigger price. Once the price touches it, the order fills at whatever the " <>
          "price is then, which after a gap can be worse than the stop.",
      in_app: "Every stop-loss is a stop order.",
      related: ["stop-loss", "trigger", "gap", "limit-order"]
    },
    %{
      id: "stop-loss",
      term: "Stop-loss",
      aliases: ["sl", "stop loss"],
      short: "An exit that closes a losing trade at a price you set.",
      body:
        "For a long it sits below the entry, for a short above it. It caps the loss of a trade " <>
          "that goes wrong, so one bad trade can't sink the account.",
      in_app: "Drawn in orange on the chart when you click its open order.",
      related: ["take-profit", "stop", "risk", "oco"]
    },
    %{
      id: "take-profit",
      term: "Take-profit",
      aliases: ["tp", "take profit", "profit target"],
      short: "An exit that closes a winning trade at your target price.",
      body:
        "For a long it sits above the entry, for a short below it. It's a limit order, so it never " <>
          "fills at a worse price than your target.",
      in_app: "Drawn in blue on the chart when you click its open order.",
      related: ["stop-loss", "target", "limit-order", "oco"]
    },
    %{
      id: "target",
      term: "Target",
      aliases: ["reward"],
      short: "What you make if the take-profit is hit.",
      body: "(Take-profit - entry) × shares for a long, the other way round for a short.",
      in_app: "Shown in the risk preview as 'target'.",
      related: ["take-profit", "r-r", "risk"]
    },
    %{
      id: "ticker",
      term: "Ticker",
      aliases: ["symbol", "ticker symbol"],
      short: "A stock's short code, like AAPL for Apple.",
      body: "Every listed stock has one. Traders say the ticker rather than the company name.",
      in_app: "Pick one in the watchlist, or press / to search by ticker or company name.",
      related: ["watchlist", "share"]
    },
    %{
      id: "trigger",
      term: "Trigger",
      aliases: ["trigger price"],
      short: "The price an open order is waiting for.",
      body: "A stop's stop price, or a limit's limit price. Reaching it lets the order fill.",
      in_app:
        "The Move box on an open order changes its trigger. A price that would fill instantly is " <>
          "refused.",
      related: ["stop", "limit-order", "open-order"]
    },
    %{
      id: "watchlist",
      term: "Watchlist",
      aliases: [],
      short: "The list of stocks you're following.",
      body: "A trader's short list of tickers to keep an eye on during the day.",
      in_app: "The 50 tickers on the right. Click one to chart it and trade it.",
      related: ["ticker"]
    }
  ]

  @ids MapSet.new(@terms, & &1.id)

  for %{id: id, related: related} <- @terms, rel <- related, not MapSet.member?(@ids, rel) do
    raise "glossary term #{inspect(id)} relates to unknown term #{inspect(rel)}"
  end

  @doc "All terms, alphabetical by `:term`."
  def terms, do: Enum.sort_by(@terms, &String.downcase(&1.term))

  @doc "One term by id, or nil."
  def get(id), do: Enum.find(@terms, &(&1.id == id))
end
