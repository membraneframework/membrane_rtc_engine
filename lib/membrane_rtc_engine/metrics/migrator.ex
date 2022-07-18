defmodule Membrane.RTC.Engine.Metrics.Migrator do
  @moduledoc """
  An auto migration task that can be run along with Reporter's supervisor tree.
  """
  use GenServer

  require Logger

  @repo Membrane.RTC.Engine.Metrics.Repo

  @spec start_link(GenServer.options()) :: :ignore | {:error, any()}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  @impl true
  def init(_opts) do
    if migrate() do
      Logger.info("#{@repo} successfully migrated.")

      :ignore
    else
      message = "#{@repo} failed to perform a migration"
      Logger.error(message)

      {:error, message}
    end
  end

  @doc """
  Performs database migration required for the reporter to work.
  """
  @spec migrate() :: boolean()
  def migrate() do
    case Ecto.Migrator.with_repo(@repo, &Ecto.Migrator.run(&1, :up, all: true)) do
      {:ok, _return, _started_apps} -> true
      _other -> false
    end
  end
end
