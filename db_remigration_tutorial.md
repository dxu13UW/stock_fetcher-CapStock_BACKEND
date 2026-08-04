## Step 1: Wipe Existing Docker Volumes & Containers

in a terminal, type:
`docker compose down -v`

## Step 2: Build & Start Fresh Containers

`docker compose up -d --build`

## Step 3: Run the Database Reset & Migration

`docker compose exec stock_runner mix ecto.setup`
then
`docker compose exec -e MIX_ENV=test stock_runner mix ecto.setup`

## Step 4: Verify with the Test Suite

test if migration is successful with insertion tests.
`docker compose exec -e MIX_ENV=test stock_runner mix test`
