defmodule WorkerTest do
  use ExUnit.Case, async: true
  use Jazz

  setup_all do
    {:ok, _} = :application.ensure_all_started(:httparrot)
    :ok
  end

  test "get a valid url" do
    Axe.Worker.get self, "http://localhost:8080/get"
    assert_receive {:ok, data }, 1000
    assert_http_response(data)

    Axe.Worker.get self, "https://localhost:8433/get"
    assert_receive {:ok, data }, 1000
    assert_https_response(data)
  end

  test "automatically prefixes urls whith http" do
    Axe.Worker.get self, "localhost:8080/get"
    assert_receive {:ok, data }, 1000
    assert_http_response(data)
  end

  test "get an url returning an error code" do
    Axe.Worker.get self, "localhost:8080/status/500"
    assert_receive  {:ok, response }, 1000
    assert response.status_code == 500
    assert response.body == "Internal Server Error"
    assert response.resp_headers != nil

    Axe.Worker.get self, "https://localhost:8433/status/500"
    assert_receive  {:ok, response }, 1000
    assert response.status_code == 500
    assert response.body == "Internal Server Error"
    assert response.resp_headers != nil
  end

  test "follows a redirection" do
    Axe.Worker.get self, "localhost:8080/redirect-to?url=http://localhost:8080/get"
    assert_receive {:ok, response}, 1000
    assert_http_response(response)

    Axe.Worker.get self, "https://localhost:8433/redirect-to?url=https://localhost:8433/get"
    assert_receive {:ok, response}, 1000
    assert_https_response(response)
  end

  test "follows several redirection" do
    Axe.Worker.get self, "localhost:8080/redirect/4"
    assert_receive {:ok, response}, 1000
    assert_http_response(response)

    Axe.Worker.get self, "https://localhost:8433/redirect/4"
    assert_receive {:ok, response}, 1000
    assert_https_response(response)
  end

  test "follows several relative redirections" do
    Axe.Worker.get self, "localhost:8080/relative-redirect/4"
    assert_receive {:ok, response}, 1000
    assert_http_response(response)

    Axe.Worker.get self, "https://localhost:8433/relative-redirect/4"
    assert_receive {:ok, response}, 1000
    assert_https_response(response)
  end

  test "supports basic authentication" do
    Axe.Worker.get self, "http://user:password@localhost:8080/basic-auth/user/password"
    assert_receive {:ok, response}, 1000
    assert response.status_code == 200

    Axe.Worker.get self, "https://user:password@localhost:8433/basic-auth/user/password"
    assert_receive {:ok, response}, 1000
    assert response.status_code == 200
  end

  defp assert_http_response(response) do
    assert match?(%Axe.Response{}, response)
    assert response.status_code == 200
    assert response.resp_headers != nil
    json = JSON.decode!(response.body)
    assert json["url"] == "http://localhost:8080/get"
  end

  defp assert_https_response(response) do
    assert match?(%Axe.Response{}, response)
    assert response.status_code == 200
    assert response.resp_headers != nil
    json = JSON.decode!(response.body)
    assert json["url"] == "https://localhost:8433/get"
  end
end
