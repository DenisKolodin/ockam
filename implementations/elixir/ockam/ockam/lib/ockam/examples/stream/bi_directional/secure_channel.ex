defmodule Ockam.Examples.Stream.BiDirectional.SecureChannel do
  @moduledoc """

  Ping-pong example for bi-directional stream communication

  Use-case: integrate ockam nodes which implement stream protocol consumer and publisher

  Pre-requisites:

  Ockam hub running with stream service and TCP listener

  Two ockam nodes "ping" and "pong"

  Expected behaviour:

  Two nodes "ping" and "pong" send messages to each other using two streams:
  "sc_listener_topic" to send messages to "pong" node
  "sc_initiator_topic" to send messages to "ping" node

  Implementation:

  Stream service is running on the hub node

  Ping and pong nodes create local consumers and publishers to exchange messages

  Ping establishes an ordered channel to pong over the stream publisher

  Ping creates a secure channel over the ordered channel

  Ping exchanges messages with ping using the secure channel
  """
  alias Ockam.SecureChannel
  alias Ockam.Vault
  alias Ockam.Vault.Software, as: SoftwareVault

  alias Ockam.Examples.Ping
  alias Ockam.Examples.Pong

  alias Ockam.Stream.Client.BiDirectional
  alias Ockam.Stream.Client.BiDirectional.PublisherRegistry

  alias Ockam.Messaging.PipeChannel

  alias Ockam.Messaging.Ordering.Strict.IndexPipe

  alias Ockam.Transport.TCP

  require Logger

  ## Ignore no local return for secure channel
  @dialyzer :no_return

  def simple_ping_pong() do
    {:ok, "pong"} = Pong.create(address: "pong")
    {:ok, "ping"} = Ping.create(address: "ping")
    send_message(["pong"], ["ping"], "0")
  end

  def outline() do
    ## On one node:
    Ockam.Examples.Stream.BiDirectional.SecureChannel.init_pong()

    ## On another node:
    Ockam.Examples.Stream.BiDirectional.SecureChannel.run()
  end

  def config() do
    %{
      hub_ip: "127.0.0.1",
      hub_port: 4000,
      hub_port_udp: 7000,
      service_address: "stream_kafka",
      index_address: "stream_kafka_index",
      ping_stream: "ping_stream",
      pong_stream: "pong_stream"
    }
  end

  def init_pong() do
    TCP.start()

    ## PONG worker
    {:ok, "pong"} = Pong.create(address: "pong")

    ## Create secure channel listener
    create_secure_channel_listener()

    ## Create ordered channel spawner
    {:ok, "ord_channel_spawner"} =
      PipeChannel.Spawner.create(
        responder_options: [pipe_mods: IndexPipe],
        address: "ord_channel_spawner"
      )

    config = config()
    ## Create a local subscription to forward pong_topic messages to local node
    subscribe(config.pong_stream, "pong", :tcp)
  end

  def run() do
    TCP.start()

    ## PING worker
    {:ok, "ping"} = Ping.create(address: "ping")

    config = config()
    ## Subscribe to response topic
    subscribe(config.ping_stream, "ping", :tcp)

    ## Create local publisher worker to forward to pong_topic and add metadata to
    ## messages to send responses to ping_topic
    {:ok, publisher} = init_publisher(config.pong_stream, config.ping_stream, "ping", :tcp)

    ## Create an ordered channel over the stream communication
    ## Strictly ordered channel would de-duplicate messages
    {:ok, ord_channel} =
      PipeChannel.Initiator.create(
        pipe_mods: IndexPipe,
        spawner_route: [publisher, "ord_channel_spawner"]
      )

    ## Create a secure channel over the ordered channel
    {:ok, channel} = create_secure_channel([ord_channel, "SC_listener"])

    ## Send a message THROUGH the channel to the remote worker
    send_message([channel, "pong"], ["ping"], "0")
  end

  def init_publisher(publisher_stream, consumer_stream, subscription_id, protocol \\ :tcp) do
    BiDirectional.ensure_publisher(
      consumer_stream,
      publisher_stream,
      subscription_id,
      stream_options(protocol)
    )
  end

  def subscribe(stream, subscription_id, protocol \\ :tcp) do
    ## Local subscribe
    ## Create bidirectional subscription on local node
    ## using stream service configuration from stream_options
    {:ok, consumer} = BiDirectional.subscribe(stream, subscription_id, stream_options(protocol))

    wait(fn ->
      # Logger.info("Consumer: #{consumer} ready?")
      ready = Ockam.Stream.Client.Consumer.ready?(consumer)
      # Logger.info("#{ready}")
      ready
    end)

    ## This is necessary to make sure we don't spawn publisher for each message
    PublisherRegistry.start_link([])
  end

  defp create_secure_channel_listener() do
    {:ok, vault} = SoftwareVault.init()
    {:ok, identity} = Vault.secret_generate(vault, type: :curve25519)

    SecureChannel.create_listener(
      vault: vault,
      identity_keypair: identity,
      address: "SC_listener"
    )
  end

  defp create_secure_channel(route_to_listener) do
    {:ok, vault} = SoftwareVault.init()
    {:ok, identity} = Vault.secret_generate(vault, type: :curve25519)

    {:ok, c} =
      SecureChannel.create(route: route_to_listener, vault: vault, identity_keypair: identity)

    wait(fn -> SecureChannel.established?(c) end)
    {:ok, c}
  end

  defp wait(fun) do
    case fun.() do
      true ->
        :ok

      false ->
        :timer.sleep(100)
        wait(fun)
    end
  end

  def send_message(onward_route, return_route, payload) do
    msg = %{
      onward_route: onward_route,
      return_route: return_route,
      payload: payload
    }

    Ockam.Router.route(msg)
  end

  def ensure_udp(port) do
    Ockam.Transport.UDP.start(port: port)
  end

  def stream_options(protocol) do
    config = config()

    {:ok, hub_ip_n} = :inet.parse_address(to_charlist(config.hub_ip))
    tcp_address = Ockam.Transport.TCPAddress.new(hub_ip_n, config.hub_port)

    udp_address = Ockam.Transport.UDPAddress.new(hub_ip_n, config.hub_port_udp)

    hub_address =
      case protocol do
        :tcp -> tcp_address
        :udp -> udp_address
      end

    [
      service_route: [hub_address, config.service_address],
      index_route: [hub_address, config.index_address],
      partitions: 1
    ]
  end
end
