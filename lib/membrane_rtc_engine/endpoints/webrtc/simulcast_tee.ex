defmodule Membrane.RTC.Engine.Endpoint.WebRTC.SimulcastTee do
  @moduledoc false
  use Membrane.Filter

  require Membrane.Logger
  require Membrane.TelemetryMetrics

  alias Membrane.RTC.Engine.Endpoint.WebRTC.EncodingTracker
  alias Membrane.RTC.Engine.Endpoint.WebRTC.Forwarder
  alias Membrane.RTC.Utils

  @supported_codecs [:H264, :VP8]

  def_options track: [
                type: :struct,
                spec: Membrane.RTC.Engine.Track.t(),
                description: "Track this tee is going to forward to other endpoints"
              ]

  def_input_pad :input,
    availability: :on_request,
    mode: :pull,
    demand_mode: :auto,
    caps: Membrane.RTP,
    options: [
      telemetry_label: [
        spec: Membrane.TelemetryMetrics.label(),
        default: [],
        description: "Label passed to Membrane.TelemetryMetrics functions"
      ]
    ]

  def_output_pad :output,
    availability: :on_request,
    mode: :push,
    caps: Membrane.RTP,
    options: [
      default_simulcast_encoding: [
        spec: String.t() | nil,
        default: nil,
        description: """
        Initial encoding that should be sent via this pad.
        `nil` means that the best possible encoding should be used.
        """
      ]
    ]

  @typedoc """
  Notifies that encoding for endpoint with id `endpoint_id` was switched to encoding `encoding`.
  """
  @type encoding_switched_notification_t() ::
          {:encoding_switched, endpoint_id :: any(), encoding :: String.t()}

  @impl true
  def handle_init(opts) do
    if opts.track.encoding not in @supported_codecs do
      raise("""
      #{inspect(__MODULE__)} does not support codec #{inspect(opts.track.encoding)}.
      Supported codecs: #{inspect(@supported_codecs)}
      """)
    end

    trackers = Map.new(opts.track.simulcast_encodings, &{&1, EncodingTracker.new(&1)})

    {:ok,
     %{
       track: opts.track,
       forwarders: %{},
       trackers: trackers,
       inactive_encodings: []
     }}
  end

  @impl true
  def handle_pad_added(Pad.ref(:input, {_track_id, _rid}) = pad, ctx, state) do
    Utils.telemetry_register(ctx.pads[pad].options.telemetry_label)

    {:ok, state}
  end

  @impl true
  def handle_pad_added(
        Pad.ref(:output, {:endpoint, endpoint_id}) = pad,
        %{playback_state: playback_state} = context,
        state
      ) do
    forwarder =
      Forwarder.new(
        state.track.encoding,
        state.track.clock_rate,
        state.track.simulcast_encodings,
        context.options[:default_simulcast_encoding]
      )

    forwarder =
      Enum.reduce(state.inactive_encodings, forwarder, fn encoding, forwarder ->
        Forwarder.encoding_inactive(forwarder, encoding)
      end)

    state = put_in(state, [:forwarders, endpoint_id], forwarder)

    actions =
      if playback_state == :playing do
        [caps: {pad, %Membrane.RTP{}}]
      else
        []
      end

    {{:ok, actions}, state}
  end

  @impl true
  def handle_pad_added(pad, _context, _state) do
    raise("Pad #{inspect(pad)} not allowed for #{inspect(__MODULE__)}")
  end

  @impl true
  def handle_pad_removed(Pad.ref(:output, {:endpoint, endpoint_id}), _context, state) do
    {_forwarder, state} = pop_in(state, [:forwarders, endpoint_id])
    {:ok, state}
  end

  @impl true
  def handle_pad_removed(Pad.ref(:input, {_track_id, rid}), _context, state) do
    {_tracker, state} = pop_in(state, [:trackers, rid])
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(context, state) do
    caps =
      Enum.flat_map(context.pads, fn
        {Pad.ref(:output, _ref) = pad, _pad_data} -> [caps: {pad, %Membrane.RTP{}}]
        _other -> []
      end)

    start_timer = [start_timer: {:check_encoding_statuses, 1_000_000_000}]
    {{:ok, start_timer ++ caps}, state}
  end

  @impl true
  def handle_process(Pad.ref(:input, {_track_id, encoding}) = pad, buffer, ctx, state) do
    Utils.emit_packet_arrival_event(
      buffer.payload,
      state.track.encoding,
      ctx.pads[pad].options.telemetry_label
    )

    state = update_in(state, [:trackers, encoding], &EncodingTracker.increment_samples(&1))

    {actions, state} =
      Enum.flat_map_reduce(state.forwarders, state, fn
        {endpoint_id, forwarder}, state ->
          {forwarder, actions} = Forwarder.process(forwarder, buffer, encoding, endpoint_id)
          state = put_in(state, [:forwarders, endpoint_id], forwarder)
          {actions, state}
      end)

    {{:ok, actions}, state}
  end

  @impl true
  def handle_tick(:check_encoding_statuses, _ctx, state) do
    state =
      Enum.reduce(state.trackers, state, fn {rid, tracker}, state ->
        check_encoding_status(rid, tracker, state)
      end)

    {:ok, state}
  end

  defp check_encoding_status(rid, tracker, state) do
    case EncodingTracker.check_encoding_status(tracker) do
      {:ok, tracker} ->
        put_in(state, [:trackers, rid], tracker)

      {:status_changed, tracker, :active} ->
        state =
          Enum.reduce(state.forwarders, state, fn {endpoint_id, forwarder}, state ->
            put_in(state, [:forwarders, endpoint_id], Forwarder.encoding_active(forwarder, rid))
          end)

        state
        |> update_in([:inactive_encodings], &List.delete(&1, rid))
        |> put_in([:trackers, rid], tracker)

      {:status_changed, tracker, :inactive} ->
        state =
          Enum.reduce(state.forwarders, state, fn {endpoint_id, forwarder}, state ->
            put_in(state, [:forwarders, endpoint_id], Forwarder.encoding_inactive(forwarder, rid))
          end)

        state
        |> update_in([:inactive_encodings], &[rid | &1])
        |> put_in([:trackers, rid], tracker)
    end
  end

  @impl true
  def handle_other({:select_encoding, {endpoint_id, encoding}}, _ctx, state) do
    state =
      update_in(state, [:forwarders, endpoint_id], fn forwarder ->
        Forwarder.select_encoding(forwarder, encoding)
      end)

    {:ok, state}
  end

  @impl true
  def handle_end_of_stream(_pad, context, state) do
    all_end_of_streams? =
      context.pads
      |> Enum.filter(fn {_pad_name, pad_data} ->
        pad_data.direction == :input
      end)
      |> Enum.all?(fn {_pad_name, pad_data} ->
        pad_data.end_of_stream?
      end)

    if all_end_of_streams? do
      {{:ok, forward: :end_of_stream}, state}
    else
      {:ok, state}
    end
  end
end
