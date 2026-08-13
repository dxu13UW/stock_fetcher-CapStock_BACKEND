# --- Stage 1: Build Stage ---
FROM elixir:1.19-alpine AS builder

# Install C compilation tools required for SQLite C-NIFs (exqlite)
RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN mix compile
RUN mix release
FROM alpine:edge AS app

RUN apk add --no-cache libstdc++ sqlite-libs ca-certificates ncurses-libs openssl

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/stock_fetcher ./
RUN mkdir -p /app/db

ENV HOME=/app
EXPOSE 4000

CMD ["sh", "-c", "./bin/stock_fetcher eval 'StockFetcher.Release.migrate' && ./bin/stock_fetcher start"]