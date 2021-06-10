defmodule ExHashRing.Node do
  @moduledoc """
  Types and Functions for working with Ring Nodes and their Replicas
  """

  alias ExHashRing.Hash

  @typedoc """
  Nodes are uniquely identified in the ring by their name.
  """
  @type name :: binary()

  @typedoc """
  Replicas is a count of how many times a Node should be placed into a Ring.

  Replica counts less than 1 are ignored.
  """
  @type replicas :: pos_integer()

  @typedoc """
  Nodes are properly specified as a tuple of their name and their number of replicas
  """
  @type t :: {name(), replicas()}

  @typedoc """
  Nodes can be defined by either using a bare name or using a fully specified node.  When using a
  bare name the definition will have to be converted into a fully specified node, see
  `normalize/2`.
  """
  @type definition :: name() | t()

  @typedoc """
  Nodes are expanded into multiple virtual nodes.
  """
  @type virtual :: {Hash.t(), name()}

  @doc """
  Expands a list of nodes into a list of virtual nodes.
  """
  @spec expand([t()]) :: [virtual()]
  def expand([]), do: []

  def expand(nodes) do
    nodes
    |> Enum.reduce([], fn node, acc ->
      do_expand(node, acc)
    end)
    |> do_sort()
  end

  @spec expand([t()], replicas()) :: [virtual()]
  def expand(nodes, replicas) do
    nodes
    |> normalize(replicas)
    |> expand()
  end

  @doc """
  Converts definitions into fully specified nodes.

  A single definition or a list of defintions can be normalized by this function.
  """
  @spec normalize([definition()], replicas()) :: [t()]
  def normalize(nodes, replicas) when is_list(nodes) do
    Enum.map(nodes, &normalize(&1, replicas))
  end

  @spec normalize(t(), replicas()) :: t()
  def normalize({_name, _replicas} = normalized, _default_replicas) do
    normalized
  end

  @spec normalize(name(), replicas()) :: t()
  def normalize(name, replicas) do
    {name, replicas}
  end

  ## Private

  @spec do_expand(node :: t, acc :: [virtual()]) :: [virtual()]
  defp do_expand({name, replicas}, acc) when replicas > 0 do
    Enum.reduce(0..(replicas - 1), acc, fn replica, acc ->
      [{Hash.of("#{name}#{replica}"), name} | acc]
    end)
  end

  defp do_expand(_, acc) do
    acc
  end

  @spec do_sort([virtual()]) :: [virtual()]
  defp do_sort(virtual_nodes) do
    Enum.sort(virtual_nodes, &(elem(&1, 0) < elem(&2, 0)))
  end
end
