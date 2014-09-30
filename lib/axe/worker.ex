defmodule Axe.Worker do
  use ExActor.GenServer, export: :axe_worker

  defmodule Request do
    defstruct url: nil, method: nil, headers: [], body: ""
  end

  definit do
    initial_state(nil)
  end

  defcast request(pid, url, method) do
    do_request(pid, %Request{url: url, method: method})
    noreply
  end

  defcast request(pid, url, method, headers), when: is_list(headers) do
    do_request(pid, %Request{url: url, method: method, headers: headers})
    noreply
  end

  defcast request(pid, url, method, body), when: is_binary(body) do
    do_request(pid, %Request{url: url, method: method, body: body})
    noreply
  end

  defcast request(pid, url, method, headers, body) do
    do_request(pid, %Request{url: url, method: method, headers: headers, body: body})
    noreply
  end

  Enum.map [:get, :post, :put, :head, :delete, :patch], fn method ->
    defcast unquote(method)(pid, url), when: is_pid(pid)  do
      do_request(pid, %Request{url: url, method: unquote(method)})
      noreply
    end

    defcast unquote(method)(pid, url, headers), when: is_pid(pid) and is_list(headers) do
      do_request(pid, %Request{url: url, method: unquote(method), headers: headers})
      noreply
    end

    defcast unquote(method)(pid, url, body), when: is_pid(pid) and is_binary(body) do
      do_request(pid, %Request{url: url, method: unquote(method), body: body})
      noreply
    end

    defcast unquote(method)(pid, url, headers, body), when: is_pid(pid)  do
      do_request(pid, %Request{url: url, method: unquote(method), headers: headers, body: body})
      noreply
    end
  end

  definfo {:request, pid, request} do
    do_request(pid, request)
    noreply
  end

  defp do_request(pid, request) when is_pid(pid) do
    {:ok, session} = Axe.WorkerSession.start_link(pid)
    Axe.WorkerSession.execute_request session, request
  end
end
