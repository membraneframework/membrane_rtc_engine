defmodule Membrane.RTC.HLSEndpointTest do
  use ExUnit.Case

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.HLS
  alias Membrane.RTC.Engine.{Message, Peer}
  alias Membrane.RTC.Engine.Support.FileEndpoint

  @fixtures_dir "./test/fixtures/"

  setup do
    options = [
      id: "test_rtc"
    ]

    {:ok, pid} = Engine.start_link(options, [])

    Engine.register(pid, self())

    [rtc_engine: pid]
  end

  describe "HLS Endpoint test" do
    test "FileEndpoint send media to HLS Endpoint", %{rtc_engine: rtc_engine} do
      peer_id = "file-endpoint-peer"
      metadata = %{"display_name" => "test_peer"}

      add_peer(rtc_engine, peer_id, metadata)

      file_name = "video.h264"
      file_path = Path.join(@fixtures_dir, file_name)

      hls_endpoint_id = "hls-endpoint"

      track_id = "test-track-id"

      track =
        Engine.Track.new(
          :video,
          "test-stream",
          peer_id,
          :H264,
          nil,
          [:raw],
          nil,
          id: track_id
        )

      hls_endpoint = %HLS{
        rtc_engine: rtc_engine,
        owner: self(),
        output_directory: Path.join(["./", "test", "hls_output"]),
        target_window_duration: :infinity
      }

      :ok = Engine.add_endpoint(rtc_engine, hls_endpoint, endpoint_id: hls_endpoint_id)

      file_endpoint = %FileEndpoint{rtc_engine: rtc_engine, file_path: file_path, track: track}

      :ok = Engine.add_endpoint(rtc_engine, file_endpoint, peer_id: peer_id)

      assert_receive %Message.MediaEvent{rtc_engine: ^rtc_engine, to: :broadcast, data: data}

      assert %{
               "type" => "tracksAdded",
               "data" => %{
                 "trackIdToMetadata" => %{track_id => nil},
                 "peerId" => peer_id
               }
             } == Jason.decode!(data)

      custom_media_event = Jason.encode!(%{"type" => "custom", "data" => "start_track"})

      send(rtc_engine, {:media_event, peer_id, custom_media_event})

      assert_receive({:playlist_playable, :video, stream}, 2_000)
    end
  end

  defp add_peer(rtc_engine, peer_id, metadata) do
    peer = Peer.new(peer_id, metadata)
    :ok = Engine.add_peer(rtc_engine, peer)
    assert_receive %Message.MediaEvent{rtc_engine: ^rtc_engine, to: ^peer_id, data: data}

    assert %{"type" => "peerAccepted", "data" => %{"id" => peer_id, "peersInRoom" => []}} ==
             Jason.decode!(data)

    assert_receive %Message.MediaEvent{rtc_engine: ^rtc_engine, to: :broadcast, data: data}

    assert %{
             "type" => "peerJoined",
             "data" => %{
               "peer" => %{"id" => peer_id, "metadata" => metadata}
             }
           } == Jason.decode!(data)
  end
end
