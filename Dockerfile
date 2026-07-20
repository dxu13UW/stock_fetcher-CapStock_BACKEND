FROM elixir:1.19-alpine AS builder

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

RUN mkdir -p /app/db

CMD ["mix", "run", "--no-halt"]