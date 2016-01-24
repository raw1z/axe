defmodule Axe.WorkerSessionSupervisor do
  use Supervisor

  @name :worker_session_supervisor

  # public API

  def start_link do
    Supervisor.start_link __MODULE__, [], name: @name
  end

  def start_session(request) do
    @name
    |> Process.whereis
    |> Supervisor.start_child([request])
  end

  # Supervior implementation

  def init([]) do
    children = [
      worker(Axe.WorkerSession, [], restart: :transient)
    ]
    supervise children, strategy: :simple_one_for_one
  end
end

