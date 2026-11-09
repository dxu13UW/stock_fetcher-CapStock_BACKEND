defmodule StockFetcherWeb.HealthPageTest do
  use StockFetcherWeb.ConnCase, async: false

  test "GET /health is a self-refreshing HTML page", %{conn: conn} do
    conn = get(conn, "/health")

    assert html_response(conn, 200) =~ "Capstock health"
    assert conn.resp_body =~ ~s(http-equiv="refresh")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    # It skips the browser pipeline: no session cookie is set.
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "?format=json and Accept: application/json return the data", %{conn: conn} do
    body = conn |> get("/health?format=json") |> json_response(200)
    assert body["status"] in ~w(ok tight critical)
    assert is_number(body["beam"]["total_mb"])
    assert body["history"] == []

    accept = build_conn() |> put_req_header("accept", "application/json") |> get("/health")
    assert json_response(accept, 200)["processes"] > 0
  end

  test "with samples, the page draws its charts", %{conn: conn} do
    start_supervised!({StockFetcher.Health, interval: 1})
    Process.sleep(100)

    html = conn |> get("/health") |> html_response(200)
    assert html =~ "<polyline"

    # Times carry their UTC instant for the browser to show in local time; UTC without JS.
    assert html =~
             ~r/<time datetime="\d{4}-\d\d-\d\dT[^"]+Z" data-local>\d\d:\d\d:\d\d UTC<\/time>/

    assert html =~ "toLocaleTimeString"
  end

  test "the JSON API health check is unchanged", %{conn: conn} do
    assert conn |> get("/api/health") |> json_response(200) |> Map.fetch!("status") == "ok"
  end
end
