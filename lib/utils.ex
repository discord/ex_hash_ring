defmodule ExHashRing.HashRing.Utils do
  @compile :native
  @compile {:inline, take: 2}

  @spec hash(atom | binary | integer) :: integer
  def hash(key) when is_binary(key) do
    <<_::binary-size(8), value::unsigned-little-integer-size(64)>> = :erlang.md5(key)
    value
  end

  def hash(key), do: hash("#{key}")

  @spec gen_items([{binary, integer}]) :: [{integer, binary}]
  @spec gen_items(binary, integer) :: [{integer, binary}]
  def gen_items([]), do: []
  def gen_items(nodes), do: do_gen_items(nodes, [])
  def gen_items([], _num_replicas), do: []

  def gen_items(nodes, default_num_replicas) do
    nodes = for node <- nodes, do: {node, default_num_replicas}
    gen_items(nodes)
  end

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

  def take(_, 0), do: []
  def take([a | _], 1), do: [a]
  def take([a, b | _], 2), do: [a, b]
  def take([a, b, c | _], 3), do: [a, b, c]
  def take([a, b, c, d | _], 4), do: [a, b, c, d]
  def take([a, b, c, d, e | _], 5), do: [a, b, c, d, e]
  def take(list, n), do: Enum.take(list, n)
end
