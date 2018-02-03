defmodule Ace.HTTP1.Client do
  @moduledoc """
  Simple API client that makes streaming easy.

  This client will send any `Raxx.Request` struct to a server.
  Raxx provedes basic tools for manipulating requests.

      request = Raxx.request(:POST, "/headers")
      |> Raxx.set_header("accept", "application/json")
      |> Raxx.set_body("Hello, httpbin")

  ## Synchronous dispatch

  Send a request and wait for the complete response.
  The response will be a complete `Raxx.Response`.

      {:ok, response} = Ace.HTTP1.Client.send_sync(request, "http://httpbin.org")
      # => {:ok, %Raxx.Response{...

      response.status
      # => 200

  ## Asynchronous responses

  `send_sync/2` is a wrapper around the underlying async api.
  To send requests asynchronously use `send/2`

      {:ok, channel_ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")

      receive do: {^channel_ref, %Raxx.Response{}} -> :ok
      receive do: {^channel_ref, %Raxx.Data{}} -> :ok
      receive do: {^channel_ref, %Raxx.Tail{}} -> :ok

  - *A response with no body will return only a `Raxx.Response`*
  - *A response with a body can return any number of `Raxx.Data` parts*

  ## Streamed requests

  A request can have a body value of true indicating that the body will be sent later.
  The channel_ref returned when sending to an endpoint can be used to send follow up data.

      request = Raxx.request(:POST, "/headers")
      |> Raxx.set_header("accept", "application/json")
      |> Raxx.set_header("content-length", "13")
      |> Raxx.set_body(true)

      {:ok, channel_ref} = Ace.HTTP1.Client.send(request, "http://httpbin.org")

      data = Raxx.data("Hello, httpbin")
      {:ok, channel_ref} = Ace.HTTP1.Client.send(data, "http://httpbin.org")

      receive do: {^channel_ref, %Raxx.Response{}} -> :ok
      receive do: {^channel_ref, %Raxx.Data{}} -> :ok
      receive do: {^channel_ref, %Raxx.Tail{}} -> :ok

  NOTE: This module defines a `send/2` function clashes with `Kernel.send/2` if imported
  """

  import Kernel, except: [send: 2]

  @type channel_ref :: {:http1, pid(), integer}

  @doc """
  Start a client linked to the calling process to manage a HTTP/1 connection.

  The location of the server to connect to, must include the scheme and host

  ## Examples

      {:ok, client} = Ace.HTTP1.Client.start_link("http://httpbin.org")
  """
  def start_link(uri, options \\ []) do
    uri = URI.parse(uri)

    scheme = case uri.scheme do
      "https" ->
        :https
      "http" ->
        :http
      nil ->
        raise "Scheme must be provided when starting #{__MODULE__}"
    end

    host = uri.host
    port = uri.port

    GenServer.start_link(__MODULE__, {{scheme, host, port}, options})
  end


  @doc """
  Send a request, or part of, to a remote endpoint.
  """
  def send(client, request) when is_pid(client) do
    GenServer.call(client, {:send, self(), request})
  end
  # # channel would be called link
  def send(part, channel_ref = {:http1, endpoint, _monitor, _id}) do
    GenServer.call(endpoint, {:send, channel_ref, [part]})
  end

  @enforce_keys [
    # Link to the TCP or SSL connection
    :socket,

    # reference to the
    :channel,

    :receive_state,
    :dispatch_state,

    :authority,
  ]
  defstruct @enforce_keys

  @impl GenServer
  def init({location, options}) do
    {:ok, {:unconnected, location, options}}
  end

  def handle_call({:send, pid, request}, from, {:unconnected, location, options}) do
    case Ace.Socket.connect(location) do
      {:ok, socket} ->
        endpoint = %{socket: socket, options: options, channel: nil}
        handle_call({:send, pid, request}, from, endpoint)
      {:error, reason} ->
        {:reply, {:error, reason}, {:unconnected, location, options}}
    end
  end
  def handle_call({:send, pid, request}, _from, endpoint) do
    case endpoint.worker do
      nil ->
        monitor = Process.monitor(pid)

    end
  end
    # NOTE change 1 to latest id for streaming.
    # channel_number = 1
    #
    # channel_ref = {:http1, self(), channel_monitor, channel_number}
    #
    # monitor = Process.monitor(worker)
    # channel = {worker, monitor, channel_ref}
    # new_state = %{state | channel: channel}
    #
    # {packets, newer_state} = prepare(parts, new_state)
    # IO.inspect(packets)
    #
    # Ace.Socket.send(state.socket, packets)
    # {:reply, {:ok, channel_ref}, newer_state}
  # end
  def handle_call({:send, channel_ref, parts}, from, state = %{channel: {worker, monitor, channel_ref}}) do
    {packets, new_state} = prepare(parts, state)
    IO.inspect(packets)

    Ace.Socket.send(state.socket, packets)
    {:reply, {:ok, channel_ref}, new_state}
  end


  def handle_info({t, s, packet}, state = %{socket: {t, s}}) do
    IO.inspect(packet)
    case Ace.HTTP1.Parser.parse(packet, state.receive_state) do
      {:ok, {parts, receive_state}} ->
        {worker, worker_monitor, channel_ref} = state.channel
        Enum.each(parts, &Kernel.send(worker, {channel_ref, &1}))
        {:noreply, %{state | receive_state: receive_state}}
    end
  end
  def handle_info({transport, _socket}, state)
      when transport in [:tcp_closed, :ssl_closed] do
    {:stop, :normal, state}
  end

  defp prepare(parts, state) do
    Enum.reduce(parts, {[], state}, fn
      (request = %Raxx.Request{body: false}, {queue, state}) ->
        host = request.authority || state.authority
        headers = [{"host", host} | request.headers]

        start_line = [Atom.to_string(request.method), " ", raxx_to_path(request), " HTTP/1.1"]
        request = Enum.map([start_line] ++ raxx_header_lines(headers) ++ [""], fn(line) -> [line, "\r\n"] end)
        {queue ++ request, state}
      (request = %Raxx.Request{body: true}, {queue, state}) ->
        host = request.authority || state.authority
        {headers, state} = if raxx_header(request, "content-length") do
          headers = [{"host", host} | request.headers]
          {headers, %{state | dispatch_state: :body}}
        else
          headers = [{"host", host}, {"transfer-encoding", "chunked"} | request.headers]
          {headers, %{state | dispatch_state: :chunked_body}}
        end


        header_lines = Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
        request = Enum.map([raxx_start_line(request)] ++ header_lines ++ [""], fn(line) -> [line, "\r\n"] end)
        {queue ++ request, state}
      (request = %Raxx.Request{body: body}, {queue, state}) when is_binary(body) ->
        content_length = :erlang.iolist_size(body)
        host = request.authority || state.authority
        headers = [{"host", host}, {"content-length", "#{content_length}"} | request.headers]
        header_lines = Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
        request = Enum.map([raxx_start_line(request)] ++ header_lines ++ [""], fn(line) -> [line, "\r\n"] end)

        {queue ++ request ++ [body], state}
      (request = %Raxx.Data{data: data}, {queue, state = %{dispatch_state: :body}}) ->
        {queue ++ [data], state}
      (request = %Raxx.Data{data: data}, {queue, state = %{dispatch_state: :chunked_body}}) ->
        {queue ++ [Ace.HTTP1.serialize_chunk(data)], state}
      (request = %Raxx.Tail{}, {queue, state = %{dispatch_state: :chunked_body}}) ->
        {queue ++ [Ace.HTTP1.serialize_chunk("")], %{state | dispatch_state: :complete}}
    end)
  end

  defp raxx_header(%{headers: headers}, header, default \\ nil) do
    case :proplists.get_all_values("content-length", headers) do
      [] ->
        default
      [value] ->
        value
    end
  end

  defp raxx_start_line(request) do
    [Atom.to_string(request.method), " ", raxx_to_path(request), " HTTP/1.1"]
  end

  defp raxx_header_lines(headers) do
    Enum.map(headers, fn({k, v}) -> [k, ": ", v] end)
  end

  defp raxx_to_path(%{path: segments, query: query}) do
    path = "/" <> Enum.join(segments, "/")
    query_string = URI.encode_query(query || %{})
    query = if query_string == "", do: "", else: "?" <> query_string
    [path, query]
  end
end
