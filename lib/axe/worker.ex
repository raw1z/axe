defmodule Axe.Worker do
  use GenServer

  defmodule Request do
    defstruct url: nil, method: nil, headers: [], body: "", options: []
  end

  # Public API

  def start_link do
    GenServer.start_link __MODULE__, [], name: :axe_worker
  end

  def request(pid, url, method, headers \\ [], body \\ "", options \\ []) do
    GenServer.cast :axe_worker, {:request, pid, url, method, headers, body, options}
  end

  Enum.map [:get, :post, :put, :head, :delete, :patch], fn method ->
    def unquote(method)(pid, url, headers \\ [], body \\ "", options \\ []) when is_pid(pid) do
      GenServer.cast :axe_worker, {:request, pid, url, unquote(method), headers, body, options}
    end
  end

  # GenServer implementation

  def init([]) do
    {:ok, nil}
  end

  def handle_cast({:request, pid, url, method, headers, body, options}, _state) do
    do_request(pid, %Request{url: url, method: method, headers: headers, body: body, options: options})
    {:noreply, nil}
  end

  def handle_info({:request, pid, request}, _state) do
    do_request(pid, request)
    {:noreply, nil}
  end

  defp do_request(pid, request) when is_pid(pid) do
    {:ok, session} = Axe.WorkerSession.start_link(pid)
    Axe.WorkerSession.execute_request session, request
  end
end
