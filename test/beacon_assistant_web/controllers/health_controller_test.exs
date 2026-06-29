defmodule BeaconAssistantWeb.HealthControllerTest do
  use BeaconAssistantWeb.ConnCase

  test "GET /health returns a plain text liveness response", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end
end
