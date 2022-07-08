defmodule Membrane.RTC.Engine.Support.FileEndpoint do
  @moduledoc false

  # Endpoint that publish data from file

  use Membrane.Bin

  alias Membrane.RTC.Engine
  require Membrane.Logger

  @type encoding_t() :: String.t()

  def_options rtc_engine: [
                spec: pid(),
                description: "Pid of parent Engine"
              ],
              file_path: [
                spec: Path.t(),
                description: "Path of file"
              ],
              track: [
                spec: Engine.Track.t(),
                description: "Track to publish"
              ]

  def_output_pad :output,
    demand_unit: :buffers,
    caps: :any,
    availability: :on_request

  @impl true
  def handle_init(opts) do
    state = %{rtc_engine: opts.rtc_engine, path: opts.file_path, track: opts.track}

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
        },
        parser: %Membrane.H264.FFmpeg.Parser{
          attach_nalus?: true,
          skip_until_parameters?: false
        }
      },
      links: [
        link(:source)
        |> to(:parser)
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
  def handle_other({:custom_media_event, "start_track"}, _ctx, state) do
    {{:ok, notify: {:track_ready, state.track.id, nil, state.track.encoding, nil}}, state}
  end
end
