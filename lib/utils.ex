defmodule ExHashRing.HashRing.Utils do
  @compile :native
  @compile {:inline, do_take_max: 3, take_max: 2}

  @spec hash(atom | binary | integer) :: integer
  def hash(key) when is_binary(key) do
    <<_::binary-size(8), value::unsigned-little-integer-size(64)>> = :erlang.md5(key)
    value
  end

  def hash(key), do: hash("#{key}")

  @spec transform_nodes([binary], integer) :: [{binary, integer}]
  def transform_nodes(nodes, default_num_replicas) do
    Enum.map(nodes, fn
      {_node, _num_replicas} = item -> item
      node -> {node, default_num_replicas}
    end)
  end

  @spec gen_items([{binary, integer}]) :: [{integer, binary}]
  def gen_items(nodes), do: do_gen_items(nodes, [])

  defp do_gen_items([], items) do
    Enum.sort(items, &(elem(&1, 0) < elem(&2, 0)))
  end

  defp do_gen_items([{node, num_replicas} | nodes], items) do
    items =
      Enum.reduce(0..(num_replicas - 1), items, fn replica, acc ->
        [{hash("#{node}#{replica}"), node} | acc]
      end)

    do_gen_items(nodes, items)
  end

  @spec take_max(list :: list, maximum :: integer) :: {list :: list, count :: integer}
  def take_max(list, maximum)
  def take_max(_, 0), do: {[], 0}
  def take_max(list, maximum) when maximum > 0, do: do_take_max(list, maximum, 0)

  @spec do_take_max(list, remaining :: integer, count :: integer) :: {list, count :: integer}
  defp do_take_max([head | _], 1, count) do
    {[head], count + 1}
  end

  defp do_take_max([head | tail], remaining, count) do
    {tail, count} = do_take_max(tail, remaining - 1, count + 1)

    {[head | tail], count}
  end

  defp do_take_max([], _remaining, count) do
    {[], count}
  end
end
