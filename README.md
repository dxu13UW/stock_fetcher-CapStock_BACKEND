# StockFetcher

**TODO: Add description**

## Installation

Step -1: Discord Daniel for .env file and api key

Step 0: make sure you have
Download Docker Desktop installed, it can be found here: https://www.docker.com/products/docker-desktop/

Step 1:
Unzip if zipped, then `cd path/to/extracted/stock_fetcher`

Step 2:
`docker-compose up -d --build`

Step 3:
Once Docker Desktop shows that your container is successfully Running, you can jump straight into the application's active memory playground to watch the workers execute:

- Open your Docker Desktop application interface.

- Click on Containers in the left sidebar and select the running stock_runner container.

- Click on the Terminal (or Exec) tab at the top.

Type this command to connect to the live application:
`iex -S mix`

- What you will see:

```
[Worker] Running parallel Finnhub fetch and writing to SQLite...
INSERT INTO "stock_prices" ("ticker","price",...) VALUES ("AAPL", 333.74...)
Successfully saved AAPL to SQLite!
```

## Run

turn on docker, ensure db is running

`iex -S mix`

`iex|1> Code.require_file("run_query.exs")`
