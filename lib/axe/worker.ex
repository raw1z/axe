defmodule Axe.Worker do
  use ExActor.GenServer, export: :axe_worker

  defmodule Request do
    defstruct url: nil, method: nil, headers: [], body: "", options: []
  end

  defstart start_link, do: initial_state(nil)

  defcast request(pid, url, method, headers \\ [], body \\ "", options \\ []) do
    do_request(pid, %Request{url: url, method: method, headers: headers, body: body, options: options})
    noreply
  end

  Enum.map [:get, :post, :put, :head, :delete, :patch], fn method ->
    defcast unquote(method)(pid, url, headers \\ [], body \\ "", options \\ []), when: is_pid(pid)  do
      do_request(pid, %Request{url: url, method: unquote(method), headers: headers, body: body, options: options})
      noreply
    end
  end

  defhandleinfo {:request, pid, request} do
    do_request(pid, request)
    noreply
  end

  defp do_request(pid, request) when is_pid(pid) do
    {:ok, session} = Axe.WorkerSession.start_link(pid)
    Axe.WorkerSession.execute_request session, request
  end
end
