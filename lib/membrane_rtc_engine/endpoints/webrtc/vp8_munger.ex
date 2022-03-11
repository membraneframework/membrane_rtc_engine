defmodule Membrane.RTC.Engine.Endpoint.WebRTC.VP8Munger do
  @moduledoc false
  # Module responsible for rewriting VP8 RTP payload fields
  # to provide transparent switch between simulcast encodings.
  use Bitwise

  alias Membrane.Buffer
  alias Membrane.RTP.VP8

  @type t() :: %__MODULE__{
          pic_id_used: boolean(),
          last_pic_id: integer(),
          pic_id_offset: integer(),
          tl0picidx_used: boolean(),
          last_tl0picidx: integer(),
          tl0picidx_offset: integer(),
          keyidx_used: boolean(),
          last_keyidx: integer(),
          keyidx_offset: integer()
        }

  defstruct pic_id_used: false,
            last_pic_id: 0,
            pic_id_offset: 0,
            tl0picidx_used: false,
            last_tl0picidx: 0,
            tl0picidx_offset: 0,
            keyidx_used: false,
            last_keyidx: 0,
            keyidx_offset: 0

  @spec new() :: t()
  def new() do
    %__MODULE__{}
  end

  @spec init(t(), Membrane.Buffer.t()) :: t()
  def init(vp8_munger, buffer) do
    {:ok, {payload_descriptor, _payload}} =
      VP8.PayloadDescriptor.parse_payload_descriptor(buffer.payload)

    %VP8.PayloadDescriptor{
      i: i,
      keyidx: keyidx,
      l: l,
      picture_id: pic_id,
      k: k,
      tl0picidx: tl0picidx
    } = payload_descriptor

    pic_id_used = i == 1
    tl0picidx_used = l == 1
    keyidx_used = k == 1

    last_pic_id = if pic_id_used, do: pic_id, else: 0
    last_tl0picidx = if tl0picidx_used, do: tl0picidx, else: 0
    last_keyidx = if keyidx_used, do: keyidx, else: 0

    %__MODULE__{
      vp8_munger
      | pic_id_used: pic_id_used,
        last_pic_id: last_pic_id,
        tl0picidx_used: tl0picidx_used,
        last_tl0picidx: last_tl0picidx,
        keyidx_used: keyidx_used,
        last_keyidx: last_keyidx
    }
  end

  @spec update(t(), Membrane.Buffer.t()) :: t()
  def update(vp8_munger, buffer) do
    {:ok, {payload_descriptor, _payload}} =
      VP8.PayloadDescriptor.parse_payload_descriptor(buffer.payload)

    %VP8.PayloadDescriptor{
      keyidx: keyidx,
      picture_id: pic_id,
      tl0picidx: tl0picidx
    } = payload_descriptor

    pic_id_offset = if vp8_munger.pic_id_used, do: pic_id - vp8_munger.last_pic_id - 1, else: 0

    tl0picidx_offset =
      if vp8_munger.tl0picidx_used, do: tl0picidx - vp8_munger.last_tl0picidx - 1, else: 0

    keyidx_offset = if vp8_munger.keyidx_used, do: keyidx - vp8_munger.last_keyidx - 1, else: 0

    %__MODULE__{
      vp8_munger
      | pic_id_offset: pic_id_offset,
        tl0picidx_offset: tl0picidx_offset,
        keyidx_offset: keyidx_offset
    }
  end

  @spec munge(t(), Membrane.Buffer.t()) :: {t(), Membrane.Buffer.t()}
  def munge(vp8_munger, %Membrane.Buffer{payload: <<>>} = buffer), do: {vp8_munger, buffer}

  def munge(vp8_munger, buffer) do
    {:ok, {payload_descriptor, vp8_payload}} =
      VP8.PayloadDescriptor.parse_payload_descriptor(buffer.payload)

    %VP8.PayloadDescriptor{
      keyidx: keyidx,
      picture_id: pic_id,
      tl0picidx: tl0picidx
    } = payload_descriptor

    munged_pic_id = rem(pic_id + (1 <<< 15) - vp8_munger.pic_id_offset, 1 <<< 15)
    munged_tl0picidx = rem(tl0picidx + (1 <<< 8) - vp8_munger.tl0picidx_offset, 1 <<< 8)
    munged_keyidx = rem(keyidx + (1 <<< 5) - vp8_munger.keyidx_offset, 1 <<< 5)

    buffer =
      %VP8.PayloadDescriptor{
        payload_descriptor
        | keyidx: munged_keyidx,
          picture_id: munged_pic_id,
          tl0picidx: munged_tl0picidx
      }
      |> VP8.PayloadDescriptor.serialize()
      |> then(fn munged_payload_descriptor ->
        %Buffer{buffer | payload: munged_payload_descriptor <> vp8_payload}
      end)

    vp8_munger = %__MODULE__{
      vp8_munger
      | last_pic_id: munged_pic_id,
        last_tl0picidx: munged_tl0picidx,
        last_keyidx: munged_keyidx
    }

    {vp8_munger, buffer}
  end
end
