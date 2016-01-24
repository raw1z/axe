defmodule Axe.Client do

  Enum.map [:get, :head, :post, :put, :patch, :delete], fn method ->
    def unquote(method)(url, headers \\ [], body \\ "", options \\ [])
    def unquote(method)(url, headers, body, options) when is_map(headers) and is_binary(body), do: unquote(method)(url, Map.to_list(headers), body, options)
    def unquote(method)(url, headers, body, options) when is_list(headers) and is_binary(body) do
      my_pid = self
      {timeout, options} = Keyword.pop_first(options, :timeout, 30_000)

      func = fn ->
        Axe.Worker.unquote(method)(self, url, headers, body, options)
        receive do
          response ->
            send my_pid, response
        end
      end

      spawn(func)

      receive do
        data ->
          data
        after
          timeout ->
            %Axe.Error{url: url, reason: "An error occurred"}
      end
    end
  end

end
