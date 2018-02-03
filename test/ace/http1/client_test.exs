defmodule Ace.HTTP1.ClientTest do
  use ExUnit.Case, async: true

  alias Ace.HTTP1.Client

  # REQUEST

  describe "established client" do
    setup %{} do
      {:ok, client} = Client.start_link("http://httpbin.org")
      {:ok, %{client: client}}
    end
    test "sends the correct method", %{client: client} do
      request = Raxx.request(:GET, "/anything")

      {:ok, channel} = Client.send(client, request)
      #
      #
      # assert String.contains?(response.body, "\"method\": \"GET\"")
      #
      # request = Raxx.request(:DELETE, "/anything")
      # {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
      #
      # assert String.contains?(response.body, "\"method\": \"DELETE\"")
    end

  end


  @tag :skip
  test "adds host header from connection if not given" do
    request = Raxx.request(:GET, "/headers")

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")

    assert String.contains?(response.body, "\"Host\": \"httpbin.org\"")
  end

  @tag :skip
  test "sends correct host header from request" do
    request = Raxx.request(:GET, "/headers")
    request = %{request | authority: "httpbin.org"}

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")

    assert String.contains?(response.body, "\"Host\": \"httpbin.org\"")
  end

  @tag :skip
  test "can send data with request" do
    request = Raxx.request(:POST, "/post")
    |> Raxx.set_body("Hello, World!")

    {:ok, ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")
    assert_receive {^ref, %Raxx.Response{}}, 1_000
    assert_receive {^ref, %Raxx.Data{}}, 1_000
    assert_receive {^ref, %Raxx.Tail{}}, 1_000
  end

  @tag :skip
  test "can send data after request with content_length" do
    request = Raxx.request(:POST, "/post")
    |> Raxx.set_header("content-length", "13")
    |> Raxx.set_body(true)

    {:ok, ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")

    data = Raxx.data("Hello, World!")
    {:ok, ref} = Ace.HTTP1.Client.send(data, ref)
    assert_receive {^ref, %Raxx.Response{}}, 1_000
    assert_receive {^ref, %Raxx.Data{}}, 1_000
    assert_receive {^ref, %Raxx.Tail{}}, 1_000
  end

  @tag :skip
  test "can send chunked data when no content-length given" do
    request = Raxx.request(:POST, "/post")
    |> Raxx.set_body(true)

    {:ok, ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")
    data = Raxx.data("Hello, ")
    assert {:ok, ^ref} = Ace.HTTP1.Client.send(data, ref)
    data = Raxx.data("World!")
    {:ok, ^ref} = Ace.HTTP1.Client.send(data, ref)
    tail = Raxx.tail()
    {:ok, ^ref} = Ace.HTTP1.Client.send(tail, ref)

    assert_receive {^ref, %Raxx.Response{}}, 1_000
    assert_receive {^ref, %Raxx.Data{}}, 1_000
    assert_receive {^ref, %Raxx.Tail{}}, 1_000
  end

  @tag :skip
  test "returns error if unable to connect to endpoint" do
    request = Raxx.request(:GET, "/")

    # TODO we need to somehow forward error
    :ignore = Ace.HTTP1.Client.send_sync(request, "http://fooo.dummy")
  end

  # RESPONSE

  @tag :skip
  test "decodes correct status" do
    request = Raxx.request(:GET, "/status/503")

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
    assert response.status == 503
  end

  @tag :skip
  test "decodes response headers" do
    request = Raxx.request(:GET, "/response-headers?lowercase=foo&UPPERCASE=BAR")

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
    assert "foo" == :proplists.get_value("lowercase", response.headers)
    assert "BAR" == :proplists.get_value("uppercase", response.headers)
  end

  @tag :skip
  test "body will be added to response" do
    request = Raxx.request(:GET, "/drip?numbytes=5&duration=1")

    {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
    assert "*****" = response.body
  end

    @tag :skip
  test "body message will be received for every streamed chunk" do
    request = Raxx.request(:GET, "/stream/2")

    {:ok, ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")
    assert_receive {^ref, %Raxx.Response{status: 200}}
    assert_receive {^ref, %Raxx.Data{}}
    assert_receive {^ref, %Raxx.Data{data: _}}
    assert_receive {^ref, %Raxx.Tail{}}
  end

  @tag :skip
  test "will timeout after delay" do
    request = Raxx.request(:GET, "/delay/10")

    assert {:error, {:timeout, 5_000}} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
  end
end
