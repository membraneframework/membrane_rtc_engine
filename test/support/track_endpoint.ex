defmodule Membrane.RTC.Engine.Support.TrackEndpoint do
  @moduledoc false

  # Simple endpoint that publishes track passed in options

  use Membrane.Bin

  alias Membrane.RTC.Engine

  @type encoding_t() :: String.t()

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              track: [
                spec: Engine.Track.t(),
                description: "Track to publish"
              ]

  def_input_pad :input,
    demand_unit: :buffers,
    caps: :any,
    availability: :on_request

  def_output_pad :output,
    demand_unit: :buffers,
    caps: :any,
    availability: :on_request

  @impl true
  def handle_init(opts) do
    state = %{rtc_engine: opts.rtc_engine, track: opts.track}

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, notify: {:publish, {:new_tracks, [state.track]}}}, state}
  end

  @impl true
  def handle_other({:new_tracks, []}, _ctx, state) do
    {:ok, state}
  end
end
