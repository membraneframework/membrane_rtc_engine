defmodule Membrane.RTC.Utils do
  @moduledoc false

  require OpenTelemetry.Tracer, as: Tracer
  require Membrane.TelemetryMetrics

  alias Membrane.RTP.PayloadFormatResolver

  @rtp_packet_arrival_event [Membrane.RTC.Engine, :RTP, :packet, :arrival]

  # This is workaround to make dialyzer happy.
  # In other case we would have to specify all possible CallbackContext types here.
  # Maybe membrane_core should have something like
  # @type Membrane.Pipeline.CallbackContxt.t() ::  CallbackContext.Notification.t()
  #  | CallbackContext.Other.t()
  #  | CallbackContext.PlaybackChange.t()
  #  | etc.
  # to make it easier to reference CallbackContext types.
  @type ctx :: any()

  defmacro find_child(ctx, pattern: pattern) do
    quote do
      unquote(ctx).children |> Map.keys() |> Enum.find(&match?(unquote(pattern), &1))
    end
  end

  defmacro filter_children(ctx, pattern: pattern) do
    quote do
      unquote(ctx).children |> Map.keys() |> Enum.filter(&match?(unquote(pattern), &1))
    end
  end

  @spec reduce_children(ctx :: ctx(), acc :: any(), fun :: fun()) ::
          any()
  def reduce_children(ctx, acc, fun) do
    ctx.children |> Map.keys() |> Enum.reduce(acc, fun)
  end

  @spec flat_map_children(ctx :: ctx(), fun :: fun()) :: [any()]
  def flat_map_children(ctx, fun) do
    ctx.children |> Map.keys() |> Enum.flat_map(fun)
  end

  @spec forward(
          child_name :: any(),
          msg :: any(),
          ctx :: ctx()
        ) :: [Membrane.Pipeline.Action.forward_t()]
  def forward(child_name, msg, ctx) do
    child = find_child(ctx, pattern: ^child_name)

    if child do
      [forward: {child_name, msg}]
    else
      []
    end
  end

  @spec send_if_not_nil(pid :: pid() | nil, msg :: any()) :: any()
  def send_if_not_nil(pid, msg) do
    if pid != nil do
      send(pid, msg)
    end
  end

  @spec create_otel_context(name :: String.t(), metadata :: [{atom(), any()}]) :: any()
  def create_otel_context(name, metadata \\ []) do
    metadata =
      [
        {:"library.language", :erlang},
        {:"library.name", :membrane_rtc_engine},
        {:"library.version", "server:#{Application.spec(:membrane_rtc_engine, :vsn)}"}
      ] ++ metadata

    root_span = Tracer.start_span(name)
    parent_ctx = Tracer.set_current_span(root_span)
    otel_ctx = OpenTelemetry.Ctx.attach(parent_ctx)
    OpenTelemetry.Span.set_attributes(root_span, metadata)
    OpenTelemetry.Span.end_span(root_span)
    OpenTelemetry.Ctx.attach(otel_ctx)

    [otel_ctx]
  end

  @spec generate_turn_credentials(binary(), binary()) :: {binary(), binary()}
  def generate_turn_credentials(name, secret) do
    duration =
      DateTime.utc_now()
      |> DateTime.to_unix()
      |> tap(fn unix_timestamp -> unix_timestamp + 24 * 3600 end)

    username = "#{duration}:#{name}"

    password =
      :crypto.mac(:hmac, :sha, secret, username)
      |> Base.encode64()

    {username, password}
  end

  @spec telemetry_register(Membrane.TelemetryMetrics.label()) :: :ok
  def telemetry_register(telemetry_label) do
    Membrane.TelemetryMetrics.register(@rtp_packet_arrival_event, telemetry_label)
    :ok
  end

  @spec emit_packet_arrival_event(
          binary(),
          :VP8 | :H264 | :OPUS,
          Membrane.TelemetryMetrics.label()
        ) :: :ok
  def emit_packet_arrival_event(payload, codec, telemetry_label) do
    Membrane.TelemetryMetrics.execute(
      @rtp_packet_arrival_event,
      packet_measurements(payload, codec),
      %{},
      telemetry_label
    )

    :ok
  end

  defp packet_measurements(payload, codec) do
    measurements =
      case PayloadFormatResolver.keyframe_detector(codec) do
        {:ok, detector} -> %{keyframe_indicator: detector.(payload) |> bool_to_int()}
        :error -> %{}
      end

    case PayloadFormatResolver.frame_detector(codec) do
      {:ok, detector} ->
        frame_indicator = detector.(payload) |> bool_to_int()
        Map.put(measurements, :frame_indicator, frame_indicator)

      :error ->
        measurements
    end
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
