defmodule Membrane.RTC.Engine.Metrics.Reporter do
  use GenServer

  alias Membrane.RTC.Engine.Metrics

  @type reporter :: pid() | atom()

  @spec store_report(reporter(), Metrics.rtc_engine_report()) :: :ok
  def store_report(reporter, report) do
    GenServer.cast(reporter, {:store_report, report})
  end

  @impl true
  def init(_arg) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:store_report, report}, state) do
    Metrics.Model.insert_report(report)
    {:noreply, state}
  end
end
