defmodule ExHashRing.HashRing.ETS do
  @compile {:inline,
            do_find_nodes: 6,
            find_next_highest_item: 4,
            find_node_inner: 4,
            find_node: 2,
            find_nodes: 3,
            find_override: 2}

  @default_num_replicas 512
  @default_ring_gen_gc_delay 10_000

  @type t :: __MODULE__
  @type override_map :: %{atom => binary}

  use GenServer

  alias ExHashRing.HashRing.Utils
  alias ExHashRing.HashRing.ETS.Config

  defstruct default_num_replicas: @default_num_replicas,
            nodes: [],
            overrides: %{},
            table: nil,
            ring_gen: 0,
            name: nil,
            pending_gcs: %{}

  def start_link(name, opts \\ []) do
    named = Keyword.get(opts, :named, false)
    nodes = Keyword.get(opts, :nodes, [])
    overrides = Keyword.get(opts, :overrides, %{})
    num_replicas = Keyword.get(opts, :default_num_replicas, @default_num_replicas)

    gen_opts =
      if named do
        [name: name]
      else
        []
      end

    GenServer.start_link(__MODULE__, {name, nodes, num_replicas, overrides}, gen_opts)
  end

  @spec init({atom, [binary], integer, override_map}) :: {:ok, t}
  def init({name, nodes, default_num_replicas, overrides}) do
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
        overrides: overrides,
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

  @spec remove_node(atom, binary) :: {:ok, [{binary, integer}]} | {:error, :node_not_exists}
  def remove_node(name, node_name) do
    GenServer.call(name, {:remove_node, node_name})
  end

  @spec set_overrides(atom, override_map) :: {:ok, override_map}
  def set_overrides(name, overrides) do
    GenServer.call(name, {:set_overrides, overrides})
  end

  @spec get_overrides(atom) :: {:ok, override_map}
  def get_overrides(name) do
    GenServer.call(name, :get_overrides)
  end

  @spec get_nodes(atom) :: {:ok, [binary]}
  def get_nodes(name) do
    GenServer.call(name, :get_nodes)
  end

  @spec get_nodes_with_replicas(atom) :: {:ok, [{binary, integer}]}
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
    case Config.get(name) do
      {:ok, {_, ring_gen, _}} -> {:ok, ring_gen}
      {:ok, {_, ring_gen, _, _}} -> {:ok, ring_gen}
      x -> x
    end
  end

  @spec find_node(atom, binary | integer) :: {:ok, binary} | {:error, atom}
  def find_node(name, key) do
    case Config.get(name) do
      {:ok, {table, gen, num_nodes}} when num_nodes > 0 ->
        find_node_inner(table, gen, num_nodes, key)

      {:ok, {table, gen, num_nodes, overrides}} when num_nodes > 0 ->
        if override = find_override(overrides, key) do
          {:ok, override}
        else
          find_node_inner(table, gen, num_nodes, key)
        end

      {:error, error} ->
        {:error, error}

      _ ->
        {:error, :invalid_ring}
    end
  end

  defp find_node_inner(table, gen, num_nodes, key) do
    hash = Utils.hash(key)

    case find_next_highest_item(table, gen, num_nodes, hash) do
      {_, node} -> {:ok, node}
      _ -> {:error, :invalid_ring}
    end
  end

  @spec find_nodes(atom, binary | integer, integer) :: {:ok, [binary]} | {:error, atom}
  def find_nodes(name, key, num) do
    hash = Utils.hash(key)

    case Config.get(name) do
      {:ok, {table, gen, num_nodes}} when num_nodes > 0 ->
        nodes = do_find_nodes(table, gen, num_nodes, min(num, num_nodes), hash, [])

        {:ok, nodes}

      {:ok, {table, gen, num_nodes, overrides}} when num_nodes > 0 and num > 0 ->
        nodes = do_find_nodes(table, gen, num_nodes, min(num, num_nodes), hash, [])

        if override = find_override(overrides, key) do
          nodes = ([override] ++ (nodes -- [override])) |> Enum.take(num)

          {:ok, nodes}
        else
          {:ok, nodes}
        end

      {:ok, {_, _, num_nodes, _}} when num_nodes > 0 ->
        {:ok, []}

      {:error, error} ->
        {:error, error}

      _ ->
        {:error, :invalid_ring}
    end
  end

  ## Private

  defp do_find_nodes(_table, _gen, _num_nodes, 0, _hash, nodes) do
    Enum.reverse(nodes)
  end

  defp do_find_nodes(table, gen, num_nodes, remaining, hash, nodes) do
    {number, node} = find_next_highest_item(table, gen, num_nodes, hash)

    if node in nodes do
      do_find_nodes(table, gen, num_nodes, remaining, number, nodes)
    else
      do_find_nodes(table, gen, num_nodes, remaining - 1, number, [node | nodes])
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

  def handle_call({:set_overrides, overrides}, _from, state) do
    {:reply, {:ok, overrides}, rebuild(%{state | overrides: overrides})}
  end

  def handle_call(:get_overrides, _from, %{overrides: overrides} = state) do
    {:reply, {:ok, overrides}, state}
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

  defp rebuild(
         %{nodes: nodes, name: name, table: table, ring_gen: ring_gen, overrides: overrides} =
           state
       ) do
    new_ring_gen = ring_gen + 1

    :ets.insert(
      table,
      for {hash, node} <- Utils.gen_items(nodes) do
        {{new_ring_gen, hash}, node}
      end
    )

    config =
      if map_size(overrides) > 0 do
        {table, new_ring_gen, length(nodes), overrides}
      else
        {table, new_ring_gen, length(nodes)}
      end

    Config.set(name, self(), config)

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

  def find_override(overrides, key) do
    case overrides do
      %{^key => value} -> value
      _ -> nil
    end
  end

  defp find_next_highest_item(_table, _ring_gen, 0, _hash) do
    nil
  end

  defp find_next_highest_item(table, ring_gen, _num_nodes, hash) do
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
