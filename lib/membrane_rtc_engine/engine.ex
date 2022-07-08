defmodule Membrane.RTC.Engine do
  @moduledoc """
  RTC Engine implementation.

  RTC Engine is an abstraction layer responsible for linking together different types of `Endpoints`.
  From the implementation point of view, RTC Engine is a `Membrane.Pipeline`.

  ## Messages

  The RTC Engine works by sending messages which notify user logic about important events like
  "There is a new peer, would you like to to accept it?".
  To receive RTC Engine messages you have to register your process so that RTC Engine will
  know where to send them.
  All messages RTC Engine can emit are described in `#{inspect(__MODULE__)}.Message` docs.

  ### Registering for messages

  Registration can be done using `register/2` e.g.

  ```elixir
  Engine.register(rtc_engine, self())
  ```

  This will register your process to receive RTC Engine messages.
  If your process implements `GenServer` behavior then all messages can be handled
  by `c:GenServer.handle_info/2`, e.g.

  ```elixir
  @impl true
  def handle_info(%Message.NewPeer{rtc_engine: rtc_engine, peer: peer}, state) do
    Engine.accept_peer(rtc_engine, peer.id)
    {:noreply, state}
  end
  ```

  You can register multiple processes to receive messages from an RTC Engine instance.
  In such a case each message will be sent to each registered process.

  ## Client Libraries

  RTC Engine allows creating Client Libraries that can send and receive media tracks from it.
  The current version of RTC Engine ships with WebRTC Client Library which connects to the RTC Engine
  via WebRTC standard.
  Communication with Client Libraries is done using `Media Events`.
  Media Events are control messages which notify about e.g. new peer joining to the RTC Engine.
  When Client Library receives Media Event it can invoke some callbacks.
  In the case of WebRTC Client Library, these are e.g. `onPeerJoined` or `onTrackAdded`.
  When RTC Engine receives Media Event it can emit some messages e.g. `t:#{inspect(__MODULE__)}.Message.NewPeer.t/0`.
  More about Media Events can be read in subsequent sections.
  Below there is a figure showing the architecture of the RTC Engine working in conjunction with some Client Library.

  ```txt
      +--------------------------------- media events -----------------------------+
      |                                (signaling layer)                           |
      |                                                                            |
      |                                                                            |
  +--------+                 +---------+             +--------+               +---------+
  | user   | <-   media   -> | Client  |             |  RTC   | <- media   -> | user    |
  | client |      events     | Library | <- media -> | Engine |    events     | backend |
  | logic  | <- callbacks -  |         |             |        | - messages -> | logic   |
  +--------+                 +---------+             +--------+               +---------+
  ```



  ### Media Events

  Media Events are blackbox messages that carry data important for the
  RTC Engine and its Client Library, but not for the user.
  There are two types of Media Events:
  * Internal Media Events - generic, protocol-agnostic Media Events sent by RTC Engine itself.
  Example Internal Media Events are `peerJoined`, `peerLeft`, `tracksAdded` or `tracksRemoved`.
  * Custom Media Events - they can be used to send custom data from Client Library to some Endpoint inside RTC Engine
  and vice versa. In the case of WebRTC Client Library, these are `sdpOffer`, `sdpAnswer`, or `iceCandidate`.

  An application is obligated to transport Media Events from an RTC Engine instance to
  its Client Library, and vice versa.

  When the RTC Engine needs to send a Media Event to a specific client, registered processes will
  receive `t:#{inspect(__MODULE__)}.Message.MediaEvent.t/0` message with `to` field indicating where this Media Event
  should be sent to.
  This can be either `:broadcast`, when the event should be sent to all peers, or `peer_id`
  when the messages should be sent to the specified peer. The `event` is encoded in binary format,
  so it is ready to send without modification.

  Feeding an RTC Engine instance with Media Events from a Client Library can be done using `receive_media_event/2`.
  Assuming the user process is a GenServer, the Media Event can be received by `c:GenServer.handle_info/2` and
  conveyed to the RTC Engine in the following way:

  ```elixir
  @impl true
  def handle_info({:media_event, from, event} = msg, state) do
    Engine.receive_media_event(state.rtc_engine, from, event)
    {:noreply, state}
  end
  ```

  What is important, Membrane RTC Engine doesn't impose usage of any specific transport layer for carrying
  Media Events through the network.
  You can e.g. use Phoenix and its channels.
  This can look like this:

  ```elixir
  @impl true
  def handle_in("mediaEvent", %{"data" => event}, socket) do
    Engine.receive_media_event(socket.assigns.room, socket.assigns.peer_id, event)
    {:noreply, socket}
  end
  ```

  ## Peers

  Each peer represents some user that can possess some metadata.
  A Peer can be added in two ways:
  * by sending proper Media Event from a Client Library
  * using `add_peer/3`

  Adding a peer will cause RTC Engine to emit Media Event which will notify connected clients about new peer.

  ### Peer id

  Peer ids must be assigned by application code. This is not done by the RTC Engine or its client library.
  Ids can be assigned when a peer initializes its signaling layer.

  ## Endpoints

  `Endpoints` are `Membrane.Bin`s able to publish their own tracks and subscribe for tracks from other Endpoints.
  One can think about Endpoint as an entity responsible for handling some specific task.
  An Endpoint can be added and removed using `add_endpoint/3` and `remove_endpoint/2` respectively.

  There are two types of Endpoints:
  * Standalone Endpoints - they are in most cases spawned only once per RTC Engine instance and they are not associated with any peer.
  * Peer Endpoints - they are associated with some peer.
  Associating Endpoint with Peer will cause RTC Engine to send some Media Events to the Enpoint's Client Library
  e.g. one which indicates which tracks belong to which peer.

  Currently RTC Engine ships with the implementation of two Endpoints:
  * `#{inspect(__MODULE__)}.Endpoint.WebRTC` which is responsible for establishing a connection with some WebRTC
  peer (mainly browser) and exchanging media with it. WebRTC Endpoint is a Peer Endpoint.
  * `#{inspect(__MODULE__)}.Endpoint.HLS` which is responsible for receiving media tracks from all other Endpoints and
  saving them to files by creating HLS playlists. HLS Endpoint is a Standalone Endpoint.

  User can also implement custom Endpoints.

  ### Implementing custom RTC Engine Endpoint

  Each RTC Engine Endpoint has to:
  * implement `Membrane.Bin` behavior
  * specify input, output, or both input and output pads depending on what it is intended to do.
  For example, if Endpoint will not publish any tracks but only subscribe for tracks from other Endpoints it can specify only input pads.
  Pads should have the following form

  ```elixir
    def_input_pad :input,
      demand_unit: :buffers,
      caps: <caps>,
      availability: :on_request

    def_output_pad :output,
      demand_unit: :buffers,
      caps: <caps>,
      availability: :on_request
  ```

  Where `caps` are `t:Membrane.Caps.t/0` or `:any`.

  * publish for some tracks using actions `t:publish_action_t/0` and subscribe for some tracks using
  function `#{inspect(__MODULE__)}.subscribe/5`. The first will cause RTC Engine to send a message in
  form of `{:new_tracks, tracks}` where `tracks` is a list of `t:#{inspect(__MODULE__)}.Track.t/0` to all other Endpoints.
  When an Endpoint receives such a message it can subscribe for new tracks by
  using `#{inspect(__MODULE__)}.subscribe/5` function. An Endpoint will be notified about track readiness
  it subscribed for in `c:Membrane.Bin.handle_pad_added/3` callback. An example implementation of `handle_pad_added`
  callback can look like this

  ```elixir
    @impl true
    def handle_pad_added(Pad.ref(:input, _track_id) = pad, _ctx, state) do
      links = [
        link_bin_input(pad)
        |> via_in(pad)
        |> to(:my_element)
      ]

      {{:ok, spec: %ParentSpec{links: links}}, state}
    end
  ```

  Where `:my_element` is a custom Membrane element responsible for processing track.

  Endpoint will be also notified when some tracks it subscribed for are removed with
  `{:removed_tracks, tracks}` message where `tracks` is a list of `t:#{inspect(__MODULE__)}.Track.t/0`.
  """

  use Membrane.Pipeline

  import Membrane.RTC.Utils

  alias Membrane.RTC.Engine.{
    DisplayManager,
    Endpoint,
    Endpoint.WebRTC.SimulcastTee,
    FilterTee,
    MediaEvent,
    Message,
    Peer,
    PushOutputTee,
    Subscription,
    Track
  }

  require Membrane.Logger
  require Membrane.OpenTelemetry
  require Membrane.TelemetryMetrics

  @registry_name Membrane.RTC.Engine.Registry.Dispatcher

  @life_span_id "rtc_engine.life_span"

  @typedoc """
  RTC Engine configuration options.

  * `id` is used by logger. If not provided it will be generated.
  * `trace_ctx` is used by OpenTelemetry. All traces from this engine will be attached to this context.
  Example function from which you can get Otel Context is `get_current/0` from `OpenTelemetry.Ctx`.
  * `display_manager?` - set to `true` if you want to limit number of tracks sent from `#{inspect(__MODULE__)}.Endpoint.WebRTC` to a browser.
  """

  @type options_t() :: [
          id: String.t(),
          trace_ctx: map(),
          telemetry_label: Membrane.TelemetryMetrics.label(),
          display_manager?: boolean()
        ]

  @typedoc """
  Endpoint configuration options.

  * `peer_id` - associate endpoint with exisiting peer
  * `endpoint_id` - assign endpoint id. If not provided it will be generated by RTC Engine. This option cannot be used together with `peer_id`.
  Endpoints associated with peers have the id `peer_id`.
  * `node` - node on which endpoint should be spawned. If not provided, current node is used.
  """
  @type endpoint_options_t() :: [
          endpoint_id: String.t(),
          peer_id: String.t(),
          node: node()
        ]

  @typedoc """
  Subscription options.

  * `default_simulcast_encoding` - initial encoding that
  endpoint making subscription wants to receive.
  This option has no effect for audio tracks and video tracks
  that are not simulcast.

  """
  @type subscription_opts_t() :: [default_simulcast_encoding: String.t()]

  @typedoc """
  Membrane action that will cause RTC Engine to publish some message to all other endpoints.
  """
  @type publish_action_t() :: {:notify, {:publish, publish_message_t()}}

  @typedoc """
  Membrane action that will inform RTC Engine about track readiness.
  """
  @type track_ready_action_t() ::
          {:notify,
           {:track_ready, Track.id(), Track.encoding(),
            depayloading_filter :: Membrane.ParentSpec.child_spec_t()}}

  @typedoc """
  Membrane action that will generate Custom Media Event.
  """
  @type custom_media_event_action_t() :: {:notify, {:custom_media_event, data :: binary()}}

  @typedoc """
  Types of messages that can be published to other Endpoints.
  """
  @type publish_message_t() :: {:new_tracks, [Track.t()]} | {:removed_tracks, [Track.t()]}

  @spec start(options :: options_t(), process_options :: GenServer.options()) ::
          GenServer.on_start()
  def start(options, process_options) do
    do_start(:start, options, process_options)
  end

  @spec start_link(options :: options_t(), process_options :: GenServer.options()) ::
          GenServer.on_start()
  def start_link(options, process_options) do
    do_start(:start_link, options, process_options)
  end

  defp do_start(func, options, process_options) when func in [:start, :start_link] do
    id = options[:id] || "#{UUID.uuid4()}"
    display_manager? = options[:display_manager?] || false
    options = Keyword.put(options, :id, id)
    options = Keyword.put(options, :display_manager?, display_manager?)
    Membrane.Logger.info("Starting a new RTC Engine instance with id: #{id}")
    apply(Membrane.Pipeline, func, [__MODULE__, options, process_options])
  end

  @spec get_registry_name() :: atom()
  def get_registry_name(), do: @registry_name

  @doc """
  Adds endpoint to the RTC Engine

  Returns `:error` when there are both `peer_id` and `endpoint_id` specified in `opts`.
  For more information refer to `t:endpoint_options_t/0`.
  """
  @spec add_endpoint(
          pid :: pid(),
          endpoint :: Membrane.ParentSpec.child_spec_t(),
          opts :: endpoint_options_t()
        ) :: :ok | :error
  def add_endpoint(pid, endpoint, opts \\ []) do
    if Keyword.has_key?(opts, :endpoint_id) and Keyword.has_key?(opts, :peer_id) do
      raise "You can't pass both option endpoint_id and peer_id"
    end

    send(pid, {:add_endpoint, endpoint, opts})
    :ok
  end

  @doc """
  Removes endpoint from the RTC Engine
  """
  @spec remove_endpoint(
          pid :: pid(),
          id :: String.t()
        ) :: :ok
  def remove_endpoint(rtc_engine, id) do
    send(rtc_engine, {:remove_endpoint, id})
    :ok
  end

  @doc """
  Adds peer to the RTC Engine
  """
  @spec add_peer(pid :: pid(), peer :: Peer.t()) :: :ok
  def add_peer(pid, peer) do
    send(pid, {:add_peer, peer})
    :ok
  end

  @doc """
  Removes peer from RTC Engine.

  If reason is other than `nil`, RTC Engine will inform client library about peer removal with passed reason.
  """
  @spec remove_peer(rtc_engine :: pid(), peer_id :: any(), reason :: String.t() | nil) :: :ok
  def remove_peer(rtc_engine, peer_id, reason \\ nil) do
    send(rtc_engine, {:remove_peer, peer_id, reason})
    :ok
  end

  @doc """
  Allows peer for joining to the RTC Engine
  """
  @spec accept_peer(pid :: pid(), peer_id :: String.t()) :: :ok
  def accept_peer(pid, peer_id) do
    send(pid, {:accept_new_peer, peer_id})
    :ok
  end

  @doc """
  Deny peer from joining to the RTC Engine.
  """
  @spec deny_peer(pid :: pid(), peer_id :: String.t()) :: :ok
  def deny_peer(pid, peer_id) do
    send(pid, {:deny_new_peer, peer_id})
    :ok
  end

  @doc """
  The same as `deny_peer/2` but allows for passing any data that will be returned to the client.

  This can be used for passing reason of peer refusal.
  """
  @spec deny_peer(pid :: pid(), peer_id :: String.t(), data: any()) :: :ok
  def deny_peer(pid, peer_id, data) do
    send(pid, {:deny_new_peer, peer_id, data})
    :ok
  end

  @doc """
  Registers process with pid `who` for receiving messages from RTC Engine
  """
  @spec register(rtc_engine :: pid(), who :: pid()) :: :ok
  def register(rtc_engine, who \\ self()) do
    send(rtc_engine, {:register, who})
    :ok
  end

  @doc """
  Unregisters process with pid `who` from receiving messages from RTC Engine
  """
  @spec unregister(rtc_engine :: pid(), who :: pid()) :: :ok
  def unregister(rtc_engine, who \\ self()) do
    send(rtc_engine, {:unregister, who})
    :ok
  end

  @doc """
  Sends Media Event to RTC Engine.
  """
  @spec receive_media_event(rtc_engine :: pid(), media_event :: {:media_event, pid(), any()}) ::
          :ok
  def receive_media_event(rtc_engine, media_event) do
    send(rtc_engine, media_event)
    :ok
  end

  @doc """
  Subscribes endpoint for tracks.

  Endpoint  will be notified about track readiness in `c:Membrane.Bin.handle_pad_added/3` callback.
  `tracks` is a list in form of pairs `{track_id, track_format}`, where `track_id` is id of track this endpoint subscribes for
  and `track_format` is the format of track that this endpoint is willing to receive.
  If `track_format` is `:raw` Endpoint will receive track in `t:#{inspect(__MODULE__)}.Track.encoding/0` format.
  Endpoint_id is a an id of endpoint, which want to subscribe on tracks.
  """
  @spec subscribe(
          rtc_engine :: pid(),
          endpoint_id :: String.t(),
          track_id :: Track.id(),
          format :: atom(),
          opts :: subscription_opts_t
        ) ::
          :ok
          | {:error,
             :timeout
             | :invalid_track_id
             | :invalid_track_format
             | :invalid_default_simulcast_encoding}
  def subscribe(rtc_engine, endpoint_id, track_id, format, opts \\ []) do
    ref = make_ref()
    send(rtc_engine, {:subscribe, {self(), ref}, endpoint_id, track_id, format, opts})

    receive do
      {^ref, :ok} -> :ok
      {^ref, {:error, reason}} -> {:error, reason}
    after
      5_000 -> {:error, :timeout}
    end
  end

  @impl true
  def handle_init(options) do
    Logger.metadata(rtc_engine_id: options[:id])

    if Keyword.has_key?(options, :trace_ctx),
      do: Membrane.OpenTelemetry.attach(options[:trace_ctx])

    start_span_opts =
      case options[:parent_span] do
        nil -> []
        parent_span -> [parent_span: parent_span]
      end

    Membrane.OpenTelemetry.start_span(@life_span_id, start_span_opts)

    display_manager =
      if options[:display_manager?] do
        {:ok, pid} = DisplayManager.start_link(ets_name: options[:id], engine: self())
        pid
      else
        nil
      end

    telemetry_label = (options[:telemetry_label] || []) ++ [room_id: options[:id]]

    {{:ok, playback: :playing},
     %{
       id: options[:id],
       component_path: Membrane.ComponentPath.get_formatted(),
       trace_context: options[:trace_ctx],
       telemetry_label: telemetry_label,
       peers: %{},
       endpoints: %{},
       pending_subscriptions: [],
       filters: %{},
       subscriptions: %{},
       display_manager: display_manager
     }}
  end

  @impl true
  def handle_playing_to_prepared(ctx, state) do
    {actions, state} =
      state.peers
      |> Map.keys()
      |> Enum.reduce({[], state}, fn peer_id, {all_actions, state} ->
        {actions, state} = handle_remove_peer(peer_id, "playback_finished", ctx, state)
        {all_actions ++ actions, state}
      end)

    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:add_endpoint, endpoint, opts}, _ctx, state) do
    peer_id = opts[:peer_id]
    endpoint_id = opts[:endpoint_id] || opts[:peer_id]

    endpoint =
      case endpoint do
        %Endpoint.WebRTC{} ->
          %Endpoint.WebRTC{
            endpoint
            | telemetry_label: state.telemetry_label ++ [peer_id: peer_id],
              parent_span: Membrane.OpenTelemetry.get_span(@life_span_id),
              trace_context: state.trace_context
          }

        another_endpoint ->
          another_endpoint
      end

    cond do
      Map.has_key?(state.endpoints, endpoint_id) ->
        Membrane.Logger.warn(
          "Cannot add Endpoint with id #{inspect(endpoint_id)} as it already exists"
        )

        {:ok, state}

      peer_id != nil and !Map.has_key?(state.peers, peer_id) ->
        Membrane.Logger.warn(
          "Cannot attach Endpoint to peer with id #{peer_id} as such peer does not exist"
        )

        {:ok, state}

      true ->
        {actions, state} = handle_add_endpoint(endpoint, opts, state)
        {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_other({:remove_endpoint, id}, ctx, state) do
    case handle_remove_endpoint(id, ctx, state) do
      {:absent, [], state} ->
        Membrane.Logger.info("Endpoint #{inspect(id)} already removed")
        {:ok, state}

      {:present, actions, state} ->
        {{:ok, actions}, state}
    end
  end

  @impl true
  def handle_other({:add_peer, peer}, _ctx, state) do
    {actions, state} = handle_add_peer(peer, state)
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:remove_peer, id, reason}, ctx, state) do
    {actions, state} = handle_remove_peer(id, reason, ctx, state)
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({:register, pid}, _ctx, state) do
    Registry.register(get_registry_name(), self(), pid)
    {:ok, state}
  end

  @impl true
  def handle_other({:unregister, pid}, _ctx, state) do
    Registry.unregister_match(get_registry_name(), self(), pid)
    {:ok, state}
  end

  @impl true
  def handle_other({:media_event, from, data}, ctx, state) do
    case MediaEvent.decode(data) do
      {:ok, event} ->
        if event.type == :join or Map.has_key?(state.peers, from) do
          {actions, state} = handle_media_event(event.type, event[:data], from, ctx, state)
          {{:ok, actions}, state}
        else
          Membrane.Logger.warn("Received media event from unknown peer id: #{inspect(from)}")
          {:ok, state}
        end

      {:error, :invalid_media_event} ->
        Membrane.Logger.warn("Invalid media event #{inspect(data)}")
        {:ok, state}
    end
  end

  def handle_other(
        {:subscribe, {endpoint_pid, ref}, endpoint_id, track_id, format, opts},
        ctx,
        state
      ) do
    subscription = %Subscription{
      endpoint_id: endpoint_id,
      track_id: track_id,
      format: format,
      opts: opts
    }

    case validate_subscription(subscription, state) do
      :ok ->
        {links, state} = fulfill_or_postpone_subscription(subscription, ctx, state)
        parent_spec = %ParentSpec{links: links, log_metadata: [rtc: state.id]}
        send(endpoint_pid, {ref, :ok})
        {{:ok, [spec: parent_spec]}, state}

      {:error, _reason} = error ->
        send(endpoint_pid, {ref, error})
        {:ok, state}
    end
  end

  @impl true
  def handle_other({:track_priorities, endpoint_to_tracks}, ctx, state) do
    for {{:endpoint, endpoint_id}, tracks} <- endpoint_to_tracks do
      dispatch(endpoint_id, MediaEvent.tracks_priority(tracks))
    end

    tee_actions =
      ctx
      |> filter_children(pattern: {:tee, _tee_name})
      |> Enum.flat_map(&[forward: {&1, :track_priorities_updated}])

    {{:ok, tee_actions}, state}
  end

  @impl true
  def handle_notification(notifcation, {:endpoint, endpoint_id}, ctx, state) do
    if Map.has_key?(state.endpoints, endpoint_id) do
      handle_endpoint_notification(notifcation, endpoint_id, ctx, state)
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_notification(notification, {:tee, track_id}, _ctx, state) do
    handle_tee_notification(notification, track_id, state)
  end

  @impl true
  def handle_crash_group_down(endpoint_id, ctx, state) do
    if Map.has_key?(state.peers, endpoint_id) do
      dispatch(endpoint_id, MediaEvent.peer_removed(endpoint_id, "Internal server error."))
    end

    dispatch(%Message.EndpointCrashed{endpoint_id: endpoint_id})
    {_status, actions, state} = handle_remove_endpoint(endpoint_id, ctx, state)
    {{:ok, actions}, state}
  end

  #
  # Media Events
  #
  # - handle_media_event/5: Handles all types of media events including join, custom, leave,
  #   update_peer_metadata, update_track_metadata, select_encoding
  #

  defp handle_media_event(:join, data, peer_id, _ctx, state) do
    peer = Peer.new(peer_id, data.metadata || %{})
    dispatch(%Message.NewPeer{rtc_engine: self(), peer: peer})

    receive do
      {:accept_new_peer, ^peer_id} ->
        handle_add_peer(peer, state)

      {:accept_new_peer, peer_id} ->
        Membrane.Logger.warn("Unknown peer id passed for acceptance: #{inspect(peer_id)}")
        {[], state}

      {:deny_new_peer, peer_id} ->
        dispatch(peer_id, MediaEvent.peer_denied())
        {[], state}

      {:deny_new_peer, peer_id, data: data} ->
        dispatch(peer_id, MediaEvent.peer_denied(data))
        {[], state}
    end
  end

  defp handle_media_event(:custom, event, peer_id, ctx, state) do
    actions = forward({:endpoint, peer_id}, {:custom_media_event, event}, ctx)
    {actions, state}
  end

  defp handle_media_event(:leave, _event, peer_id, ctx, state) do
    dispatch(%Message.PeerLeft{rtc_engine: self(), peer: state.peers[peer_id]})
    handle_remove_peer(peer_id, nil, ctx, state)
  end

  defp handle_media_event(:update_peer_metadata, %{metadata: metadata}, peer_id, _ctx, state) do
    peer = Map.get(state.peers, peer_id)

    if peer.metadata != metadata do
      updated_peer = %{peer | metadata: metadata}
      state = put_in(state, [:peers, peer_id], updated_peer)
      broadcast(MediaEvent.peer_updated(updated_peer))
      {[], state}
    else
      {[], state}
    end
  end

  defp handle_media_event(
         :update_track_metadata,
         %{track_id: track_id, track_metadata: track_metadata},
         endpoint_id,
         _ctx,
         state
       ) do
    if Map.has_key?(state.endpoints, endpoint_id) do
      endpoint = Map.get(state.endpoints, endpoint_id)
      track = Endpoint.get_track_by_id(endpoint, track_id)

      if track != nil and track.metadata != track_metadata do
        endpoint = Endpoint.update_track_metadata(endpoint, track_id, track_metadata)
        state = put_in(state, [:endpoints, endpoint_id], endpoint)
        broadcast(MediaEvent.track_updated(endpoint_id, track_id, track_metadata))
        {[], state}
      else
        {[], state}
      end
    else
      {[], state}
    end
  end

  defp handle_media_event(
         :select_encoding,
         %{peer_id: peer_id, track_id: track_id, encoding: encoding},
         requester,
         _ctx,
         state
       ) do
    endpoint = Map.fetch!(state.endpoints, peer_id)
    subscription = get_in(state, [:subscriptions, requester, track_id])
    video_track = Endpoint.get_track_by_id(endpoint, track_id)

    cond do
      subscription == nil ->
        Membrane.Logger.warn("""
        Endpoint #{inspect(requester)} requested encoding #{inspect(encoding)} for
        track #{inspect(track_id)} belonging to peer #{inspect(peer_id)} but
        given endpoint is not subscribed for this track. Ignoring.
        """)

        {[], state}

      video_track == nil ->
        Membrane.Logger.warn("""
        Endpoint #{inspect(requester)} requested encoding #{inspect(encoding)} for
        track #{inspect(track_id)} belonging to peer #{inspect(peer_id)} but
        given peer does not have this track.
        Peer tracks: #{inspect(Endpoint.get_tracks(endpoint) |> Enum.map(& &1.id))}
        Ignoring.
        """)

        {[], state}

      encoding not in video_track.simulcast_encodings ->
        Membrane.Logger.warn("""
        Endpoint #{inspect(requester)} requested encoding #{inspect(encoding)} for
        track #{inspect(track_id)} belonging to peer #{inspect(peer_id)} but
        given track does not have this encoding.
        Track encodings: #{inspect(video_track.simulcast_encodings)}
        Ignoring.
        """)

        {[], state}

      true ->
        tee = {:tee, track_id}
        actions = [forward: {tee, {:select_encoding, {requester, encoding}}}]
        {actions, state}
    end
  end

  #
  # Endpoint Notifications
  #
  # - handle_endpoint_notification/4: Handles incoming notifications from an Endpoint, usually
  #   the WebRTC endpoint. Handles track_ready, publication of new tracks, and publication of
  #   removed tracks. Also forwards custom media events.
  #
  # - handle_tee_notification/3: Handles incoming notifications from the tee, mainly this is
  #   used by the Simulcast tee to signal change of encoding.
  #

  defp handle_endpoint_notification(
         {:track_ready, track_id, rid, encoding, depayloading_filter},
         endpoint_id,
         ctx,
         state
       ) do
    # NOTE: When `payload_and_depayload_tracks?` options is set to false we may still want to
    # depayload some streams just in one place to e.g. dump them to HLS or perform any actions on
    # depayloaded media without adding payload/depayload elements to all EndpointBins (performing
    # unnecessary work).
    #
    # To do that one just need to apply `depayloading_filter` after the tee element on which
    # filter's the notification arrived.

    Membrane.Logger.info(
      "New incoming #{encoding} track #{track_id} from endpoint #{inspect(endpoint_id)}"
    )

    track = get_in(state, [:endpoints, endpoint_id]) |> Endpoint.get_track_by_id(track_id)

    {base_tee_name, state} =
      if track.format == [:raw] do
        {{:raw_format_tee, track_id}, state}
      else
        state = put_in(state, [:filters, track_id], depayloading_filter)
        {{:tee, track_id}, state}
      end

    track_link = build_track_link(base_tee_name, rid, track, endpoint_id, ctx, state)

    # check if there are subscriptions for this track and fulfill them
    {subscriptions, pending_subscriptions} =
      Enum.split_with(state.pending_subscriptions, &(&1.track_id == track_id))

    {subscription_links, state} = fulfill_subscriptions(subscriptions, ctx, state)

    links = [track_link] ++ subscription_links
    state = %{state | pending_subscriptions: pending_subscriptions}

    state =
      update_in(
        state,
        [:endpoints, endpoint_id],
        &Endpoint.update_track_encoding(&1, track_id, encoding)
      )

    spec = %ParentSpec{
      links: links,
      crash_group: {endpoint_id, :temporary},
      log_metadata: [rtc_engine_id: state.id]
    }

    {{:ok, spec: spec}, state}
  end

  defp handle_endpoint_notification(
         {:publish, {:new_tracks, tracks}},
         endpoint_id,
         _ctx,
         state
       ) do
    id_to_track = Map.new(tracks, &{&1.id, &1})

    state =
      update_in(
        state,
        [:endpoints, endpoint_id, :inbound_tracks],
        &Map.merge(&1, id_to_track)
      )

    tracks_msgs = build_track_added_actions(tracks, endpoint_id, state)
    endpoint = get_in(state, [:endpoints, endpoint_id])
    track_id_to_track_metadata = Endpoint.get_active_track_metadata(endpoint)
    broadcast(MediaEvent.tracks_added(endpoint_id, track_id_to_track_metadata))
    {{:ok, tracks_msgs}, state}
  end

  defp handle_endpoint_notification(
         {:publish, {:removed_tracks, tracks}},
         endpoint_id,
         ctx,
         state
       ) do
    id_to_track = Map.new(tracks, &{&1.id, &1})

    state =
      update_in(
        state,
        [:endpoints, endpoint_id, :inbound_tracks],
        &Map.merge(&1, id_to_track)
      )

    tracks_msgs = build_track_removed_actions(tracks, endpoint_id, state)
    track_ids = Enum.map(tracks, & &1.id)
    broadcast(MediaEvent.tracks_removed(endpoint_id, track_ids))
    tracks_children = Enum.flat_map(tracks, &get_track_elements(&1.id, ctx))
    {{:ok, tracks_msgs ++ [remove_child: tracks_children]}, state}
  end

  defp handle_endpoint_notification({:custom_media_event, data}, peer_id, _ctx, state) do
    dispatch(peer_id, MediaEvent.custom(data))
    {:ok, state}
  end

  defp handle_tee_notification({:encoding_switched, endpoint_id, encoding}, track_id, state) do
    # send event that endpoint with id `from_endpoint_id` is sending encoding `encoding` for track
    # `track_id` now

    {from_endpoint_id, _endpoint} =
      Enum.find(state.endpoints, fn {_, endpoint} ->
        Endpoint.get_track_by_id(endpoint, track_id) != nil
      end)

    dispatch(endpoint_id, MediaEvent.encoding_switched(from_endpoint_id, track_id, encoding))
    {:ok, state}
  end

  #
  # Peer Management
  #
  # - handle_add_peer/2: Adds a new Peer, part of the Public API and also called when the “join”
  #   media event is received.
  #
  # - handle_remove_peer/4: Removes a Peer, part of the Public API and also called when the
  #   “leave” media event is received.
  #

  defp handle_add_peer(peer, state) do
    if Map.has_key?(state.peers, peer.id) do
      Membrane.Logger.warn("Peer with id: #{inspect(peer.id)} has already been added")
      {[], state}
    else
      Membrane.OpenTelemetry.add_event(@life_span_id, :peer_joined,
        peer_id: peer.id,
        peer_metadata: inspect(peer.metadata)
      )

      dispatch(peer.id, MediaEvent.peer_accepted(peer.id, state.peers, state.endpoints))
      broadcast(MediaEvent.peer_joined(peer))
      state = put_in(state, [:peers, peer.id], peer)
      {[], state}
    end
  end

  defp handle_remove_peer(peer_id, reason, ctx, state) do
    case do_remove_peer(peer_id, reason, ctx, state) do
      {:absent, [], state} ->
        Membrane.Logger.info("Peer #{inspect(peer_id)} already removed")
        {[], state}

      {:present, actions, state} ->
        Membrane.OpenTelemetry.add_event(@life_span_id, :peer_left,
          peer_id: peer_id,
          reason: inspect(reason)
        )

        broadcast(MediaEvent.peer_left(peer_id))
        send_if_not_nil(state.display_manager, {:unregister_endpoint, {:endpoint, peer_id}})
        {actions, state}
    end
  end

  defp do_remove_peer(peer_id, reason, ctx, state) do
    if Map.has_key?(state.peers, peer_id) do
      unless reason == nil do
        dispatch(peer_id, MediaEvent.peer_removed(peer_id, reason))
      end

      {_peer, state} = pop_in(state, [:peers, peer_id])
      {_status, actions, state} = handle_remove_endpoint(peer_id, ctx, state)
      {:present, actions, state}
    else
      {:absent, [], state}
    end
  end

  #
  # Endpoint Management
  #
  # - handle_add_endpoint/3: Adds a new Endpoint based on the entry provided. Part of the
  #   implementation for the public API.
  #
  # - handle_remove_endpoint/3: Removes the given Endpoint. Part of the implementation for the
  #   public API. Also called when the peer leaves.
  #
  # - get_active_tracks/1: Helper function for add_endpoint/3. Returns a list of Tracks that can
  #   be provided to the newly added Endpoint straight away.
  #
  # - find_children_for_endpoint/2: Convenience function to identify all Elements owned by an
  #   Endpoint, via its Tracks.
  #
  # - get_track_elements/2: Convenience function to identify all Elements owned by a Track
  #   such as the tee, raw_format_filter and raw_format_tee.
  #

  defp handle_add_endpoint(endpoint_entry, opts, state) do
    endpoint_id = opts[:endpoint_id] || opts[:peer_id] || UUID.uuid4()
    endpoint_name = {:endpoint, endpoint_id}

    spec = %ParentSpec{
      node: opts[:node],
      children: %{endpoint_name => endpoint_entry},
      crash_group: {endpoint_id, :temporary},
      log_metadata: [rtc_engine_id: state.id]
    }

    display_manager_message =
      if state.display_manager != nil,
        do: {endpoint_name, {:display_manager, state.display_manager}},
        else: nil

    actions =
      [
        spec: spec,
        forward: display_manager_message,
        forward: {endpoint_name, {:new_tracks, get_active_tracks(state.endpoints)}}
      ]
      |> Keyword.filter(fn
        {:forward, nil} -> false
        _other -> true
      end)

    state = put_in(state, [:subscriptions, endpoint_id], %{})
    state = put_in(state, [:endpoints, endpoint_id], Endpoint.new(endpoint_id, []))
    {actions, state}
  end

  defp handle_remove_endpoint(endpoint_id, ctx, state) do
    if Map.has_key?(state.endpoints, endpoint_id) do
      pending_subscriptions_fun = fn subscriptions ->
        Enum.filter(subscriptions, &(&1.endpoint_id != endpoint_id))
      end

      {endpoint, state} = pop_in(state, [:endpoints, endpoint_id])
      {_, state} = pop_in(state, [:subscriptions, endpoint_id])
      state = update_in(state, [:pending_subscriptions], pending_subscriptions_fun)

      tracks = Enum.map(Endpoint.get_tracks(endpoint), &%Track{&1 | active?: true})
      tracks_msgs = build_track_removed_actions(tracks, endpoint_id, state)
      endpoint_bin = ctx.children[{:endpoint, endpoint_id}]

      if endpoint_bin == nil or endpoint_bin.terminating? do
        {:present, tracks_msgs, state}
      else
        actions = [remove_child: find_children_for_endpoint(endpoint, ctx)]
        {:present, tracks_msgs ++ actions, state}
      end
    else
      {:absent, [], state}
    end
  end

  defp get_active_tracks(endpoints) do
    endpoints
    |> Map.values()
    |> Enum.flat_map(&Endpoint.get_tracks/1)
    |> Enum.filter(& &1.active?)
  end

  defp find_children_for_endpoint(endpoint, ctx) do
    children =
      endpoint
      |> Endpoint.get_tracks()
      |> Enum.flat_map(fn track -> get_track_elements(track.id, ctx) end)

    [endpoint: endpoint.id] ++ children
  end

  defp get_track_elements(track_id, ctx) do
    [
      tee: track_id,
      raw_format_filter: track_id,
      raw_format_tee: track_id
    ]
    |> Enum.filter(&Map.has_key?(ctx.children, &1))
  end

  #
  # Track Actions
  #
  # - build_track_added_actions/3: Called when new tracks were published by the WebRTC endpoint
  #   and the Engine has been notified. Notifies all other Endpoints of the new tracks.
  #
  # - build_track_removed_actions/3: Called when the underlying endpoint was removed (either
  #   normally, or due to crash).
  #

  defp build_track_added_actions(tracks, endpoint_id, state) do
    Enum.flat_map(state.endpoints, fn
      {^endpoint_id, _endpoint} -> []
      {_, nil} -> []
      {endpoint_id, _} -> [forward: {{:endpoint, endpoint_id}, {:new_tracks, tracks}}]
    end)
  end

  defp build_track_removed_actions(tracks, from_endpoint_id, state) do
    state.endpoints
    |> Stream.reject(&(elem(&1, 0) == from_endpoint_id))
    |> Stream.reject(&is_nil(elem(&1, 1)))
    |> Enum.flat_map(fn {endpoint_id, _endpoint} ->
      subscriptions = state.subscriptions[endpoint_id]
      tracks = Enum.filter(tracks, &Map.has_key?(subscriptions, &1.id))
      [forward: {{:endpoint, endpoint_id}, {:remove_tracks, tracks}}]
    end)
  end

  #
  # Track Links
  #
  # - build_track_link/6 - called when the track is ready, via notification from the WebRTC
  #   endpoint. Create the link from the endpoint which published the track, and starts the
  #   underlying tee which is required to bring the content of the track to all subscribers.
  #
  # - build_track_tee/5 - Called by build_track_link/5; builds the correct tee depending on the
  #   type of the track (simulcast / filtered / normal).
  #
  # - build_track_tee_simulcast/1 - Convenience function, builds a Simulcast tee
  #
  # - build_track_tee_filter/4 - Convenience function, builds a Filter tee
  #
  # - build_track_tee_push_output/2 - Convenience function, builds a Push Output tee
  #

  defp build_track_link(base_tee_name, rid, track, endpoint_id, ctx, state) do
    is_simulcast? = rid != nil
    telemetry_label = [peer_id: endpoint_id, track_id: "#{track.id}:#{rid}"]
    telemetry_label = Keyword.merge(state.telemetry_label, telemetry_label)

    link({:endpoint, endpoint_id})
    |> via_out(Pad.ref(:output, {track.id, rid}))
    |> then(fn link ->
      if is_simulcast? do
        options = [telemetry_label: telemetry_label]
        via_in(link, Pad.ref(:input, {track.id, rid}), options: options)
      else
        link
      end
    end)
    |> then(fn link ->
      if Map.has_key?(ctx.children, base_tee_name) do
        to(link, base_tee_name)
      else
        to(link, base_tee_name, build_track_tee(track.id, rid, track, telemetry_label, state))
      end
    end)
  end

  defp build_track_tee(track_id, rid, track, telemetry_label, state) do
    is_simulcast? = rid != nil
    is_filter? = state.display_manager != nil

    cond do
      is_simulcast? -> build_track_tee_simulcast(track)
      is_filter? -> build_track_tee_filter(state.id, track_id, track, telemetry_label)
      true -> build_track_tee_push_output(track, telemetry_label)
    end
  end

  defp build_track_tee_simulcast(track) do
    %SimulcastTee{
      track: track
    }
  end

  defp build_track_tee_filter(ets_name, track_id, track, telemetry_label) do
    %FilterTee{
      ets_name: ets_name,
      track_id: track_id,
      type: track.type,
      codec: track.encoding,
      telemetry_label: telemetry_label
    }
  end

  defp build_track_tee_push_output(track, telemetry_label) do
    %PushOutputTee{
      codec: track.encoding,
      telemetry_label: telemetry_label
    }
  end

  #
  # Track Subscriptions
  #
  # - validate_subscription/2: Validates proposed subscription, called when a new subscription
  #   is to be added, via handle_other.
  #
  # - fulfill_or_postpone_subscription/3: Called immediately upon validation of subscription,
  #   optimistically links subscriber to the track's tee if the track is ready, otherwise adds the
  #   subscription to the list of pending subscriptions
  #
  # - fulfill_subscriptions/3: Called when a new track is ready and there are pending
  #   subscriptions to the track. Within subscription fulfillment, the raw format
  #   filter/tee is built and linked, if the subscription is raw. Additional links from either the
  #   normal tee or the raw tee to the subscribing endpoint are also built.
  #
  # - build_raw_format_links/3, build_raw_format_link/2: Called by fulfill_subscriptions/3, these
  #   functions would build, for each track, links through the root tee, via the depayloader,
  #   to a PushOutputTee, which exposes outpad pads for each subscription to pull from
  #
  # - build_subscription_links/2, build_subscription_link/2: Called by fulfill_subscriptions/3,
  #   these functions build the actual links between 1) either the root tee or the raw tee, and
  #   2) the endpoint subscribing to the given track.
  #
  # - get_track/2: Convenience function. Searches for a Track with the given Track ID which is
  #   owned by one of the Endpoints in the list.
  #

  defp validate_subscription(subscription, state) do
    # checks whether subscription is correct
    track = get_track(subscription.track_id, state.endpoints)
    default_simulcast_encoding = subscription.opts[:default_simulcast_encoding]

    cond do
      track == nil ->
        {:error, :invalid_track_id}

      subscription.format not in track.format ->
        {:error, :invalid_format}

      # check if subscribed for existing simulcast encoding if simulcast is used
      track.simulcast_encodings != [] and default_simulcast_encoding != nil and
          default_simulcast_encoding not in track.simulcast_encodings ->
        {:error, :invalid_default_simulcast_encoding}

      true ->
        :ok
    end
  end

  defp fulfill_or_postpone_subscription(subscription, ctx, state) do
    # If the tee for this track is already spawned, fulfill subscription.
    # Otherwise, save subscription as pending, we will fulfill it when the tee is linked.

    if Map.has_key?(ctx.children, {:tee, subscription.track_id}) do
      fulfill_subscriptions([subscription], ctx, state)
    else
      state = update_in(state, [:pending_subscriptions], &[subscription | &1])
      {[], state}
    end
  end

  defp fulfill_subscriptions(subscriptions, ctx, state) do
    # Attempt to fulfill multiple subscriptions. This is done so in simultaneous subscriptions
    # to the raw format can be fulfilled by linking just one pair of raw format filter/tee.
    #
    # After all links were built, the subscriptions are added to the state.

    raw_format_links = build_raw_format_links(subscriptions, ctx, state)
    subscription_links = build_subscription_links(subscriptions, state)
    links = raw_format_links ++ subscription_links

    Enum.reduce(subscriptions, {links, state}, fn subscription, {links, state} ->
      endpoint_id = subscription.endpoint_id
      track_id = subscription.track_id
      subscription = %{subscription | status: :active}
      state = put_in(state, [:subscriptions, endpoint_id, track_id], subscription)
      {links, state}
    end)
  end

  defp build_raw_format_links(subscriptions, ctx, state) do
    subscriptions
    |> Stream.filter(&(&1.format == :raw))
    |> Stream.map(& &1.track_id)
    |> Stream.uniq()
    |> Stream.reject(&Map.has_key?(ctx.children, {:raw_format_tee, &1}))
    |> Enum.map(&build_raw_format_link(&1, state))
  end

  defp build_raw_format_link(track_id, state) do
    # Build raw format filter and tee for the given track.
    # Raw format filter and tee are connected to the output of the
    # track's base tee.

    track = get_track(track_id, state.endpoints)

    link({:tee, track_id})
    |> via_out(Pad.ref(:output, {:endpoint, :raw_format_filter}))
    |> to({:raw_format_filter, track_id}, get_in(state, [:filters, track_id]))
    |> to({:raw_format_tee, track_id}, %PushOutputTee{codec: track.encoding})
  end

  defp build_subscription_links(subscriptions, state) do
    Enum.map(subscriptions, &build_subscription_link(&1, state))
  end

  defp build_subscription_link(subscription, state) do
    track = get_track(subscription.track_id, state.endpoints)

    if subscription.format == :raw do
      link({:raw_format_tee, subscription.track_id})
    else
      link({:tee, subscription.track_id})
    end
    |> then(fn link ->
      if track.type == :video and track.simulcast_encodings != [] do
        options = Keyword.take(subscription.opts, [:default_simulcast_encoding])
        via_out(link, Pad.ref(:output, {:endpoint, subscription.endpoint_id}), options: options)
      else
        via_out(link, Pad.ref(:output, {:endpoint, subscription.endpoint_id}))
      end
    end)
    |> via_in(Pad.ref(:input, subscription.track_id))
    |> to({:endpoint, subscription.endpoint_id})
  end

  defp get_track(track_id, endpoints) do
    endpoints
    |> Map.values()
    |> Enum.flat_map(&Endpoint.get_tracks/1)
    |> Map.new(&{&1.id, &1})
    |> Map.get(track_id)
  end

  #
  # Message Dispatch
  #
  # - dispatch/1: Internal function, dispatches the message to all registered processes within the
  #   registry
  #
  # - dispatch/2: Dispatches the Media Event to all registered processes within the registry, with
  #   the correct `to` field populated
  #
  # - brodcast/1: Convenience function, dispatches the data within a Media Event and sets the `to`
  #   field to `:broadcast`.
  #

  defp dispatch(message) do
    Registry.dispatch(get_registry_name(), self(), fn entries ->
      for {_, pid} <- entries, do: send(pid, message)
    end)
  end

  defp dispatch(to, data) when is_binary(data) do
    dispatch(%Message.MediaEvent{rtc_engine: self(), to: to, data: data})
  end

  defp dispatch(to, data) when is_map(data) do
    dispatch(to, MediaEvent.encode(data))
  end

  defp broadcast(data) when is_map(data) do
    dispatch(:broadcast, data)
  end
end
