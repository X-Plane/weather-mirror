defmodule WeatherMirror.StripTransferEncoding do
  @moduledoc """
  I don't have the patience to change our transfer mechanism in Cowboy based on the transfer encoding of the source...
  """
  @behaviour :cowboy_stream

  def info(stream_id, {:response, status, headers, body}, state) do
    clean_headers = Map.drop(headers, ["Transfer-Encoding"])
    :cowboy_stream.info(stream_id, {:response, status, clean_headers, body}, state)
  end

  # Defaults for everything else
  def info(stream_id, info, state), do: :cowboy_stream.info(stream_id, info, state)
  def init(stream_id, req, opts), do: :cowboy_stream.init(stream_id, req, opts)

  def data(stream_id, is_fin, info, state),
    do: :cowboy_stream.data(stream_id, is_fin, info, state)

  def early_error(stream_id, reason, partial_req, resp, opts),
    do: :cowboy_stream.early_error(stream_id, reason, partial_req, resp, opts)

  def terminate(stream_id, reason, state), do: :cowboy_stream.terminate(stream_id, reason, state)
end
