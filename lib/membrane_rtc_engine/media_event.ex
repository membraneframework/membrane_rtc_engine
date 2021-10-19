defmodule Membrane.RTC.Engine.MediaEvent do
  @moduledoc false

  @type peer_id_t() :: String.t()
  @type to_t() :: peer_id_t() | :broadcast
  @type sfu_media_event_t() :: {:sfu_media_event, to_t(), binary()}

  @type track_id() :: Membrane.WebRTC.Track.id()

  @spec create_peer_accepted_event(peer_id_t(), map()) :: sfu_media_event_t()
  def create_peer_accepted_event(peer_id, peers) do
    peers =
      Enum.map(peers, fn {id, peer} ->
        %{id: id, metadata: peer.metadata, trackIdToMetadata: peer.track_id_to_track_metadata}
      end)

    %{type: "peerAccepted", data: %{id: peer_id, peersInRoom: peers}}
    |> do_create(peer_id)
  end

  @spec create_peer_denied_event(peer_id_t(), map()) :: sfu_media_event_t()
  def create_peer_denied_event(peer_id, metadata \\ %{}) do
    %{type: "peerDenied", data: metadata}
    |> do_create(peer_id)
  end

  @spec create_peer_joined_event(peer_id_t(), map()) :: sfu_media_event_t()
  def create_peer_joined_event(peer_id, peer) do
    %{
      type: "peerJoined",
      data: %{
        peer: %{
          id: peer_id,
          metadata: peer.metadata,
          trackIdToMetadata: peer.track_id_to_track_metadata
        }
      }
    }
    |> do_create(:broadcast)
  end

  @spec create_peer_left_event(peer_id_t()) :: sfu_media_event_t()
  def create_peer_left_event(peer_id) do
    %{
      type: "peerLeft",
      data: %{
        peerId: peer_id
      }
    }
    |> do_create(:broadcast)
  end

  @spec create_tracks_added_event(peer_id_t(), map()) ::
          sfu_media_event_t()
  def create_tracks_added_event(peer_id, track_id_to_metadata) do
    %{
      type: "tracksAdded",
      data: %{
        peerId: peer_id,
        trackIdToMetadata: track_id_to_metadata
      }
    }
    |> do_create(:broadcast)
  end

  @spec create_tracks_removed_event(peer_id_t(), list(track_id())) ::
          sfu_media_event_t()
  def create_tracks_removed_event(peer_id, track_ids) do
    %{
      type: "tracksRemoved",
      data: %{
        peerId: peer_id,
        trackIds: track_ids
      }
    }
    |> do_create(:broadcast)
  end

  @spec create_peer_updated_event(peer_id_t(), map()) :: sfu_media_event_t()
  def create_peer_updated_event(peer_id, peer) do
    %{
      type: "peerUpdated",
      data: %{
        peerId: peer_id,
        metadata: peer.metadata
      }
    }
    |> do_create(:broadcast)
  end

  @spec create_track_updated_event(peer_id_t(), String.t(), map()) :: sfu_media_event_t()
  def create_track_updated_event(peer_id, track_id, metadata) do
    %{
      type: "trackUpdated",
      data: %{
        peerId: peer_id,
        trackId: track_id,
        metadata: metadata
      }
    }
    |> do_create(:broadcast)
  end

  @spec create_signal_event(peer_id_t(), {:signal, {:candidate, String.t(), non_neg_integer()}}) ::
          sfu_media_event_t()
  def create_signal_event(peer_id, {:signal, {:candidate, candidate, sdp_m_line_index}}) do
    %{
      type: "candidate",
      data: %{
        candidate: candidate,
        sdpMLineIndex: sdp_m_line_index,
        sdpMid: nil,
        usernameFragment: nil
      }
    }
    |> do_create(peer_id)
  end

  @spec create_signal_event(peer_id_t(), {:signal, {:sdp_offer, String.t()}}) ::
          sfu_media_event_t()
  def create_signal_event(peer_id, {:signal, {:sdp_offer, offer}}) do
    %{
      type: "sdpOffer",
      data: %{
        type: "offer",
        sdp: offer
      }
    }
    |> do_create(peer_id)
  end

  @spec create_signal_event(peer_id_t(), {:signal, {:offer_data, String.t()}}) ::
          sfu_media_event_t()
  def create_signal_event(peer_id, {:signal, {:offer_data, tracks_types}}) do
    %{
      type: "offerData",
      data: tracks_types
    }
    |> do_create(peer_id)
  end

  @spec create_signal_event(peer_id_t(), {:signal, {:sdp_answer, String.t(), map()}}) ::
          sfu_media_event_t()
  def create_signal_event(peer_id, {:signal, {:sdp_answer, answer, mid_to_track_id}}) do
    %{
      type: "sdpAnswer",
      data: %{
        type: "answer",
        sdp: answer,
        midToTrackId: mid_to_track_id
      }
    }
    |> do_create(peer_id)
  end

  @spec create_error_event(to_t(), String.t()) :: sfu_media_event_t()
  def create_error_event(to, msg) do
    %{
      type: "error",
      data: %{
        message: msg
      }
    }
    |> do_create(to)
  end

  defp do_create(event, to) do
    event
    |> serialize()
    |> then(fn event -> {:sfu_media_event, to, event} end)
  end

  @spec serialize(map()) :: binary()
  def serialize(event), do: Jason.encode!(event)

  @spec deserialize(binary()) :: {:ok, map()} | {:error, :invalid_media_event}
  def deserialize(raw_event) do
    case Jason.decode(raw_event) do
      {:ok, event} -> do_deserialize(event)
      _error -> {:error, :invalid_media_event}
    end
  end

  defp do_deserialize(%{"type" => "renegotiateTracks"}) do
    {:ok, %{type: :renegotiate_tracks}}
  end

  defp do_deserialize(%{"type" => "join"} = event) do
    case event do
      %{
        "type" => "join",
        "data" => %{
          "receiveMedia" => receive_media,
          "metadata" => metadata
        }
      } ->
        {:ok,
         %{
           type: :join,
           data: %{
             receive_media: receive_media,
             metadata: metadata
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp do_deserialize(%{"type" => "sdpOffer"} = event) do
    case event do
      %{
        "type" => "sdpOffer",
        "data" => %{
          "sdpOffer" => %{
            "type" => "offer",
            "sdp" => sdp
          },
          "trackIdToTrackMetadata" => track_id_to_track_metadata,
          "midToTrackId" => mid_to_track_id
        }
      } ->
        {:ok,
         %{
           type: :sdp_offer,
           data: %{
             sdp_offer: %{
               type: :offer,
               sdp: sdp
             },
             track_id_to_track_metadata: track_id_to_track_metadata,
             mid_to_track_id: mid_to_track_id
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp do_deserialize(%{"type" => "candidate"} = event) do
    case event do
      %{
        "type" => "candidate",
        "data" => %{
          "candidate" => candidate,
          "sdpMLineIndex" => sdp_m_line_index
        }
      } ->
        {:ok,
         %{
           type: :candidate,
           data: %{
             candidate: candidate,
             sdp_m_line_index: sdp_m_line_index
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp do_deserialize(%{"type" => "updatePeerMetadata"} = event) do
    case event do
      %{
        "type" => "updatePeerMetadata",
        "data" => %{
          "metadata" => peer_metadata
        }
      } ->
        {:ok,
         %{
           type: :update_peer_metadata,
           data: %{
             metadata: peer_metadata
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp do_deserialize(%{"type" => "updateTrackMetadata"} = event) do
    case event do
      %{
        "type" => "updateTrackMetadata",
        "data" => %{
          "trackId" => track_id,
          "trackMetadata" => track_metadata
        }
      } ->
        {:ok,
         %{
           type: :update_track_metadata,
           data: %{
             track_id: track_id,
             track_metadata: track_metadata
           }
         }}

      _other ->
        {:error, :invalid_media_event}
    end
  end

  defp do_deserialize(%{"type" => "leave"}), do: {:ok, %{type: :leave}}

  defp do_deserialize(_event), do: {:error, :invalid_media_event}
end
