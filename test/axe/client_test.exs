defmodule ClientTest do
  use ExUnit.Case, async: true

  setup_all do
    {:ok, _} = :application.ensure_all_started(:httparrot)
    :ok
  end

  test "get" do
    assert_response Axe.Client.get("localhost:8080/deny"), fn(response) ->
      assert :erlang.size(response.body) == 197
    end
  end

  test "head" do
    assert_response Axe.Client.head("localhost:8080/get"), fn(response) ->
      assert response.body == ""
    end
  end

  test "post" do
    assert_response Axe.Client.post("localhost:8080/post", [], "hello")
  end

  test "put" do
    assert_response Axe.Client.put("localhost:8080/put", [], "test")
  end

  test "patch" do
    assert_response Axe.Client.patch("localhost:8080/patch", [], "test")
  end

  test "delete" do
    assert_response Axe.Client.delete("localhost:8080/delete")
  end

  test "request headers as a map" do
    map_header = %{"X-Header" => "X-Value"}
    {:ok, response} = Axe.Client.get("localhost:8080/get", map_header)
    assert response.body =~ "X-Value"
  end

  test "basic_auth" do
    assert_response Axe.Client.get("http://user:pass@localhost:8080/basic-auth/user/pass")
  end

  defp assert_response({:ok, response}, function \\ nil) do
    assert response.status_code == 200
    assert is_binary(response.body)

    unless function == nil, do: function.(response)
  end
end
