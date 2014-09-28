defmodule Axe do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      worker(Axe.Worker, []),
      worker(Agent, [fn -> %{} end, [name: :axe_agent]])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Axe.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
