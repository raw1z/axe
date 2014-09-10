defmodule Axe.Client do
  use ExActor.GenServer, export: :axe_client

  require Logger

  defmodule Session do
    defstruct ref: nil, url: nil, requester: nil, status_code: nil, resp_headers: nil, info: nil, data: "", req_headers: nil, req_method: nil, req_body: nil

    def location(session) do
      get_location(session.resp_headers)
    end

    defp get_location([]), do: nil
    defp get_location([{"Location", location}|_]), do: location
    defp get_location([{"location", location}|_]), do: location
    defp get_location([_|tail]), do: get_location(tail)
  end

  defmodule Response do
    defstruct url: nil, status_code: nil, resp_headers: nil, data: nil, body: nil
  end

  defmodule Error do
    defstruct url: nil, reason: nil, requester: nil
  end

  defmodule Request do
    defstruct url: nil, method: nil, headers: [], body: ""
  end

  require Record
  Record.defrecord :hackney_url, Record.extract(:hackney_url, from_lib: "hackney/include/hackney_lib.hrl")

  definit do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
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

  Enum.map [:get], fn method ->
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

  definfo {:hackney_response, ref, {:headers, headers}} do
    handle_headers(ref, headers)
    noreply
  end

  definfo {:hackney_response, ref, {:status, status_code, reason}}, state: _ do
    handle_status_code(ref, status_code, reason)
    noreply
  end

  definfo {:hackney_response, ref, chunk}, when: is_binary(chunk) do
    handle_chunk(ref, chunk)
    noreply
  end

  definfo {:hackney_response, ref, :done} do
    handle_done(ref)
    noreply
  end

  definfo {:hackney_response, ref, {:error, {:closed, reason}}} do
    session = get_session(ref)
    if session.status_code in [302, 301] do
      follow_redirection(session)
    else
      send session.requester, %Error{ url: session.url, requester: session.requester, reason: reason }
    end
    noreply
  end

  definfo {:hackney_response, ref, {:error, reason}} do
    session = get_session(ref)
    send session.requester, %Error{ url: session.url, requester: session.requester, reason: reason }
    noreply
  end

  def do_request(pid, request) when is_pid(pid) do
    uri = {:hackney_url, _transport, scheme, netloc, _raw_path, path, _qs, _fragment, _host, _port, user, password} = :hackney_url.parse_url(request.url)
    if String.length(user) > 0 do
      token = Base.encode64("#{user}:#{password}")
      url = :hackney_url.unparse_url hackney_url(uri, user: "", password: "")
      headers = [{"Authorization", "Basic #{token}"}|request.headers]
    else
      url = :hackney_url.unparse_url(uri)
      headers = request.headers
    end

    case :hackney.request(request.method, url, headers, request.body, [:async, {:stream_to, self}]) do
      {:ok, client_ref} ->
        register_session %Session{
          url: url,
          requester: pid,
          ref: client_ref,
          req_headers: headers,
          req_method: request.method,
          req_body: request.body
        }

      {:error, reason} ->
        send pid, %Error{ url: request.url, requester: pid, reason: reason }
    end
  end

  defp handle_status_code(ref, 200, _) do
    session = get_session(ref)
    update_session %Session{ session | status_code: 200 }
  end

  defp handle_status_code(ref, status_code, reason) do
    session = get_session(ref)
    update_session %Session{ session | status_code: status_code, info: reason }
  end

  defp handle_headers(ref, headers) do
    session = get_session(ref)
    update_session %Session{ session | resp_headers: headers }
  end

  defp handle_chunk(ref, chunk) do
    session = get_session(ref)
    data = << session.data :: binary, chunk :: binary >>
    update_session %Session{ session | data: data }
  end

  defp handle_done(ref) do
    get_session(ref)
    |> process_session
    |> delete_session
  end

  defp register_session(new_session) do
    Agent.update(__MODULE__, &Map.put(&1, new_session.ref, new_session))
  end

  defp get_session(ref) do
    Agent.get(__MODULE__, &Map.get(&1, ref))
  end

  defp update_session(session) do
    Agent.update(__MODULE__, &Map.put(&1, session.ref, session))
  end

  defp delete_session(session) do
    Agent.update(__MODULE__, &Map.delete(&1, session.ref))
  end

  defp process_session(%Session{status_code: 200} = session) do
    response = %Response{
      url: session.url,
      status_code: session.status_code,
      resp_headers: session.resp_headers,
      body: session.data
    }
    send session.requester, {:ok, response}
    session
  end

  defp process_session(%Session{status_code: status_code} = session) when status_code in [302, 301] do
    url = Session.location(session)
    if url != nil do
      follow_redirection(session)
    else
      send session.pid, %Error{ url: session.url, requester: session.requester, reason: "WRONG REDIRECTION" }
    end
    session
  end

  defp process_session(%Session{status_code: status_code} = session) do
    response = %Response{
      url: session.url,
      status_code: session.status_code,
      resp_headers: session.resp_headers,
      body: session.info
    }
    send session.requester, {:ok, response}
    session
  end

  defp follow_redirection(session) do
    url = Session.location(session)
    if URI.parse(url).host == nil do
      uri = URI.parse(session.url)
      url = "#{uri.scheme}://#{uri.authority}#{url}"
    end

    request session.requester, url, session.req_method, session.req_headers, session.req_body
  end
end
