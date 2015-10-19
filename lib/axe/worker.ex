defmodule Axe.Worker do
  use GenServer

  defmodule Request do
    defstruct from: nil, url: nil, method: nil, headers: [], body: "", options: []
  end

  # Public API

  def start_link do
    GenServer.start_link __MODULE__, [], name: :axe_worker
  end

  def request(from, url, method, headers \\ [], body \\ "", options \\ []) when is_pid(from) do
    GenServer.cast :axe_worker, {:request, from, url, method, headers, body, options}
  end

  Enum.map [:get, :post, :put, :head, :delete, :patch], fn method ->
    def unquote(method)(from, url, headers \\ [], body \\ "", options \\ []) when is_pid(from) do
      GenServer.cast :axe_worker, {:request, from, url, unquote(method), headers, body, options}
    end
  end

  # GenServer implementation

  def init([]) do
    {:ok, nil}
  end

  def handle_cast({:request, from, url, method, headers, body, options}, _state) when is_pid(from) do
    request = %Request{
      from: from,
      url: url,
      method: method,
      headers: headers,
      body: body,
      options: options
    }

    do_request(request)

    {:noreply, nil}
  end

  def handle_cast({:request, %Request{from: from}=request}, _state) when is_pid(from) do
    do_request(request)
    {:noreply, nil}
  end

  defp do_request(request) do
    Axe.WorkerSessionSupervisor.start_session(request)
  end
end
