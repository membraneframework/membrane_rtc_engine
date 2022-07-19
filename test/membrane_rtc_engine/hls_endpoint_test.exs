defmodule Membrane.RTC.HLSEndpointTest do
  use ExUnit.Case

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.HLS
  alias Membrane.RTC.Engine.{Message, Peer}
  alias Membrane.RTC.Engine.Support.FileEndpoint

  @fixtures_dir "./test/fixtures/"
  @reference_dir "./test/hls_reference/"
  @output_dir "./test/hls_output/"

  setup do
    options = [
      id: "test_rtc"
    ]

    {:ok, pid} = Engine.start_link(options, [])

    Engine.register(pid, self())

    [rtc_engine: pid]
  end

  describe "HLS Endpoint test" do
    test "creates correct hls stream", %{rtc_engine: rtc_engine} do
      peer_id = "file-endpoint-peer"
      metadata = %{"display_name" => "test_peer"}

      add_peer(rtc_engine, peer_id, metadata)

      file_name = "video.h264"
      file_path = Path.join(@fixtures_dir, file_name)

      hls_endpoint_id = "hls-endpoint"

      track_id = "test-track-id"
      stream_id = "test-stream"

      track =
        Engine.Track.new(
          :video,
          stream_id,
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

      assert_receive({:playlist_playable, :video, ^stream_id}, 2_000)

      Process.sleep(15_000)

      output_dir = Path.join([@output_dir, stream_id])
      reference_dir = Path.join([@reference_dir, stream_id])

      directory_files = File.ls!(output_dir)

      assert Enum.sort(directory_files) == reference_dir |> File.ls!() |> Enum.sort()

      for file <- directory_files do
        output_path = Path.join(output_dir, file)
        reference_path = Path.join(reference_dir, file)

        assert File.read!(output_path) == File.read!(reference_path)
      end

      File.rm_rf!(@output_dir)
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
