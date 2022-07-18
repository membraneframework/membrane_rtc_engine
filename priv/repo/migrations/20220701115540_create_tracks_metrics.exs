defmodule Membrane.RTC.Engine.Metrics.Repo.Migrations.CreateTracksMetrics do
  use Ecto.Migration

  @chunk_time_interval Application.get_env(:membrane_rtc_engine, Repo)[:chunk_time_interval] || "10 minutes"

  def change do
    create table(:tracks_metrics, primary_key: false) do
      add(:time, :naive_datetime_usec, null: false)
      add(:track_id, :string, null: false)
      add(:"track.metadata", :string)
      add(:"inbound-rtp.encoding", :string)
      add(:"inbound-rtp.ssrc", :string)
      add(:"inbound-rtp.bytes_received", :integer)
      add(:"inbound-rtp.keyframe_request_sent", :integer)
      add(:"inbound-rtp.packets", :integer)
      add(:"inbound-rtp.frames", :integer)
      add(:"inbound-rtp.keyframes", :integer)
    end

    execute("SELECT create_hypertable('tracks_metrics', 'time', chunk_time_interval => INTERVAL '#{@chunk_time_interval}')")

    create index(:tracks_metrics, [:time])
    create index(:tracks_metrics, [:track_id])
    create index(:tracks_metrics, [:time, :track_id])
  end
end
