defmodule Membrane.RTC.Engine.Metrics.Model.TrackMetrics do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          time: NaiveDateTime.t() | nil,
          track_id: String.t() | nil,
          "track.metadata": String.t() | nil,
          "inbound-rtp.encoding": non_neg_integer() | nil,
          "inbound-rtp.ssrc": non_neg_integer() | nil,
          "inbound-rtp.bytes_received": non_neg_integer() | nil,
          "inbound-rtp.keyframe_request_sent": non_neg_integer() | nil,
          "inbound-rtp.packets": non_neg_integer() | nil,
          "inbound-rtp.frames": non_neg_integer() | nil,
          "inbound-rtp.keyframes": non_neg_integer() | nil
        }

  @primary_key false
  schema "tracks_metrics" do
    field(:time, :naive_datetime_usec)
    field(:track_id, :string)

    field(:"track.metadata", :string)
    field(:"inbound-rtp.encoding", :string)
    field(:"inbound-rtp.ssrc", :string)
    field(:"inbound-rtp.bytes_received", :integer)
    field(:"inbound-rtp.keyframe_request_sent", :integer)
    field(:"inbound-rtp.packets", :integer)
    field(:"inbound-rtp.frames", :integer)
    field(:"inbound-rtp.keyframes", :integer)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, params) do
    required_fields = [:time, :track_id]

    casted_fields =
      required_fields ++
        [
          :"track.metadata",
          :"inbound-rtp.encoding",
          :"inbound-rtp.ssrc",
          :"inbound-rtp.bytes_received",
          :"inbound-rtp.keyframe_request_sent",
          :"inbound-rtp.packets",
          :"inbound-rtp.frames",
          :"inbound-rtp.keyframes"
        ]

    schema
    |> cast(params, casted_fields)
    |> validate_required(required_fields)
  end
end
