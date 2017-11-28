defmodule HashRing.ETS do
  @compile :native

  @type t :: __MODULE__

  use GenServer

  alias HashRing.Utils

  defstruct num_replicas: 0, nodes: [], table: nil, ring_gen: 0

  def start_link(name, nodes \\ [], num_replicas \\ 512) do
    GenServer.start_link(__MODULE__, {name, nodes, num_replicas}, name: name)
  end

  @spec init({atom, [binary], integer}) :: t
  def init({name, nodes, num_replicas}) do
    table = :ets.new(name, [
      :public,
      :set,
      :named_table,
      {:read_concurrency, true}
    ])

    state = %__MODULE__{
      table: table,
      num_replicas: num_replicas,
      nodes: nodes,
    } |> rebuild

    {:ok, state}
  end

  @spec set_nodes(atom, [binary]) :: t
  def set_nodes(name, nodes) do
    GenServer.call(name, {:set_nodes, nodes})
  end

  @spec add_node(atom, binary) :: {:ok, t} | :error
  def add_node(name, node) do
    GenServer.call(name, {:add_node, node})
  end

  @spec remove_node(atom, binary) :: {:ok, t} | :error
  def remove_node(name, node) do
    GenServer.call(name, {:remove_node, node})
  end

  @spec find_node(t, binary | integer) :: binary | nil
  def find_node(name, key) do
    with {:ok, config} <- get_ring_config(name),
         {_, node} <- find_next_highest_item(name, config, Utils.hash(key)) do
      node
    end
  end

  @spec find_nodes(t, binary | integer, integer) :: [binary]
  def find_nodes(name, key, num) do
    with {:ok, {_, _, num_nodes}=config} <- get_ring_config(name),
         nodes <- do_find_nodes(name, config, min(num, num_nodes), Utils.hash(key), []) do
      nodes
    end
  end

  ## Private

  defp do_find_nodes(_name, _config, 0, _key_int, nodes) do
    Enum.reverse(nodes)
  end
  defp do_find_nodes(name, config, ret, key_int, nodes) do
    {number, node} = find_next_highest_item(name, config, key_int)
    if node in nodes do
      do_find_nodes(name, config, ret, number, nodes)
    else
      do_find_nodes(name, config, ret - 1, number, [node|nodes])
    end
  end

  def handle_call({:set_nodes, nodes}, _from, %{name: name}=state) do
    new_state = %{state | nodes: nodes} |> rebuild
    {:reply, {:ok, name}, new_state}
  end
  def handle_call({:add_node, node}, _from, %{name: name, nodes: nodes}=state) do
    if node in nodes do
      {:reply, :error, state}
    else
      new_state = %{state | nodes: [node|nodes]} |> rebuild
      {:reply, {:ok, name}, new_state}
    end
  end
  def handle_call({:remove_node, node}, _from, %{name: name, nodes: nodes}=state) do
    if node in nodes do
      new_state = %{state | nodes: nodes -- [node]} |> rebuild
      {:reply, {:ok, name}, new_state}
    else
      {:reply, :error, state}
    end
  end

  defp rebuild(%{nodes: nodes, num_replicas: num_replicas, table: table, ring_gen: ring_gen}=state) do
    ring_gen = ring_gen + 1
    ets_items = Utils.gen_items(nodes, num_replicas)
      |> Tuple.to_list
      |> Enum.with_index
      |> Enum.map(fn {item, index} ->
        {{ring_gen, index}, item}
      end)

    ets_items = [{:config, {ring_gen, length(ets_items), length(nodes)}} | ets_items]
    :ets.insert(table, ets_items)
    %{state | ring_gen: ring_gen}
  end

  defp find_next_highest_item(_name, {_ring_gen, 0, _num_nodes}, _key_int) do
    nil
  end
  defp find_next_highest_item(name, {_ring_gen, num_items, _num_nodes}=config, key_int) do
    find_next_highest_item(name, config, key_int, 0, num_items - 1)
  end

  defp find_next_highest_item(name, {ring_gen, num_items, _num_nodes}=config, key_int, min, max) do
    mid = div(min + max, 2)
    {number, _node} = ets_elem(name, ring_gen, mid)
    {min, max} =
      if number > key_int do
        # Key is in the lower half.
        {min, mid - 1}
      else
        # Key is in the upper half.
        {mid + 1, max}
      end
    cond do
      min > max and min == num_items ->
        # Past the end of the ring, return the first item.
        ets_elem(name, ring_gen, 0)
      min > max ->
        # Return the next highest item.
        ets_elem(name, ring_gen, min)
      true ->
        find_next_highest_item(name, config, key_int, min, max)
    end
  end

  defp ets_elem(name, ring_gen, index) do
    # This should always exist, or there is a big bug and we should CRASH AND BURN!
    [{{^ring_gen, ^index}, item}] = :ets.lookup(name, {ring_gen, index})
    item
  end

  defp get_ring_config(name) do
    case :ets.lookup(name, :config) do
       [{:config, config}] -> {:ok, config}
       _ ->
        :error
    end
  end
end