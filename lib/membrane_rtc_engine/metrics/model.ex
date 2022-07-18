defmodule Membrane.RTC.Engine.Metrics.Model do
  import Ecto.Query

  alias Membrane.RTC.Engine.Metrics.Repo

  alias Membrane.RTC.Engine.Metrics.Model.{
    PeerMetrics,
    TrackMetrics,
    PeerToRoom,
    TrackToPeer
  }

  @spec insert_report(Metrics.rtc_engine_report()) :: :ok
  def insert_report(report) do
    for {{:room_id, room_id}, room_report} <- report do
      for {{:peer_id, peer_id}, peer_report} <- room_report do
        {peer_metrics, tracks_reports} =
          Enum.split_with(peer_report, fn {key, _value} -> is_atom(key) end)

        %{peer_id: peer_id, room_id: room_id, time: NaiveDateTime.utc_now()}
        |> upsert_peer_to_room()

        Map.new([peer_id: peer_id, time: NaiveDateTime.utc_now()] ++ peer_metrics)
        |> update_if_exists(:"peer.metadata", &inspect/1)
        |> insert_peer_metrics()

        for {{:track_id, track_id}, track_report} <- tracks_reports do
          %{track_id: track_id, peer_id: peer_id, time: NaiveDateTime.utc_now()}
          |> upsert_track_to_peer()

          Map.merge(track_report, %{track_id: track_id, time: NaiveDateTime.utc_now()})
          |> update_if_exists(:"track.metadata", &inspect/1)
          |> update_if_exists(:"inbound-rtp.ssrc", &inspect/1)
          |> update_if_exists(:"inbound-rtp.encoding", &Atom.to_string/1)
          |> insert_track_metrics()
        end
      end
    end

    :ok
  end

  defp update_if_exists(map, key, fun) do
    case map do
      %{^key => value} -> Map.put(map, key, fun.(value))
      _else -> map
    end
  end

  defp insert_peer_metrics(peer_metrics) do
    %PeerMetrics{}
    |> PeerMetrics.changeset(peer_metrics)
    |> Repo.insert()
  end

  defp insert_track_metrics(track_metrics) do
    %TrackMetrics{}
    |> TrackMetrics.changeset(track_metrics)
    |> Repo.insert()
  end

  defp upsert_peer_to_room(peer_to_room) do
    %PeerToRoom{}
    |> PeerToRoom.changeset(peer_to_room)
    |> Repo.insert()
  end

  defp upsert_track_to_peer(track_to_peer) do
    %TrackToPeer{}
    |> TrackToPeer.changeset(track_to_peer)
    |> Repo.insert()
  end

  def remove_outdated_records(days \\ 7) do
    for model <- [PeerMetrics, TrackMetrics, PeerToRoom, TrackToPeer] do
      from(p in model, where: p.time < ago(^days, "day"))
      |> Repo.delete_all()
    end
  end
end
