defmodule HashRing.Utils do
  @compile :native

  @type t :: __MODULE__
  use Bitwise

  def hash(key) when is_binary(key) do
    <<_ :: binary-size(8), a, b, c, d, e, f, g, h>> = :erlang.md5(key)
    low = d <<< 24 ||| c <<< 16 ||| b <<< 8 ||| a
    high = h <<< 24 ||| g <<< 16 ||| f <<< 8 ||| e
    ((high <<< 32) &&& 0xffffffff00000000) ||| low
  end
  def hash(key), do: hash("#{key}")

  def gen_items([], _num_replicas), do: {}
  def gen_items(nodes, num_replicas) do
    gen_items(nodes, Enum.to_list(0..(num_replicas - 1)), [])
  end

  def gen_items([], _replicas, items) do
    items
      |> Enum.sort(&(elem(&1, 0) < elem(&2, 0)))
      |> List.to_tuple
  end
  def gen_items([node|nodes], replicas, items) do
    items = Enum.reduce(replicas, items, &([{hash("#{node}#{&1}"), node}|&2]))
    gen_items(nodes, replicas, items)
  end

end