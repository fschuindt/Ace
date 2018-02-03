# defmodule Ace.HTTP1.Client do
#   use GenServer
#
#
#   def send(client, request = %Raxx.Request{}) do
#     GenServer.call(client, {:send, self(), request})
#   end
#
#   ## SERVER CALLBACKS
#
#   @impl GenServer
#   def init({location, options}) do
#     {:ok, %{location: location}}
#   end
#
#   def handle_call({:send, pid, request}, from, {:unconnected, location, options}) do
#     case Ace.Socket.connect(state.location) do
#       {:ok, socket} ->
#         endpoint = Endpoint.client(socket, options)
#         handle_call({:send, pid, request}, from, endpoint)
#       {:error, reason} ->
#         {:reply, {:error, reason}, {:unconnected, location, options}}
#     end
#   end
#
#   def handle_call({:send, pid, request}, _from, endpoint) do
#     # channel = %{id, monitor, worker, endpoint}
#     {channel, endpoint} = Endpoint.open_channel(endpoint, pid, monitor)
#     case Endpoint.send(endpoint, channel, request) do
#       {:ok, {messages, endpoint}} ->
#         do_send(messages)
#         {:reply, {:ok, channel}, endpoint}
#     end
#   end
#   def handle_call({:send, channel, part}, _from, endpoint) do
#     case Endpoint.send(endpoint, channel, part) do
#       {:ok, {effects, endpoint}} ->
#         execute_effects(effects)
#         {:reply, {:ok, channel}, endpoint}
#
#     end
#   end
# end
#
#
# # endpoint
#
# # send_request(nil, nil) -> (body, response)
# # send_response(nil, nil) -> (error, :request must come first)
# # send_response(body, response)
