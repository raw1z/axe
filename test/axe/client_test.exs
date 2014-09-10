defmodule ClientTest do
  use ExUnit.Case, async: true
  use Jazz

  test "get a valid url" do
    Axe.Client.get self, "http://httpbin.org/get"
    assert_receive {:ok, data }, 5000
    assert_response(data)
  end

  test "automatically prefixes urls whith http" do
    Axe.Client.get self, "httpbin.org/get"
    assert_receive {:ok, data }, 5000
    assert_response(data)
  end

  test "get an url returning an error code" do
    Axe.Client.get self, "httpbin.org/status/500"
    assert_receive  {:ok, response }, 5000
    assert response.status_code == 500
    assert response.body == "INTERNAL SERVER ERROR"
    assert response.resp_headers != nil
  end

  test "follows a redirection" do
    Axe.Client.get self, "httpbin.org/redirect-to?url=http://httpbin.org/get"
    assert_receive {:ok, response}, 5000
    assert_response(response)
  end

  test "follows several redirection" do
    Axe.Client.get self, "httpbin.org/redirect/4"
    assert_receive {:ok, response}, 5000
    assert_response(response)
  end

  test "follows several relative redirections" do
    Axe.Client.get self, "httpbin.org/relative-redirect/4"
    assert_receive {:ok, response}, 5000
    assert_response(response)
  end

  test "supports basic authentication" do
    Axe.Client.get self, "http://user:password@httpbin.org/basic-auth/user/password"
    assert_receive {:ok, response}, 5000
    assert response.status_code == 200
  end

  defp assert_response(response) do
    assert match?(%Axe.Client.Response{}, response)
    assert response.status_code == 200
    assert response.resp_headers != nil
    json = JSON.decode!(response.body)
    assert json["url"] == "http://httpbin.org/get"
  end
end
