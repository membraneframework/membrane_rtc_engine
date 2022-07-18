defmodule Membrane.RTC.Engine.Metrics.Repo.Migrations.CreatePeersMetrics do
  use Ecto.Migration

  @chunk_time_interval Application.get_env(:membrane_rtc_engine, Repo)[:chunk_time_interval] || "10 minutes"
  # @chunk_compress_policy_interval Application.get_env(:membrane_rtc_engine,Repo)[:chunk_compress_policy_interval] || "10 minutes"

  def change do
    create table(:peers_metrics, primary_key: false) do
      add(:time, :naive_datetime_usec, null: false)
      add(:peer_id, :string, null: false)
      add(:"peer.metadata", :string)
      add(:"ice.binding_requests_received", :integer)
      add(:"ice.binding_responses_sent", :integer)
      add(:"ice.bytes_received", :integer)
      add(:"ice.bytes_sent", :integer)
      add(:"ice.packets_received", :integer)
      add(:"ice.packets_sent", :integer)
    end

    execute("SELECT create_hypertable('peers_metrics', 'time', chunk_time_interval => INTERVAL '#{@chunk_time_interval}')")

    create index(:peers_metrics, [:time])
    create index(:peers_metrics, [:peer_id])
    create index(:peers_metrics, [:time, :peer_id])

    # execute("SELECT add_compression_policy('measurements', INTERVAL '#{@chunk_compress_policy_interval}')")
    # todo: searcxh, what is compression in timescale
  end
end
