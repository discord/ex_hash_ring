defmodule ExHashRing.Ring do
  @moduledoc """
  A pure Elixir consistent hash ring.

  Ring data is stored in an ETS table owned by the ExHashRing.Ring GenServer.  This module
  provides functions for managing and querying a consistent hash ring quickly and efficiently.
  """
  use GenServer

  alias ExHashRing.{Configuration, Hash, Info, Node, Utils}

  @compile {:inline,
            do_find_historical_nodes: 5,
            do_find_nodes_in_table: 7,
            do_find_nodes: 7,
            do_find_stable_nodes: 5,
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
  Generations act as a grouping mechanism to associate many records together as one logical and
  atomic group.
  """
  @type generation :: integer()

  @typedoc """
  Rings are named with a unique atom.
  """
  @type name :: atom()

  @typedoc """
  Option that controls the number of generations to retain for lookup.

  Defaults to #{Configuration.get_depth()}
  """
  @type option_depth :: {:depth, depth()}

  @typedoc """
  Option that controls the name to register this process under, Rings that are registered can use
  their name in place of their pid.

  Defaults behavior is to not register the Ring process.
  """
  @type option_name :: {:name, name()}

  @typedoc """
  Option that controls the initial nodes for the Ring.

  Defaults to []
  """
  @type option_nodes :: {:nodes, [Node.definition()]}

  @typedoc """
  Option that controls the initial overrides for the Ring.

  Defaults to %{}
  """
  @type option_overrides :: {:overrides, overrides()}

  @typedoc """
  Option that controls the number of replicas to use for nodes that do not define replicas.

  Defaults to #{Configuration.get_replicas()}
  """
  @type option_replicas :: {:replicas, Node.replicas()}

  @typedoc """
  Union type that represents all valid options
  """
  @type option :: option_depth | option_name | option_nodes | option_overrides | option_replicas

  @typedoc """
  List of options that can be provided when starting a Ring, see the `t:option/0` type and its
  associated types for more information.
  """
  @type options :: [option]

  @typedoc """
  Overrides allow the Ring to always resolve a given key to a set list of nodes.
  """
  @type overrides :: %{key() => [Node.name()]}

  @typedoc """
  Several functions accept either a name for a named Ring or a pid for an anonymous Ring
  """
  @type ring :: name | pid()

  @typedoc """
  Ring size is a memoized count of the number of logical nodes in a ring
  """
  @type size :: non_neg_integer()

  @type t :: %__MODULE__{
          depth: depth(),
          generation: generation(),
          nodes: [Node.t()],
          overrides: overrides(),
          pending_gcs: %{generation() => reference()},
          replicas: Node.replicas(),
          sizes: [size()],
          table: :ets.tid()
        }
  defstruct depth: Configuration.get_depth(),
            generation: 0,
            nodes: [],
            overrides: %{},
            pending_gcs: %{},
            replicas: Configuration.get_replicas(),
            sizes: [],
            table: nil

  ## Client

  @doc """
  Start and link a Ring with the given name.

  Ring supports various options see `t:options/0` for more information.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options \\ []) do
    default_options = [
      depth: Configuration.get_depth(),
      nodes: [],
      overrides: %{},
      replicas: Configuration.get_replicas()
    ]

    options = Keyword.merge(default_options, options)

    gen_opts =
      if options[:name] do
        [name: options[:name]]
      else
        []
      end

    GenServer.start_link(__MODULE__, options, gen_opts)
  end

  @doc """
  Adds a node to the existing set of nodes in the ring.
  """
  @spec add_node(ring(), Node.name(), Node.replicas() | nil, timeout :: timeout()) ::
          {:ok, [Node.t()]} | {:error, :node_exists}
  def add_node(ring, node_name, num_replicas \\ nil, timeout \\ 5000)

  def add_node(ring, node_name, nil, timeout) do
    GenServer.call(ring, {:add_nodes, [node_name]}, timeout)
  end

  def add_node(ring, node_name, num_replicas, timeout) do
    GenServer.call(ring, {:add_nodes, [{node_name, num_replicas}]}, timeout)
  end

  @doc """
  Adds multiple nodes to the existing set of nodes in the ring.
  """
  @spec add_nodes(ring(), nodes :: [Node.definition()], timeout :: timeout()) ::
          {:ok, [Node.t()]} | {:error, :node_exists}
  def add_nodes(ring, nodes, timeout \\ 5000) do
    GenServer.call(ring, {:add_nodes, nodes}, timeout)
  end

  @doc """
  Finds the node responsible for the given key in the specified ring.
  """
  @spec find_node(ring(), key()) :: {:ok, Node.name()} | {:error, atom}
  def find_node(ring, key) do
    with {:ok, [node]} <- find_nodes(ring, key, 1) do
      {:ok, node}
    end
  end

  @doc """
  Finds the specified number of nodes responsible for the given key in the specified ring's
  current generation.
  """
  @spec find_nodes(ring(), key(), num :: non_neg_integer()) ::
          {:ok, [Node.name()]} | {:error, reason :: atom()}
  def find_nodes(ring, key, num) do
    find_historical_nodes(ring, key, num, 0)
  end

  @spec find_historical_node(ring(), key(), back :: non_neg_integer()) ::
          {:ok, Node.name()} | {:error, atom}
  def find_historical_node(ring, key, back) do
    with {:ok, [node]} <- find_historical_nodes(ring, key, 1, back) do
      {:ok, node}
    end
  end

  @doc """
  Finds the specified number of nodes responsible for the given key in the specified ring's
  history, going back `back` number of generations.
  """
  @spec find_historical_nodes(ring(), key(), num :: non_neg_integer(), back :: non_neg_integer()) ::
          {:ok, [Node.name()]} | {:error, atom}
  def find_historical_nodes(ring, key, num, back) do
    with {:ok, info} <- Info.get(ring),
         hash = Hash.of(key),
         {:ok, nodes} <- do_find_historical_nodes(key, hash, num, back, info) do
      {:ok, Enum.reverse(nodes)}
    end
  end

  @doc """
  Finds the specificed number of nodes responsible for the given key by looking at each generation
  in the ring's configured depth.  See `find_stable_nodes/4` for more information.
  """
  @spec find_stable_nodes(ring(), key(), num :: non_neg_integer()) ::
          {:ok, [Node.name()]} | {:error, atom}
  def find_stable_nodes(ring, key, num) do
    with {:ok, {_table, depth, _sizes, _generation, _overrides} = info} <- Info.get(ring),
         hash = Hash.of(key),
         {:ok, nodes} <- do_find_stable_nodes(key, hash, num, depth, info) do
      {:ok, Enum.reverse(nodes)}
    end
  end

  @doc """
  Finds the specified number of nodes responsible for the given key in the specified ring's
  current generation and in the history of the ring.  This means that this function returns up to
  `back` * `num`; where `num` = number of nodes requested, and `back` = the number of generations
  to consider.
  """
  @spec find_stable_nodes(ring(), key(), num :: non_neg_integer(), back :: pos_integer()) ::
          {:ok, [Node.name()]} | {:error, atom}
  def find_stable_nodes(ring, key, num, back) do
    with {:ok, info} <- Info.get(ring),
         hash = Hash.of(key),
         {:ok, nodes} <- do_find_stable_nodes(key, hash, num, back, info) do
      {:ok, Enum.reverse(nodes)}
    end
  end

  @doc """
  Forces a garbage collection of any generations that are pending garbage collection. Returns the
  generations that were collected.

  This is equivalent to `force_gc(ring, :pending)`.
  """
  @spec force_gc(ring()) :: {:ok, [generation()]}
  def force_gc(ring) do
    force_gc(ring, :pending)
  end

  @doc """
  Forces a garbage collection of a specific generation, all generations pending garbage collection
  if `:pending` is specified. If a specific generation is specified, the it must be pending or
  else `{:error, :not_pending}` is returned.
  """
  @spec force_gc(ring(), generation() | :pending, timeout :: timeout()) ::
          :ok | {:error, :not_pending}
  def force_gc(ring, generation, timeout \\ 5000) do
    case generation do
      :pending ->
        GenServer.call(ring, :force_gc, timeout)

      generation ->
        GenServer.call(ring, {:force_gc, generation}, timeout)
    end
  end

  @doc """
  Get the current ring generation
  """
  @spec get_generation(ring()) :: {:ok, generation()} | :error
  def get_generation(ring) do
    with {:ok, {_table, _depth, _sizes, generation, _overrides}} <- Info.get(ring) do
      {:ok, generation}
    end
  end

  @doc """
  Retrieves the current set of node names from the ring.
  """
  @spec get_nodes(ring(), timeout :: timeout()) :: {:ok, [Node.name()]}
  def get_nodes(ring, timeout \\ 5000) do
    GenServer.call(ring, :get_nodes, timeout)
  end

  @doc """
  Retrieves the current set of nodes as tuples of {name, replicas} from the ring.
  """
  @spec get_nodes_with_replicas(ring(), timeout :: timeout()) :: {:ok, [Node.t()]}
  def get_nodes_with_replicas(ring, timeout \\ 5000) do
    GenServer.call(ring, :get_nodes_with_replicas, timeout)
  end

  @doc """
  Retrieves the current set of overrides from the ring.
  """
  @spec get_overrides(ring(), timeout :: timeout()) :: {:ok, overrides()}
  def get_overrides(ring, timeout \\ 5000) do
    GenServer.call(ring, :get_overrides, timeout)
  end

  @doc """
  Retrieves a list of pending gc generations.
  """
  @spec get_pending_gcs(ring(), timeout :: timeout()) :: {:ok, [generation()]}
  def get_pending_gcs(ring, timeout \\ 5000) do
    GenServer.call(ring, :get_pending_gcs, timeout)
  end

  @doc """
  Stops the GenServer holding the Ring.
  """
  @spec stop(ring()) :: :ok
  def stop(name) do
    GenServer.stop(name)
  end

  @doc """
  Removes a node from the ring by its name.
  """
  @spec remove_node(ring(), name :: Node.name(), timeout :: timeout()) ::
          {:ok, [Node.t()]} | {:error, :node_not_exists}
  def remove_node(ring, name, timeout \\ 5000) do
    GenServer.call(ring, {:remove_nodes, [name]}, timeout)
  end

  @doc """
  Atomically remove multiple nodes from the ring by name
  """
  @spec remove_nodes(ring(), names :: [Node.name()]) ::
          {:ok, [Node.t()]} | {:error, :node_not_exists}
  def remove_nodes(ring, names, timeout \\ 5000) do
    GenServer.call(ring, {:remove_nodes, names}, timeout)
  end

  @doc """
  Replaces the nodes in the ring with a new set of nodes.
  """
  @spec set_nodes(ring(), nodes :: [Node.definition()], timeout :: timeout()) ::
          {:ok, [Node.t()]}
  def set_nodes(ring, nodes, timeout \\ 5000) do
    GenServer.call(ring, {:set_nodes, nodes}, timeout)
  end

  @doc """
  Replaces the overrides in the ring with new overrides.
  """
  @spec set_overrides(ring(), overrides(), timeout :: timeout()) :: {:ok, overrides()}
  def set_overrides(ring, overrides, timeout \\ 5000) do
    GenServer.call(ring, {:set_overrides, overrides}, timeout)
  end

  ## Server

  @spec init(options()) :: {:ok, t()}
  def init(options) do
    table =
      :ets.new(:ring, [
        :protected,
        :ordered_set,
        {:read_concurrency, true}
      ])

    state = %__MODULE__{
      depth: options[:depth],
      table: table,
      replicas: options[:replicas]
    }

    nodes = Node.normalize(options[:nodes], options[:replicas])

    state =
      state
      |> update_nodes(nodes)
      |> update_overrides(options[:overrides])

    {:ok, state}
  end

  def handle_call({:add_nodes, nodes}, _from, %__MODULE__{} = state) do
    nodes = Node.normalize(nodes, state.replicas)

    has_existing_nodes? =
      Enum.any?(nodes, fn {name, _} ->
        has_node_with_name?(state.nodes, name)
      end)

    if has_existing_nodes? do
      {:reply, {:error, :node_exists}, state}
    else
      nodes = nodes ++ state.nodes
      {:reply, {:ok, nodes}, update_nodes(state, nodes)}
    end
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

  def handle_call(:get_overrides, _from, %{overrides: overrides} = state) do
    {:reply, {:ok, overrides}, state}
  end

  def handle_call(:get_nodes, _from, %{nodes: nodes} = state) do
    nodes = for {name, _} <- nodes, do: name
    {:reply, {:ok, nodes}, state}
  end

  def handle_call(:get_nodes_with_replicas, _from, %{nodes: nodes} = state) do
    {:reply, {:ok, nodes}, state}
  end

  def handle_call(:get_pending_gcs, _from, %__MODULE__{} = state) do
    {:reply, {:ok, Map.keys(state.pending_gcs)}, state}
  end

  def handle_call({:remove_nodes, names}, _from, %__MODULE__{} = state) do
    has_unknown_nodes? =
      Enum.any?(names, fn name ->
        not has_node_with_name?(state.nodes, name)
      end)

    if has_unknown_nodes? do
      {:reply, {:error, :node_not_exists}, state}
    else
      nodes = Enum.reject(state.nodes, fn {name, _} -> name in names end)
      {:reply, {:ok, nodes}, update_nodes(state, nodes)}
    end
  end

  def handle_call({:set_nodes, nodes}, _from, %__MODULE__{} = state) do
    nodes = Node.normalize(nodes, state.replicas)
    {:reply, {:ok, nodes}, update_nodes(state, nodes)}
  end

  def handle_call({:set_overrides, overrides}, _from, state) do
    {:reply, {:ok, overrides}, update_overrides(state, overrides)}
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
          hash :: Hash.t(),
          num :: non_neg_integer(),
          back :: non_neg_integer(),
          info :: Info.entry()
        ) :: {:ok, [Node.name()]} | {:error, atom()}
  defp do_find_historical_nodes(key, hash, num, back, info) do
    {table, _depth, sizes, generation, overrides} = info

    case Enum.at(sizes, back) do
      nil ->
        {:error, :invalid_ring}

      size ->
        do_find_nodes_in_table(key, hash, table, overrides, generation - back, size, num)
    end
  end

  @spec do_find_nodes(
          table :: :ets.tid(),
          generation(),
          size(),
          remaining :: non_neg_integer(),
          hash :: Hash.t(),
          found :: [Node.name()],
          found_length :: non_neg_integer()
        ) :: [Node.name()]
  defp do_find_nodes(_table, _generation, _size, 0, _hash, found, _found_length) do
    # Remaining is now 0, all the requested nodes have been found
    found
  end

  defp do_find_nodes(_table, _generation, size, _remaining, _hash, found, size) do
    # Number of found nodes and number of nodes in the ring are equal, further processing will
    # yield no additional results
    found
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
          key(),
          hash :: Hash.t(),
          table :: :ets.tid(),
          overrides(),
          generation(),
          size(),
          num :: non_neg_integer()
        ) :: {:ok, [binary]} | {:error, term}
  defp do_find_nodes_in_table(_key, _hash, _table, _overrides, _generation, 0, _num) do
    {:error, :invalid_ring}
  end

  defp do_find_nodes_in_table(_key, _hash, _table, _overrides, _generation, _size, 0) do
    {:ok, []}
  end

  defp do_find_nodes_in_table(_key, hash, table, overrides, generation, size, num)
       when map_size(overrides) == 0 do
    {:ok, do_find_nodes(table, generation, size, num, hash, [], 0)}
  end

  defp do_find_nodes_in_table(key, hash, table, overrides, generation, size, num) do
    {found_overrides, found_overrides_length} =
      case overrides do
        %{^key => overrides} ->
          Utils.take_max(overrides, num)

        _ ->
          {[], 0}
      end

    cond do
      found_overrides_length == num ->
        {:ok, found_overrides}

      found_overrides_length == 0 ->
        {:ok, do_find_nodes(table, generation, size, num, hash, [], 0)}

      true ->
        ring_nodes =
          do_find_nodes(table, generation, size, num, hash, [], 0)
          |> Enum.reject(&(&1 in found_overrides))

        # The lists are in reverse order. The ones we want are at the end
        {:ok, Enum.take(ring_nodes ++ found_overrides, -num)}
    end
  end

  @spec do_find_stable_nodes(
          key(),
          hash :: Hash.t(),
          num :: non_neg_integer(),
          back :: non_neg_integer(),
          info :: Info.entry()
        ) :: {:ok, [Node.name()]} | {:error, atom()}
  def do_find_stable_nodes(key, hash, num, back, info) do
    Enum.reduce(0..(back - 1), {:error, :invalid_ring}, fn
      back, {:error, :invalid_ring} ->
        do_find_historical_nodes(key, hash, num, back, info)

      back, {:ok, acc} ->
        case do_find_historical_nodes(key, hash, num, back, info) do
          {:ok, nodes} ->
            acc =
              nodes
              |> Enum.reverse()
              |> Enum.reduce(acc, fn node, acc ->
                if node in acc do
                  acc
                else
                  [node | acc]
                end
              end)

            {:ok, acc}

          _ ->
            {:ok, acc}
        end
    end)
  end

  @spec do_gc(table :: :ets.tid(), generation()) :: :ok
  defp do_gc(table, generation) do
    :ets.match_delete(table, {{generation, :_}, :_})
    :ok
  end

  @spec find_next_highest_item(table :: :ets.tid(), generation(), size(), hash :: Hash.t()) ::
          Node.virtual()
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

  @spec schedule_gc(state :: t(), generation()) :: t()
  defp schedule_gc(%__MODULE__{} = state, generation) when generation <= 0 do
    state
  end

  defp schedule_gc(%__MODULE__{} = state, generation) do
    pending_gcs =
      Map.put_new_lazy(state.pending_gcs, generation, fn ->
        Process.send_after(self(), {:gc, generation}, Configuration.get_gc_delay())
      end)

    %__MODULE__{state | pending_gcs: pending_gcs}
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

    # Update the information to atomically cut over to the new generation
    entry = {
      state.table,
      state.depth,
      sizes,
      next_generation,
      state.overrides
    }

    Info.set(self(), entry)

    # Schedule the stale generation for cleanup
    state = schedule_gc(state, next_generation - state.depth)

    # Update and return the state
    %__MODULE__{state | generation: next_generation, nodes: nodes, sizes: sizes}
  end

  @spec update_overrides(state :: t(), overrides()) :: t()
  defp update_overrides(%__MODULE__{} = state, overrides) do
    # Remove any empty overrides
    overrides =
      Enum.reduce(overrides, %{}, fn
        {_, []}, acc ->
          acc

        {k, v}, acc ->
          Map.put(acc, k, v)
      end)

    # Update the current information
    {:ok, {table, depth, sizes, generation, _overrides}} = Info.get(self())
    Info.set(self(), {table, depth, sizes, generation, overrides})

    # Update and return the state
    %__MODULE__{state | overrides: overrides}
  end
end
