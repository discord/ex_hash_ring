defmodule ExHashRing.HashRing.ETS do
  @default_num_replicas 512
  @default_ring_gen_gc_delay 10_000

  @type t :: __MODULE__

  use GenServer

  alias ExHashRing.HashRing.Utils
  alias ExHashRing.HashRing.ETS.Config

  defstruct default_num_replicas: @default_num_replicas,
            nodes: [],
            table: nil,
            ring_gen: 0,
            name: nil,
            pending_gcs: %{}

  def start_link(name, opts \\ []) do
    named = Keyword.get(opts, :named, false)
    nodes = Keyword.get(opts, :nodes, [])
    num_replicas = Keyword.get(opts, :default_num_replicas, @default_num_replicas)

    gen_opts =
      if named do
        [name: name]
      else
        []
      end

    GenServer.start_link(__MODULE__, {name, nodes, num_replicas}, gen_opts)
  end

  @spec init({atom, [binary], integer}) :: t
  def init({name, nodes, default_num_replicas}) do
    table =
      :ets.new(:ring, [
        :protected,
        :ordered_set,
        {:read_concurrency, true}
      ])

    state =
      rebuild(%__MODULE__{
        table: table,
        default_num_replicas: default_num_replicas,
        nodes: transform_nodes(nodes, default_num_replicas),
        name: name
      })

    {:ok, state}
  end

  def stop(name) do
    GenServer.stop(name)
  end

  @spec set_nodes(atom, [binary | {binary, integer}]) :: {:ok, [{binary, integer}]}
  def set_nodes(name, node_names) do
    GenServer.call(name, {:set_nodes, node_names})
  end

  @spec add_node(atom, binary, integer) :: {:ok, [{binary, integer}]} | {:error, :node_exists}
  def add_node(name, node_name, num_replicas \\ nil) do
    GenServer.call(name, {:add_node, node_name, num_replicas})
  end

  @spec remove_node(atom, binary) :: {:ok, [{binary, integer}]} | {:error, :node_exists}
  def remove_node(name, node_name) do
    GenServer.call(name, {:remove_node, node_name})
  end

  @spec get_nodes(atom) :: {:ok, [binary]}
  def get_nodes(name) do
    GenServer.call(name, :get_nodes)
  end

  @spec get_nodes(atom) :: {:ok, [{binary, integer}]}
  def get_nodes_with_replicas(name) do
    GenServer.call(name, :get_nodes_with_replicas)
  end

  @spec force_gc(atom) :: {:ok, [integer]}
  def force_gc(name) do
    GenServer.call(name, :force_gc)
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

  @spec find_node(atom, binary | integer) :: {:ok, binary} | {:error, atom}
  def find_node(name, key) do
    with {:ok, config} <- Config.get(name),
         {_, node} <- find_next_highest_item(config, Utils.hash(key)) do
      {:ok, node}
    else
      {:error, error} -> {:error, error}
      _ -> {:error, :invalid_ring}
    end
  end

  @spec find_nodes(atom, binary | integer, integer) :: {:ok, [binary]} | {:error, atom}
  def find_nodes(name, key, num) do
    with {:ok, {_, _, num_nodes} = config} when num_nodes > 0 <- Config.get(name),
         nodes <- do_find_nodes(config, min(num, num_nodes), Utils.hash(key), []) do
      {:ok, nodes}
    else
      {:error, error} -> {:error, error}
      _ -> {:error, :invalid_ring}
    end
  end

  ## Private

  defp do_find_nodes(_config, 0, _hash, nodes) do
    Enum.reverse(nodes)
  end

  defp do_find_nodes(config, remaining, hash, nodes) do
    {number, node} = find_next_highest_item(config, hash)

    if node in nodes do
      do_find_nodes(config, remaining, number, nodes)
    else
      do_find_nodes(config, remaining - 1, number, [node | nodes])
    end
  end

  def handle_call(
        {:set_nodes, nodes},
        _from,
        %{default_num_replicas: default_num_replicas} = state
      ) do
    nodes = transform_nodes(nodes, default_num_replicas)
    {:reply, {:ok, nodes}, rebuild(%{state | nodes: nodes})}
  end

  def handle_call(
        {:add_node, node_name, nil},
        from,
        %{default_num_replicas: default_num_replicas} = state
      ) do
    handle_call({:add_node, node_name, default_num_replicas}, from, state)
  end

  def handle_call({:add_node, node_name, num_replicas}, _from, %{nodes: nodes} = state) do
    if has_node_with_name?(nodes, node_name) do
      {:reply, {:error, :node_exists}, state}
    else
      nodes = [{node_name, num_replicas} | nodes]
      {:reply, {:ok, nodes}, rebuild(%{state | nodes: nodes})}
    end
  end

  def handle_call({:remove_node, node_name}, _from, %{nodes: nodes} = state) do
    if has_node_with_name?(nodes, node_name) do
      nodes = Enum.reject(nodes, fn {existing_node, _} -> existing_node == node_name end)
      {:reply, {:ok, nodes}, rebuild(%{state | nodes: nodes})}
    else
      {:reply, {:error, :node_not_exists}, state}
    end
  end

  def handle_call(:get_nodes, _from, %{nodes: nodes} = state) do
    nodes = for {node_name, _} <- nodes, do: node_name
    {:reply, {:ok, nodes}, state}
  end

  def handle_call(:get_nodes_with_replicas, _from, %{nodes: nodes} = state) do
    {:reply, {:ok, nodes}, state}
  end

  def handle_call(:force_gc, _from, %{pending_gcs: pending_gcs} = state)
      when map_size(pending_gcs) == 0 do
    {:reply, {:ok, []}, state}
  end

  def handle_call(:force_gc, _from, %{pending_gcs: pending_gcs, table: table} = state) do
    ring_gens =
      for {ring_gen, timer_ref} <- pending_gcs do
        Process.cancel_timer(timer_ref)
        do_ring_gen_gc(table, ring_gen)
        ring_gen
      end

    {:reply, {:ok, ring_gens}, %{state | pending_gcs: %{}}}
  end

  def handle_call({:force_gc, ring_gen}, _from, %{pending_gcs: pending_gcs, table: table} = state) do
    {reply, pending_gcs} =
      case Map.pop(pending_gcs, ring_gen) do
        {nil, pending_gcs} ->
          {{:error, :not_pending}, pending_gcs}

        {timer_ref, pending_gcs} ->
          Process.cancel_timer(timer_ref)
          {do_ring_gen_gc(table, ring_gen), pending_gcs}
      end

    {:reply, reply, %{state | pending_gcs: pending_gcs}}
  end

  def handle_info({:gc, ring_gen}, %{pending_gcs: pending_gcs, table: table} = state) do
    pending_gcs =
      case Map.pop(pending_gcs, ring_gen) do
        {nil, pending_gcs} ->
          pending_gcs

        {_stale_timer_ref, pending_gcs} ->
          do_ring_gen_gc(table, ring_gen)
          pending_gcs
      end

    {:noreply, %{state | pending_gcs: pending_gcs}}
  end

  defp rebuild(%{nodes: nodes, name: name, table: table, ring_gen: ring_gen} = state) do
    new_ring_gen = ring_gen + 1

    :ets.insert(
      table,
      for {hash, node} <- Utils.gen_items(nodes) do
        {{new_ring_gen, hash}, node}
      end
    )

    Config.set(name, self(), {table, new_ring_gen, length(nodes)})

    schedule_ring_gen_gc(%{state | ring_gen: new_ring_gen}, ring_gen)
  end

  def schedule_ring_gen_gc(state, 0), do: state

  def schedule_ring_gen_gc(%{pending_gcs: pending_gcs} = state, ring_gen) do
    ring_gen_gc_delay =
      Application.get_env(:hash_ring, :ring_gen_gc_delay, @default_ring_gen_gc_delay)

    timer_ref = Process.send_after(self(), {:gc, ring_gen}, ring_gen_gc_delay)
    %{state | pending_gcs: Map.put(pending_gcs, ring_gen, timer_ref)}
  end

  defp do_ring_gen_gc(table, ring_gen) do
    :ets.match_delete(table, {{ring_gen, :_}, :_})
    :ok
  end

  defp find_next_highest_item({_table, _ring_gen, 0}, _hash) do
    nil
  end

  defp find_next_highest_item({table, ring_gen, _num_nodes}, hash) do
    key =
      case :ets.next(table, {ring_gen, hash}) do
        {^ring_gen, _number} = key -> key
        _ -> :ets.next(table, {ring_gen, -1})
      end

    case :ets.lookup(table, key) do
      [{{^ring_gen, number}, node}] -> {number, node}
      _ -> nil
    end
  end

  defp has_node_with_name?(nodes, node_name) do
    Enum.any?(nodes, &match?({^node_name, _}, &1))
  end

  defp transform_nodes(nodes, default_num_replicas) do
    Enum.map(nodes, fn
      {_node, _num_replicas} = item -> item
      node -> {node, default_num_replicas}
    end)
  end
end
