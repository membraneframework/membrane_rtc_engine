defmodule Membrane.RTC.Engine.Metrics.Repo.Migrations.CreateTrackToPeer do
  use Ecto.Migration

  def change do
    create table(:track_to_peer, primary_key: false) do
      add(:time, :naive_datetime_usec, null: false)
      add(:track_id, :string, null: false)
      add(:peer_id, :string, null: false)
    end

    create unique_index(:track_to_peer, [:track_id, :peer_id], name: :track_to_peer_track_id_peer_id_index)
    create index(:track_to_peer, [:peer_id])
  end
end
