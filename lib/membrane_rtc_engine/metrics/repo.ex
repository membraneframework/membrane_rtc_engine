defmodule Membrane.RTC.Engine.Metrics.Repo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :membrane_rtc_engine,
    adapter: Ecto.Adapters.Postgres
end
