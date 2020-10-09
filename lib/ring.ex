defmodule ExHashRing.Ring do
  use GenServer

  alias ExHashRing.{Config, Hash, Node, Settings, Utils}

  @compile {:inline,
            do_find_historical_nodes: 4,
            do_find_nodes_in_table: 6,
            do_find_nodes: 7,
            do_find_stable_nodes: 4,
            find_next_highest_item: 4,
            find_node: 2,
            find_nodes: 3,
            find_historical_node: 3,
            find_historical_nodes: 4,
            find_stable_nodes: 3,
            find_stable_nodes: 4}

  @typedoc """
  Any hashable key can be looked up in the ring to find the nodes that own that key.
  """
  @type key :: Hash.hashable()

  @typedoc """
  Rings maintain a history, the history is limited to depth number of generations to retain.
  """
  @type depth :: pos_integer()

  @typedoc """
  Rings are named with a unique atom.
  """
  @type name :: atom()

  @typedoc """
  Ring size is a memoized count of the number of logical nodes in a ring
  """
  @type size :: non_neg_integer()


  @type t :: %__MODULE__{
    depth: depth(),
    generation: Config.generation(),
    name: name(),
    nodes: [Node.t()],
    overrides: Config.override_map(),
    pending_gcs: %{Config.generation() => reference()},
    replicas: Node.replicas(),
    sizes: [size()],
    table: :ets.tid()
  }
  defstruct depth: Settings.get_depth(),
            generation: 0,
            name: nil,
            nodes: [],
            overrides: %{},
            pending_gcs: %{},
            replicas: Settings.get_replicas(),
            sizes: [],
            table: nil

  ## Client

  @doc """
  Start and link a Ring with the given name.

  Ring supports various options as outlined below.
  - :depth - Number of generations to retain for lookup. Defaults to #{Settings.get_depth()}
  - :named - Boolean that controls whether or not to register the process as a named process.  Defaults to false
  - :nodes - Initial nodes for the Ring.  Defaults to []
  - :overrides - Initial overrides for the Ring. Defaults to %{}
  - :replicas - Replicas to use for nodes that do not define replicas. Defaults to #{Settings.get_replicas}
  """
  @spec start_link(name(), options :: Keyword.t()) :: GenServer.on_start()
  def start_link(name, options \\ []) do
    default_options = [
      depth: Settings.get_depth(),
      named: false,
      nodes: [],
      overrides: %{},
      replicas: Settings.get_replicas(),
    ]

    options = Keyword.merge(default_options, options)

    gen_opts =
      if options[:named] do
        [name: name]
      else
        []
      end


    GenServer.start_link(__MODULE__, {name, options}, gen_opts)
  end

  @doc """
  Adds a node to the existing set of nodes in the ring.
  """
  @spec add_node(name(), Node.name(), Node.replicas) :: {:ok, [Node.t()]} | {:error, :node_exists}
  def add_node(name, node_name, num_replicas \\ nil)

  def add_node(name, node_name, nil) do
    GenServer.call(name, {:add_nodes, [node_name]})
  end

  def add_node(name, node_name, num_replicas) do
    GenServer.call(name, {:add_nodes, [{node_name, num_replicas}]})
  end

  @doc """
  Adds multiple nodes to the existing set of nodes in the ring.
  """
  @spec add_nodes(name(), nodes :: [Node.definition()]) :: {:ok, [Node.t()]} | {:error, :node_exists}
  def add_nodes(name, nodes) do
    GenServer.call(name, {:add_nodes, nodes})
  end

  @doc """
  Finds the node responsible for the given key in the specified ring.
  """
  @spec find_node(name(), key()) :: {:ok, Node.name()} | {:error, atom}
  def find_node(name, key) do
    with {:ok, [node]} <- find_nodes(name, key, 1)  do
      {:ok, node}
    end
  end

  @doc """
  Finds the specified number of nodes responsible for the given key in the specified ring's current generation.
  """
  @spec find_nodes(name(), key(), non_neg_integer()) :: {:ok, [Node.name()]} | {:error, atom}
  def find_nodes(name, key, num) do
    find_historical_nodes(name, key, num, 0)
  end

  @spec find_historical_node(name(), key(), back :: non_neg_integer()) :: {:ok, Node.name()} | {:error, atom}
  def find_historical_node(name, key, back) do
    with {:ok, [node]} <- find_historical_nodes(name, key, 1, back) do
      {:ok, node}
    end
  end

  @doc """
  Finds the specified number of nodes responsible for the given key in the specified ring's history, going back `back`
  number of generations.
  """
  @spec find_historical_nodes(name(), key(), num :: non_neg_integer(), back :: non_neg_integer()) :: {:ok, [Node.name()]} | {:error, atom}
  def find_historical_nodes(name, key, num, back) do
    with {:ok, config} <- Config.get(name) do
      do_find_historical_nodes(key, num, back, config)
    end
  end

  @doc """
  Finds the specificed number of nodes responsible for the given key by looking at each generation in the ring's
  configured depth.  See `find_stable_nodes/4` for more information.
  """
  @spec find_stable_nodes(name(), key(), num :: non_neg_integer()) :: {:ok, [Node.name()]} | {:error, atom}
  def find_stable_nodes(name, key, num) do
    with {:ok, {_table, depth, _sizes, _generation, _overrides} = config} <- Config.get(name) do
      do_find_stable_nodes(key, num, depth, config)
    end
  end

  @doc """
  Finds the specified number of nodes responsible for the given key in the specified ring's current generation and in
  the history of the ring.  This means that this function returns up to `back` * `num`; where `num` = number of nodes
  requested, and `back` = the number of generations to consider
  """
  @spec find_stable_nodes(name(), key(), num :: non_neg_integer(), back :: pos_integer()) :: {:ok, [Node.name()]} | {:error, atom}
  def find_stable_nodes(name, key, num, back) do
    with {:ok, config} <- Config.get(name) do
      do_find_stable_nodes(key, num, back, config)
    end
  end

  @doc """
  Forces a garbage collection of any generations that are pending garbage collection. Returns the generations that were
  collected.
  """
  @spec force_gc(name()) :: {:ok, [Config.generation()]}
  def force_gc(name) do
    GenServer.call(name, :force_gc)
  end

  @doc """
  Forces a garbage collection of a specific generation, the generation must be pending or else {:error, :not_pending}
  is returned.
  """
  @spec force_gc(name(), Config.generation()) :: :ok | {:error, :not_pending}
  def force_gc(name, generation) do
    GenServer.call(name, {:force_gc, generation})
  end



  @doc """
  Get the current ring generation
  """
  @spec get_generation(name()) :: {:ok, Config.generation()} | :error
  def get_generation(name) do
    with {:ok, {_table, _depth, _sizes, generation, _overrides}} <- Config.get(name) do
      {:ok, generation}
    end
  end

  @doc """
  Retrieves the current set of node names from the ring.
  """
  @spec get_nodes(name()) :: {:ok, [Node.name()]}
  def get_nodes(name) do
    GenServer.call(name, :get_nodes)
  end

  @doc """
  Retrieves the current set of nodes as tuples of {name, replicas} from the ring.
  """
  @spec get_nodes_with_replicas(name()) :: {:ok, [Node.t()]}
  def get_nodes_with_replicas(name) do
    GenServer.call(name, :get_nodes_with_replicas)
  end

  @doc """
  Retrieves the current set of overrides from the ring.
  """
  @spec get_overrides(name()) :: {:ok, Config.override_map()}
  def get_overrides(name) do
    GenServer.call(name, :get_overrides)
  end

  @doc """
  Stops the GenServer holding the Ring.
  """
  @spec stop(name :: atom()) :: :ok
  def stop(name) do
    GenServer.stop(name)
  end


  @doc """
  Removes a node from the ring by its name.
  """
  @spec remove_node(name(), Node.name()) :: {:ok, [Node.t()]} | {:error, :node_not_exists}
  def remove_node(name, node_name) do
    GenServer.call(name, {:remove_nodes, [node_name]})
  end

  @doc """
  Atomically remove multiple nodes from the ring by name
  """
  @spec remove_nodes(name(), [Node.name()]) :: {:ok, [Node.t()]} | {:error, :node_not_exists}
  def remove_nodes(name, node_names) do
    GenServer.call(name, {:remove_nodes, node_names})
  end

  @doc """
  Replaces the nodes in the ring with a new set of nodes.
  """
  @spec set_nodes(name(), [Node.definition()]) :: {:ok, [Node.t()]}
  def set_nodes(name, node_names) do
    GenServer.call(name, {:set_nodes, node_names})
  end

  @doc """
  Replaces the overrides in the ring with a new override map.
  """
  @spec set_overrides(name(), Config.override_map()) :: {:ok, Config.override_map()}
  def set_overrides(name, overrides) do
    GenServer.call(name, {:set_overrides, overrides})
  end

  @doc """
  Schedulers a generation for garbage collection
  """
  @spec schedule_gc(state :: t(), Config.generation()) :: t()
  def schedule_gc(%__MODULE__{} = state, generation) do
    pending_gcs =
      Map.put_new_lazy(state.pending_gcs, generation, fn ->
        Process.send_after(self(), {:gc, generation}, Settings.get_gc_delay())
      end)

    %__MODULE__{state | pending_gcs: pending_gcs}
  end


  ## Server

  @spec init({name :: name(), options :: Keyword.t()}) :: {:ok, t()}
  def init({name, options}) do
    table =
      :ets.new(:ring, [
        :protected,
        :ordered_set,
        {:read_concurrency, true}
      ])

    state = %__MODULE__{
      depth: options[:depth],
      name: name,
      table: table,
      replicas: options[:replicas],
    }

    nodes = Node.normalize(options[:nodes], options[:replicas])

    state =
      state
      |> update_nodes(nodes)
      |> update_overrides(options[:overrides])

    {:ok, state}
  end

  def handle_call({:set_nodes, nodes}, _from, %__MODULE__{} = state) do
    nodes = Node.normalize(nodes, state.replicas)
    {:reply, {:ok, nodes}, update_nodes(state, nodes)}
  end

  def handle_call({:add_nodes, nodes}, _from, %__MODULE__{} = state) do
    nodes = Node.normalize(nodes, state.replicas)

    has_existing_nodes? = Enum.any?(nodes, fn {name, _} ->
      has_node_with_name?(state.nodes, name)
    end)

    if has_existing_nodes? do
      {:reply, {:error, :node_exists}, state}
    else
      nodes = nodes ++ state.nodes
      {:reply, {:ok, nodes}, update_nodes(state, nodes)}
    end
  end

  def handle_call({:remove_nodes, node_names}, _from, %__MODULE__{} = state) do
    has_unknown_nodes? = Enum.any?(node_names, fn name ->
      not has_node_with_name?(state.nodes, name)
    end)

    if has_unknown_nodes? do
      {:reply, {:error, :node_not_exists}, state}
    else
      nodes = Enum.reject(state.nodes, fn {name, _} -> name in node_names end)
      {:reply, {:ok, nodes}, update_nodes(state, nodes)}
    end
  end

  def handle_call({:set_overrides, overrides}, _from, state) do
    {:reply, {:ok, overrides}, update_overrides(state, overrides)}
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

  def handle_call(:force_gc, _from, %__MODULE__{} = state) do
    generations =
      for {generation, timer_ref} <- state.pending_gcs do
        Process.cancel_timer(timer_ref)
        :ok = do_gc(state.table, generation)
        generation
      end

    {:reply, {:ok, generations}, %__MODULE__{state | pending_gcs: %{}}}
  end

  def handle_call({:force_gc, generation}, _from, %__MODULE__{} = state) do
    {reply, pending_gcs} =
      case Map.pop(state.pending_gcs, generation) do
        {nil, pending_gcs} ->
          {{:error, :not_pending}, pending_gcs}

        {timer_ref, pending_gcs} ->
          Process.cancel_timer(timer_ref)
          :ok = do_gc(state.table, generation)
          {:ok, pending_gcs}
      end

    {:reply, reply, %__MODULE__{state | pending_gcs: pending_gcs}}
  end

  def handle_info({:gc, generation}, %__MODULE__{} = state) do
    pending_gcs =
      case Map.pop(state.pending_gcs, generation) do
        {nil, pending_gcs} ->
          pending_gcs

        {_stale_timer_ref, pending_gcs} ->
          :ok = do_gc(state.table, generation)
          pending_gcs
      end

    {:noreply, %__MODULE__{state | pending_gcs: pending_gcs}}
  end

  ## Private

  @spec do_find_historical_nodes(
    key(),
    num :: non_neg_integer(),
    back :: non_neg_integer(),
    config :: Config.config()
  ) :: {:ok, [Node.name()]} | {:error, atom()}
  defp do_find_historical_nodes(key, num, back, config) do
    {table, _depth, sizes, generation, overrides} = config

    case Enum.at(sizes, back) do
      nil ->
        {:ok, []}

      size ->
        do_find_nodes_in_table(key, table, overrides, generation - back, size, num)
    end
  end

  @spec do_find_nodes(
    table :: :ets.tid(),
    generation :: Config.generation(),
    size :: size(),
    remaining :: non_neg_integer(),
    hash :: Hash.t(),
    found :: [Node.name()],
    found_length :: non_neg_integer()
  ) :: [Node.name()]
  defp do_find_nodes(_table, _generation, _size, 0, _hash, found, _found_length) do
    # Remaining is now 0, all the requested nodes have been found
    Enum.reverse(found)
  end

  defp do_find_nodes(_table, _generation, size, _remaining, _hash, found, size) do
    # Number of found nodes and number of nodes in the ring are equal, further processing will yield no additional results
    Enum.reverse(found)
  end

  defp do_find_nodes(table, generation, size, remaining, hash, found, found_length) do
    {next_highest_hash, name} = find_next_highest_item(table, generation, size, hash)

    {remaining, found, found_length} =
      if name in found do
        # This node is already in the result set, skip it
        {remaining, found, found_length}
      else
        # Add node to the result set and decrement remaining
        {remaining - 1, [name | found], found_length + 1}
      end

    # Continue from the next_highest_hash
    do_find_nodes(table, generation, size, remaining, next_highest_hash, found, found_length)
  end

  @spec do_find_nodes_in_table(
    key :: key(),
    table :: :ets.tid(),
    overrides :: Config.override_map(),
    gen :: Config.generation(),
    num_nodes :: Config.num_nodes(),
    num :: non_neg_integer()
  ) :: {:ok, [binary]} | {:error, term}
  defp do_find_nodes_in_table(_key, _table, _overrides, _gen, 0, _num) do
    {:error, :invalid_ring}
  end

  defp do_find_nodes_in_table(_key, _table, _overrides, _gen, _num_nodes, 0) do
    {:ok, []}
  end

  defp do_find_nodes_in_table(key, table, overrides, gen, num_nodes, num) when map_size(overrides) == 0 do
    {:ok, do_find_nodes(table, gen, num_nodes, num, Hash.of(key), [], 0)}
  end

  defp do_find_nodes_in_table(key, table, overrides, gen, num_nodes, num) do
    {found, found_length} =
      case overrides do
        %{^key => overrides} ->
          Utils.take_max(overrides, num)

        _ ->
          {[], 0}
      end

    {:ok, do_find_nodes(table, gen, num_nodes, max(num - found_length, 0), Hash.of(key), found, found_length)}
  end

  @spec do_find_stable_nodes(
    key(),
    num :: non_neg_integer(),
    back :: non_neg_integer(),
    config :: Config.config()
  ) :: {:ok, [Node.name()]} | {:error, atom()}
  def do_find_stable_nodes(key, num, back, config) do
    stable_nodes =
      Enum.reduce_while(0..back, {:ok, []}, fn back, {:ok, acc} ->
        with {:ok, nodes} <- do_find_historical_nodes(key, num, back, config) do
          acc =
            Enum.reduce(nodes, acc, fn node, acc ->
              if node in acc do
                acc
              else
                [node | acc]
              end
            end)
          {:cont, {:ok, acc}}
        else
          error ->
            {:halt, error}
        end
      end)

    with {:ok, nodes} <- stable_nodes do
      {:ok, Enum.reverse(nodes)}
    end
  end

  @spec do_gc(table :: :ets.tid(), generation :: Config.generation()) :: :ok
  defp do_gc(table, generation) do
    :ets.match_delete(table, {{generation, :_}, :_})
    :ok
  end

  @spec find_next_highest_item(table :: :ets.tid, generation :: Config.generation(), size(), hash :: Hash.t()) :: Node.virtual()
  defp find_next_highest_item(_table, _generation, 0, _hash) do
    nil
  end

  defp find_next_highest_item(table, generation, _size, hash) do
    key =
      case :ets.next(table, {generation, hash}) do
        {^generation, _hash} = key ->
          key

        _ ->
          # Generation is exhausted, start back up at the top of this generation.
          :ets.next(table, {generation, -1})
      end

    case :ets.lookup(table, key) do
      [{{^generation, hash}, name}] ->
        {hash, name}

      _ ->
        nil
    end
  end

  @spec has_node_with_name?(nodes :: [Node.t()], name :: Node.name()) :: boolean()
  defp has_node_with_name?(nodes, name) do
    Enum.any?(nodes, &match?({^name, _}, &1))
  end

  @spec update_nodes(state :: t(), nodes :: [Node.t()]) :: t()
  defp update_nodes(%__MODULE__{} = state, nodes) do
    next_generation = state.generation + 1

    # Generate items for the next generation
    items =
      nodes
      |> Node.expand()
      |> Enum.map(fn {hash, name} ->
        {{next_generation, hash}, name}
      end)

    # Write the items into the table for this generation
    :ets.insert(state.table, items)

    # Add the new size to the sizes
    sizes = [Enum.count(nodes) | state.sizes]

    # Truncate sizes to fit into depth
    sizes = Enum.take(sizes, state.depth)

    # Update the configuration to atomically cut over to the new generation
    config = {
      state.table,
      state.depth,
      sizes,
      next_generation,
      state.overrides
    }

    Config.set(state.name, self(), config)

    # Schedule the stale generation for cleanup
    state = schedule_gc(state, next_generation - state.depth)

    # Update and return the state
    %__MODULE__{state | generation: next_generation, nodes: nodes, sizes: sizes}
  end

  @spec update_overrides(state :: t(), overrides :: Config.override_map()) :: t()
  defp update_overrides(%__MODULE__{} = state, overrides) do
    # Remove any empty overrides
    overrides =
      Enum.reduce(overrides, %{}, fn
        {_, []}, acc ->
          acc

        {k, v}, acc ->
          Map.put(acc, k, v)
      end)

    # Update the current configuration
    {:ok, {table, depth, sizes, generation, _overrides}} = Config.get(state.name)
    Config.set(state.name, self(), {table, depth, sizes, generation, overrides})

    # Update and return the state
    %__MODULE__{state | overrides: overrides}
  end
end
