defmodule Axe.WorkerSession do
  use Axe.GenFSM
  require Logger

  defmodule SessionData do
    defstruct ref: nil, url: nil, requester: nil, status_code: nil, resp_headers: nil, info: nil, data: "", req_headers: nil, req_method: nil, req_body: nil

    def location(session) do
      get_location(session.resp_headers)
    end

    defp get_location([]), do: nil
    defp get_location([{"Location", location}|_]), do: location
    defp get_location([{"location", location}|_]), do: location
    defp get_location([_|tail]), do: get_location(tail)
  end

  require Record
  Record.defrecord :hackney_url, Record.extract(:hackney_url, from_lib: "hackney/include/hackney_lib.hrl")

  # Public API

  def start_link(requester) do
    :gen_fsm.start_link(__MODULE__, requester, [])
  end

  def execute_request(pid, request) do
    :gen_fsm.send_event pid, {:execute_request, request}
  end

  # GenFSM implementation

  def init(requester) do
    {:ok, :idle, %SessionData{requester: requester}}
  end

  def idle({:execute_request, request}, session_data) do
    uri = {:hackney_url, _transport, _scheme, _netloc, _raw_path, _path, _qs, _fragment, _host, _port, user, password} = :hackney_url.parse_url(request.url)
    if String.length(user) > 0 do
      token = Base.encode64("#{user}:#{password}")
      url = :hackney_url.unparse_url hackney_url(uri, user: "", password: "")
      headers = [{"Authorization", "Basic #{token}"}|request.headers]
    else
      url = :hackney_url.unparse_url(uri)
      headers = request.headers
    end

    Logger.debug """
    [axe] request:
      method: #{request.method}
      url: #{url}
      headers: #{inspect headers}
      body: #{request.body}
    """

    case :hackney.request(request.method, url, headers, request.body, [:async, {:stream_to, self}]) do
      {:ok, client_ref} ->
        session_data = %SessionData{session_data |
          url: url,
          ref: client_ref,
          req_headers: headers,
          req_method: request.method,
          req_body: request.body }
        {:next_state, :started, session_data}

      {:error, reason} ->
        error = %Axe.Error{
          url: request.url,
          requester: session_data.requester,
          reason: reason }
        {:stop, :shutdown, error}
    end
  end

  def handle_info({:hackney_response, _ref, {:status, 200, _}}, :started, session_data) do
    session_data = %SessionData{session_data | status_code: 200}

    Logger.debug """
    [axe] received status code:
      url: #{session_data.url}
      status_code: 200
    """

    {:next_state, :status_code_received, session_data}
  end

  def handle_info({:hackney_response, _ref, {:status, status_code, reason}}, :started, session_data) do
    session_data = %SessionData{ session_data | status_code: status_code, info: reason }

    Logger.debug """
    [axe] received status code:
      url: #{session_data.url}
      status_code: #{status_code}
      info: #{reason}
    """

    {:next_state, :status_code_received, session_data}
  end

  def handle_info {:hackney_response, _ref, {:headers, headers}}, :status_code_received, session_data do
    session_data = %SessionData{ session_data | resp_headers: headers }

    Logger.debug """
    [axe] received headers:
      url: #{session_data.url}
      headers: #{inspect headers}
    """

    {:next_state, :headers_received, session_data}
  end

  def handle_info({:hackney_response, _ref, chunk}, state_name, session_data) when is_binary(chunk) and state_name in [:headers_received, :chunk_received] do
    data = << session_data.data :: binary, chunk :: binary >>
    session_data = %SessionData{ session_data | data: data }

    Logger.debug """
    [axe] received chunk:
      url: #{session_data.url}
      chunk: #{inspect chunk}
    """

    {:next_state, :chunk_received, session_data}
  end

  def handle_info({:hackney_response, _ref, :done}, state_name, session_data) when state_name in [:chunk_received, :headers_received] do
    {:stop, :normal, session_data}
  end

  def handle_info {:hackney_response, ref, {:error, reason}}, _state_name, session_data do
    error = %Axe.Error{
      url: session_data.url,
      requester: session_data.requester,
      reason: reason }
    {:stop, :shutdown, error}
  end

  def handle_info(msg, state_name, session_data) do
    Logger.error """
    [axe] received unmanaged message:
      url: #{session_data.url}
      state: #{state_name}
      data: #{inspect session_data}
      message: #{inspect msg}
    """
    {:next_state, state_name, session_data}
  end

  def terminate(:error, _state, error) do
    send error.requester, {:error, error}

    Logger.error """
    [axe] send error:
      url: #{error.url}
      error: #{inspect error}
    """

    :ok
  end

  def terminate(:normal, _state, %SessionData{status_code: status_code}=session_data) when status_code in [301, 302] do
    url = SessionData.location(session_data)
    if url != nil do
      if URI.parse(url).host == nil do
        uri = URI.parse(session_data.url)
        url = "#{uri.scheme}://#{uri.authority}#{url}"
      end

      request = %Axe.Worker.Request{url: url, method: session_data.req_method, headers: session_data.req_headers, body: session_data.req_body}
      {:ok, session} = __MODULE__.start_link session_data.requester
      __MODULE__.execute_request session, request

      Logger.debug """
      [axe] redirected:
        from: #{session_data.url}
        to: #{request.url}
      """
    else
      send session_data.requester, %Axe.Error{ url: session_data.url, requester: session_data.requester, reason: "WRONG REDIRECTION" }
    end

    :ok
  end

  def terminate(:normal, _state, %SessionData{}=session_data) do
    response = %Axe.Response{
      url: session_data.url,
      status_code: session_data.status_code,
      resp_headers: session_data.resp_headers |> Enum.into(%{}),
      body: session_data.info || session_data.data
    }

    send session_data.requester, {:ok, response}

    Logger.debug """
    [axe] send response:
      url: #{session_data.url}
      response: #{inspect response}
    """

    :ok
  end

  def terminate(_reason, _state_name, _state_data) do
    :ok
  end
end
