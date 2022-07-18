defmodule Membrane.RTC.Engine.Metrics.Repo.Migrations.CreatePeerToRoom do
  use Ecto.Migration

  def change do
    create table(:peer_to_room, primary_key: false) do
      add(:time, :naive_datetime_usec, null: false)
      add(:peer_id, :string, null: false)
      add(:room_id, :string, null: false)
    end

    create unique_index(:peer_to_room, [:room_id, :peer_id], name: :peer_to_room_room_id_peer_id_index)
    create index(:peer_to_room, [:room_id])
  end
end
