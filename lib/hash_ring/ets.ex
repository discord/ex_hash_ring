defmodule HashRing.ETS do
  @compile :native

  @default_ring_gen_gc_delay 10_000
  @type t :: __MODULE__

  use GenServer

  alias HashRing.Utils
  alias HashRing.ETS.Config

  defstruct num_replicas: 0,
            nodes: [],
            table: nil,
            ring_gen: 0,
            name: nil,
            pending_gcs: %{}

  def start_link(name, nodes \\ [], num_replicas \\ 512) do
    GenServer.start_link(__MODULE__, {name, nodes, num_replicas}, name: name)
  end

  @spec init({atom, [binary], integer}) :: t
  def init({name, nodes, num_replicas}) do
    table = :ets.new(name, [
      :protected,
      :ordered_set,
      {:read_concurrency, true}
    ])

    state = %__MODULE__{
      table: table,
      num_replicas: num_replicas,
      nodes: nodes,
      name: name,
    } |> rebuild

    {:ok, state}
  end

  def stop(name) do
    GenServer.stop(name)
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

  @spec get_nodes(atom) :: {:ok, [binary]} | :error
  def get_nodes(name) do
    GenServer.call(name, :get_nodes)
  end

  @spec force_gc(atom, integer) :: :ok | {:error, :not_pending}
  def force_gc(name, ring_gen) do
    GenServer.call(name, {:force_gc, ring_gen})
  end

  @spec get_ring_gen(atom) :: {:ok, integer} | :error
  def get_ring_gen(name) do
    with {:ok, {_, ring_gen, _}} <- Config.get(name) do
      {:ok, ring_gen}
    end
  end

  @spec find_node(atom, binary | integer) :: binary | nil
  def find_node(name, key) do
    with {:ok, config} <- Config.get(name),
         {_, node} <- find_next_highest_item(config, Utils.hash(key)) do
      node
    else
      _ -> nil
    end
  end

  @spec find_nodes(atom, binary | integer, integer) :: [binary]
  def find_nodes(name, key, num) do
    with {:ok, {_, _, num_nodes}=config} <- Config.get(name),
         nodes <- do_find_nodes(config, min(num, num_nodes), Utils.hash(key), []) do
      nodes
    else
      _ -> []
    end
  end

  ## Private

  defp do_find_nodes(_config, 0, _key_int, nodes) do
    Enum.reverse(nodes)
  end
  defp do_find_nodes(config, remaining, key_int, nodes) do
    {number, node} = find_next_highest_item(config, key_int)
    if node in nodes do
      do_find_nodes(config, remaining, number, nodes)
    else
      do_find_nodes(config, remaining - 1, number, [node|nodes])
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
  def handle_call(:get_nodes, _from, %{nodes: nodes}=state) do
    {:reply, {:ok, nodes}, state}
  end
  def handle_call({:force_gc, ring_gen}, _from, %{pending_gcs: pending_gcs, table: table}=state) do
    {reply, pending_gcs} = case Map.pop(pending_gcs, ring_gen) do
      {nil, pending_gcs} ->
        {{:error, :not_pending}, pending_gcs}
      {timer_ref, pending_gcs} ->
        Process.cancel_timer(timer_ref)
        {do_ring_gen_gc(table, ring_gen), pending_gcs}
    end

    {:reply, reply, %{state | pending_gcs: pending_gcs}}
  end

  def handle_info({:gc, ring_gen}, %{pending_gcs: pending_gcs, table: table}=state) do
    pending_gcs = case Map.pop(pending_gcs, ring_gen) do
      {nil, pending_gcs} -> pending_gcs
      {_stale_timer_ref, pending_gcs} ->
        do_ring_gen_gc(table, ring_gen)
        pending_gcs
    end

    {:noreply, %{state | pending_gcs: pending_gcs}}
  end

  defp rebuild(%{nodes: nodes, num_replicas: num_replicas, name: name, table: table, ring_gen: ring_gen, pending_gcs: pending_gcs}=state) do
    new_ring_gen = ring_gen + 1
    ets_items = Utils.gen_items(nodes, num_replicas)
      |> Enum.map(fn {hash, node} ->
        {{new_ring_gen, hash}, node}
      end)

    :ets.insert(table, ets_items)
    Config.set(name, self(), {table, new_ring_gen, length(nodes)})
    timer_ref = Process.send_after(self(), {:gc, ring_gen}, ring_gen_gc_delay())
    %{state | ring_gen: new_ring_gen, pending_gcs: Map.put(pending_gcs, ring_gen, timer_ref)}
  end

  defp ring_gen_gc_delay() do
    Application.get_env(:hash_ring, :ets_gc_delay, @default_ring_gen_gc_delay)
  end

  defp do_ring_gen_gc(table, ring_gen) do
    :ets.match_delete(table, {{ring_gen, :_}, :_})
    :ok
  end

  defp find_next_highest_item({_table, _ring_gen, 0}, _key_int) do
    nil
  end
  defp find_next_highest_item({table, ring_gen, _num_nodes}, key_int) do
    key = case :ets.next(table, {ring_gen, key_int}) do
      {^ring_gen, _number}=key -> key
      _ -> :ets.next(table, {ring_gen, -1})
    end
    case :ets.lookup(table, key) do
      [{{^ring_gen, number}, node}] -> {number, node}
      _ -> nil
    end
  end
end
