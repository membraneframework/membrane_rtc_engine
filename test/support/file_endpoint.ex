defmodule Membrane.RTC.Engine.Support.FileEndpoint do
  @moduledoc false

  # Endpoint that publishes data from a file. It will start publishing data when it receives message :start.

  use Membrane.Bin

  alias Membrane.RTC.Engine
  alias Membrane.H264
  require Membrane.Logger

  @type encoding_t() :: String.t()

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              file_path: [
                spec: Path.t(),
                description: "Path to track file"
              ],
              track: [
                spec: Engine.Track.t(),
                description: "Track to publish"
              ]

  def_output_pad :output,
    demand_unit: :buffers,
    caps: {H264, stream_format: :byte_stream},
    availability: :on_request,

  @impl true
  def handle_init(opts) do
    state = %{rtc_engine: opts.rtc_engine, file_path: opts.file_path, track: opts.track}

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, notify: {:publish, {:new_tracks, [state.track]}}}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, _rid}) = pad, _ctx, state) do
    spec = %ParentSpec{
      children: %{
        source: %Membrane.File.Source{
          location: state.file_path
        }
      },
      links: [
        link(:source)
        |> to_bin_output(pad)
      ]
    }

    {{:ok, spec: spec}, state}
  end

  @impl true
  def handle_other({:new_tracks, []}, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_other({:remove_tracks, []}, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_other(:start, _ctx, state) do
    {{:ok, notify: {:track_ready, state.track.id, nil, state.track.encoding, nil}}, state}
  end
end
