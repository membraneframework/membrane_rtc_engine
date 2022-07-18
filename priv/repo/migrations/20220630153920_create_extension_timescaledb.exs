defmodule Membrane.RTC.Engine.Metrics.Repo.Migrations.CreateExtensionTimescaledb do
  use Ecto.Migration

  alias Membrane.Telemetry.TimescaleDB.Repo

  @chunk_time_interval Application.get_env(:membrane_rtc_engine, Repo)[:chunk_time_interval] || "10 minutes"
  @chunk_compress_policy_interval Application.get_env(:membrane_rtc_engine,Repo)[:chunk_compress_policy_interval] || "10 minutes"

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS timescaledb CASCADE")
  end
end
