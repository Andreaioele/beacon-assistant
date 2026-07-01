defmodule BeaconAssistant.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BeaconAssistantWeb.Telemetry,
      BeaconAssistant.Repo,
      {DNSCluster, query: Application.get_env(:beacon_assistant, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BeaconAssistant.PubSub},
      {Task.Supervisor, name: BeaconAssistant.ChatTaskSupervisor},
      # Start a worker by calling: BeaconAssistant.Worker.start_link(arg)
      # {BeaconAssistant.Worker, arg},
      # Start to serve requests, typically the last entry
      BeaconAssistantWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BeaconAssistant.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeaconAssistantWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
