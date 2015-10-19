defmodule Axe.SessionData do
  defstruct request: nil,
            ref: nil,
            url: nil,
            status_code: nil,
            resp_headers: nil,
            info: nil,
            data: nil,
            req_headers: nil,
            req_method: nil,
            req_body: nil,
            error: nil

  def location(session) do
    get_location(session.resp_headers)
  end

  defp get_location([]), do: nil
  defp get_location([{"Location", location}|_]), do: location
  defp get_location([{"location", location}|_]), do: location
  defp get_location([_|tail]), do: get_location(tail)
end

