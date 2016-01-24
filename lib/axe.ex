defmodule Axe do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      supervisor(Axe.WorkerSessionSupervisor, []),
      worker(Axe.Worker, []),
      worker(Agent, [fn -> %{} end, [name: :axe_agent]])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Axe.Supervisor]
    Supervisor.start_link(children, opts)
  end

  Enum.map [:get, :head, :post, :put, :patch, :delete], fn method ->
    def unquote(method)(url, headers \\ [], body \\ "", options \\ [])
    def unquote(method)(url, headers, body, options) when is_map(headers) and is_binary(body), do: unquote(method)(url, Map.to_list(headers), body, options)
    def unquote(method)(url, headers, body, options) when is_list(headers) and is_binary(body) do
      Axe.Client.unquote(method)(url, headers, body, options)
    end
  end
end
