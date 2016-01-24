defmodule Axe.WorkerSession do
  use Axe.GenFSM
  use Axe.Logger

  alias Axe.SessionData

  require Record
  Record.defrecord :hackney_url, Record.extract(:hackney_url, from_lib: "hackney/include/hackney_lib.hrl")

  # Public API

  def start_link(request) do
    :gen_fsm.start_link(__MODULE__, request, [])
  end

  # GenFSM implementation

  def init(request) do
    {:ok, :idle, %SessionData{request: request}, 0}
  end

  def idle(:timeout, %{request: request}=session_data) do
    uri = {:hackney_url, _transport, _scheme, _netloc, _raw_path, _path, _qs, _fragment, _host, _port, user, password} = :hackney_url.parse_url(request.url)

    {url, headers} = 
      if String.length(user) > 0 do
        token = Base.encode64("#{user}:#{password}")
        url = hackney_url(uri, user: "", password: "") |> :hackney_url.unparse_url
        headers = [{"Authorization", "Basic #{token}"}|request.headers]
        {url, headers}
      else
        {:hackney_url.unparse_url(uri), request.headers}
      end

    Logger.debug """
    [axe] request:
      method: #{request.method}
      url: #{url}
      headers: #{inspect headers}
      body: #{request.body}
    """

    options = List.flatten [[:async, {:stream_to, self}], request.options]
    case :hackney.request(request.method, url, headers, request.body, options) do
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
          reason: reason
        }

        {:stop, :shutdown, %SessionData{ session_data | error: error }}
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
    data = << (session_data.data || "") :: binary, chunk :: binary >>
    session_data = %SessionData{ session_data | data: data }

    Logger.debug """
    [axe] received chunk:
      url: #{session_data.url}
      chunk: #{inspect chunk}
    """

    {:next_state, :chunk_received, session_data}
  end

  def handle_info({:hackney_response, _ref, :done}, _state_name, session_data) do
    {:stop, :normal, session_data}
  end

  def handle_info({:hackney_response, _ref, {:error, {:closed, reason}}}, _state_name, session_data) do
    error = %Axe.Error{
      url: session_data.url,
      reason: "CLOSED: #{reason}"
    }

    Logger.error """
    [axe] send error:
      url: #{error.url}
      error: #{inspect error}
    """

    {:stop, :shutdown, %SessionData{ session_data | error: error}}
  end

  def terminate(:shutdown, _state, %SessionData{request: request, error: error}) do
    send request.from, {:error, error}

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

      request = %Axe.Worker.Request{
        url: url,
        method: session_data.req_method,
        headers: session_data.req_headers,
        body: session_data.req_body,
        from: session_data.request.from
      }

      GenServer.cast :axe_worker, {:request, request}

      Logger.debug """
      [axe] redirected:
        from: #{session_data.url}
        to: #{request.url}
      """
    else
      error = %Axe.Error{
        url: session_data.url,
        reason: "WRONG REDIRECTION"
      }
      send session_data.request.from, error
    end

    :ok
  end

  def terminate(:normal, _state, %SessionData{}=session_data) do
    response = %Axe.Response{
      url: session_data.url,
      status_code: session_data.status_code,
      body: (session_data.data || session_data.info) || ""
    }

    if session_data.resp_headers != nil do
      response = %Axe.Response{ response | resp_headers: session_data.resp_headers |> Enum.into(%{}) }
    end

    send session_data.request.from, {:ok, response}

    Logger.debug """
    [axe] send response:
      url: #{session_data.url}
      response: #{inspect response}
    """

    :ok
  end
end
