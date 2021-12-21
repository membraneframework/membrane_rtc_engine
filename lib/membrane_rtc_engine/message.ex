defmodule Membrane.RTC.Engine.Message do
  @moduledoc """
  Module describing messages RTC Engine can emit.

  Each Message contains RTC Engine PID under `rtc_engine` field.
  Thanks to it you can distinguish between the same messages but from different RTC Engine instances.
  """
  alias Membrane.RTC.Engine.Peer

  @type t() :: __MODULE__.MediaEvent.t() | __MODULE__.NewPeer.t()

  defmodule MediaEvent do
    @moduledoc """
    Message emitted when RTC Engine need to send some Media Event to the Client Library.
    """

    @typedoc """
    Describes Media Event Message structure.

    * `rtc_engine` - pid of RTC Engine instance which emitted this message
    * `to` - informs where this Media Event should be sent. If set to `:broadcast`, the Media Event
    should be sent to all peers. When set to `t:Membrane.RTC.Engine.Peer.id()`, the Media Event
    should be sent to that specified peer.
    * `data` - Media Event in serialized i.e. binary form
    """
    @type t() :: %__MODULE__{
            rtc_engine: pid(),
            to: Peer.id() | :broadcast,
            data: binary()
          }
    @enforce_keys [:rtc_engine, :to, :data]
    defstruct @enforce_keys
  end

  defmodule NewPeer do
    @moduledoc """
    Message emmited when a new peer from Client Library tries to join RTC Engine.

    You can reply to this message using: `Membrane.RTC.Engine.accept_peer/2` and
    `Membrane.RTC.Engine.deny_peer/2` or `Membrane.RTC.Engine.deny_peer/3`.
    """

    @typedoc """
    Describes New Peer Message structure.

    * `rtc_engine` - pid of RTC Engine instance which emitted this message
    * `peer` - struct describing a new peer trying to join to RTC Engine
    """
    @type t() :: %__MODULE__{
            rtc_engine: pid(),
            peer: Peer.t()
          }

    @enforce_keys [:rtc_engine, :peer]
    defstruct @enforce_keys
  end
end
