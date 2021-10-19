defmodule Membrane.RTC.Utils do
  @moduledoc false

  alias Membrane.Pipeline.CallbackContext.Notification

  @spec find_child(ctx :: any(), pattern: pattern :: any()) :: Macro.t()
  defmacro find_child(ctx, pattern: pattern) do
    quote do
      unquote(ctx).children |> Map.keys() |> Enum.find(&match?(unquote(pattern), &1))
    end
  end

  @spec reduce_children(ctx :: Notification.t(), acc :: any(), fun :: fun()) ::
          any()
  def reduce_children(ctx, acc, fun), do: Enum.reduce(ctx.children, acc, fun)

  @spec flat_map_children(ctx :: Notification.t(), fun :: fun()) :: [any()]
  def flat_map_children(ctx, fun), do: Enum.flat_map(ctx.children, fun)
end
