defmodule Membrane.KeyframeRequester do
  @moduledoc """
  A simple filter sending `Membrane.KeyframeRequestEvent` on the `:input` pad
  repeatadly in intervals.
  """
  use Membrane.Filter

  def_input_pad :input, caps: :any, demand_mode: :auto, demand_unit: :buffers

  def_output_pad :output, caps: :any, demand_mode: :auto

  def_options interval: [
                spec: Membrane.Time.t(),
                description: "Time interval between requests"
              ]

  @kf_request_action {:event, {:input, %Membrane.KeyframeRequestEvent{}}}

  @impl true
  def handle_init(opts) do
    {:ok, Map.from_struct(opts)}
  end

  @impl true
  def handle_process_list(:input, buffers, _ctx, state) do
    {{:ok, buffer: {:output, buffers}}, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, [@kf_request_action, {:start_timer, {:send_event, state.interval}}]}, state}
  end

  @impl true
  def handle_tick(:send_event, _ctx, state) do
    {{:ok, [@kf_request_action]}, state}
  end
end
