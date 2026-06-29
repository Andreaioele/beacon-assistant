defmodule BeaconAssistantWeb.PageController do
  use BeaconAssistantWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
