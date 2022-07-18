defmodule Membrane.RTC.Engine.Metrics.Model.TrackToPeer do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          time: NaiveDateTime.t() | nil,
          track_id: String.t() | nil,
          peer_id: String.t() | nil
        }

  @primary_key false
  schema "track_to_peer" do
    field(:time, :naive_datetime_usec)
    field(:track_id, :string)
    field(:peer_id, :string)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(schema, params) do
    fields = [:time, :track_id, :peer_id]

    schema
    |> cast(params, fields)
    |> validate_required(fields)
    |> unique_constraint([:track_id, :peer_id], name: :track_to_peer_track_id_peer_id_index)
  end
end
