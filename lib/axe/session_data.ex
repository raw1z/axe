defmodule Axe.SessionData do
  defstruct ref: nil,
            url: nil,
            requester: nil,
            status_code: nil,
            resp_headers: nil,
            info: nil,
            data: nil,
            req_headers: nil,
            req_method: nil,
            req_body: nil

  def location(session) do
    get_location(session.resp_headers)
  end

  defp get_location([]), do: nil
  defp get_location([{"Location", location}|_]), do: location
  defp get_location([{"location", location}|_]), do: location
  defp get_location([_|tail]), do: get_location(tail)
end

