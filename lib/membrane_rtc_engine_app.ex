defmodule Membrane.RTC.Engine.App do
  @moduledoc false
  use Application
  alias Membrane.RTC.Engine

  @impl true
  def start(_start_type, _start_args) do
    children = [
      {Registry, keys: :duplicate, name: Engine.get_registry_name()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
