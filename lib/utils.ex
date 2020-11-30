defmodule ExHashRing.Utils do
  @moduledoc """
  Utility functions used throughout ExHashRing
  """

  @compile :native
  @compile {:inline, do_take_max: 3, take_max: 2}

  @doc """
  Take up to maximum items from a list.

  This function returns the items in reverse order and with a count of how many items were found.
  """
  @spec take_max(list :: [item], maximum :: non_neg_integer()) :: {list :: [item], count :: non_neg_integer()} when item: term()
  def take_max(list, maximum)

  def take_max(_, 0), do: {[], 0}

  def take_max(list, maximum) when maximum > 0 do
    do_take_max(list, maximum, {[], 0})
  end

  defp do_take_max([], _remaining, acc), do: acc

  defp do_take_max(_, 0, acc), do: acc

  defp do_take_max([head | tail], remaining, {items, count}) do
    do_take_max(tail, remaining - 1, {[head | items], count + 1})
  end
end
