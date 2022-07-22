defmodule Membrane.RTC.Engine.Support.FileEndpoint do
  @moduledoc false

  # Endpoint that publishes data from a file in realtime. It will start publishing data when it receives message :start.
  # Buffers from file must have timestamps, because it will be used in Realtimer.

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
                description: "Path to track file"
              ],
              track: [
                spec: Engine.Track.t(),
                description: "Track to publish"
              ],
              processing_children: [
                spec: %{any() => Membrane.ParentSpec.child_spec_t()},
                description: "Children required for processing input from file."
              ],
              processing_link: [
                spec:
                  (Membrane.ParentSpec.link_builder_t() -> Membrane.ParentSpec.link_builder_t()),
                description: "Function which link source with processing children"
              ]

  def_output_pad :output,
    demand_unit: :buffers,
    caps: :any,
    availability: :on_request

  @impl true
  def handle_init(opts) do
    state = %{
      rtc_engine: opts.rtc_engine,
      file_path: opts.file_path,
      track: opts.track,
      processing_children: opts.processing_children,
      processing_link: opts.processing_link
    }

    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, notify: {:publish, {:new_tracks, [state.track]}}}, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, {track_id, _rid}) = pad, _ctx, state) do
    base_children = %{
      source: %Membrane.File.Source{
        location: state.file_path
      },
      realtimer: Membrane.Realtimer
    }

    spec = %ParentSpec{
      children: Map.merge(base_children, state.processing_children),
      links: [
        link(:source)
        |> then(state.processing_link)
        |> to(:realtimer)
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
