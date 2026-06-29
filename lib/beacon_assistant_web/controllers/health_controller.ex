defmodule BeaconAssistantWeb.HealthController do
  use BeaconAssistantWeb, :controller

  def show(conn, _params) do
    text(conn, "ok")
  end
end
