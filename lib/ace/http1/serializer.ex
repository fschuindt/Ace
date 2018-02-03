# defmodule Ace.HTTP1.Serializer do
#   @enforce_keys [
#     :body,
#   ]
#
#   def serialize(head = %{body: false}) do
#     {serialize_head(head), :done}
#   end
#   def serialize(head = %{body: true}) do
#     case raxx_content_length(head) do
#       nil ->
#         # Add transfer encoding chunked
#         {serialize_head(head), %__MODULE__{body: :chunked}}
#       length when length > 0 ->
#         {serialize_head(head), %__MODULE__{body: {:remaining, length}}}
#     end
#   end
#   def serialize(message = %{body: body}) do
#     content_length = raxx_content_length(message) || :erlang.iolist_size(body)
#     message = raxx_set_content_length(content_length)
#     # Could call serialize body to check too long too short or already chunked
#     {serialize_head(message) <> body, :done}
#   end
#
#   defp serialize_head(%Raxx.Resonse{}) do
#
#   end
#   defp serialize_head(%Raxx.Request{}) do
#
#   end
# end
