defmodule Ockam.Messaging.Ordering.Tests.Shuffle do
  @moduledoc """
  Worker to shuffle forwarded messages

  Spawns a process for each message
  """
  use Ockam.Worker

  alias Ockam.Message

  require Logger

  @impl true
  def handle_message(message, state) do
    spawn(fn ->
      forward_message(message, state)
    end)

    {:ok, state}
  end

  def forward_message(message, _state) do
    :timer.sleep(10)
    Logger.info("Forward #{inspect(message)}")
    [_me | onward_route] = Message.onward_route(message)

    Ockam.Router.route(%{
      onward_route: onward_route,
      return_route: Message.return_route(message),
      payload: Message.payload(message)
    })
  end
end
