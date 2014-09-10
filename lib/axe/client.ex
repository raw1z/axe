defmodule Axe.Client do

  Enum.map [:get, :head, :post, :put, :patch, :delete], fn method ->
    def unquote(method)(url), do: unquote(method)(url, [], "")
    def unquote(method)(url, headers) when is_list(headers), do: unquote(method)(url, headers, "")
    def unquote(method)(url, headers) when is_map(headers), do: unquote(method)(url, Map.to_list(headers), "")
    def unquote(method)(url, body) when is_binary(body), do: unquote(method)(url, [], body)
    def unquote(method)(url, headers, body) when is_map(headers) and is_binary(body), do: unquote(method)(url, Map.to_list(headers), body)
    def unquote(method)(url, headers, body) when is_list(headers) and is_binary(body) do
      my_pid = self

      func = fn ->
        Axe.Worker.unquote(method)(self, url, headers, body)
        receive do
          response ->
            send my_pid, response
        end
      end

      spawn(func)

      receive do
        {:ok, response} ->
          response
        {:error, error} ->
          error
        after
          5000 ->
            %Axe.Worker.Error{url: url, reason: "An error occurred", requester: self}
      end
    end
  end

end
