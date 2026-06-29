defmodule BeaconAssistant.Repo do
  use Ecto.Repo,
    otp_app: :beacon_assistant,
    adapter: Ecto.Adapters.Postgres
end
