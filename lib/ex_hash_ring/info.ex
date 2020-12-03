defmodule ExHashRing.Info do
  @moduledoc """
  Provides an interface for querying information about Rings.

  Each Ring has some associated information that is available at all times to aid in performing
  client-context queries into the underlying ETS table.non_neg_integer()
  """

  use GenServer

  alias ExHashRing.Ring

  @typedoc """
  For any ring information can be looked up that will provide an entry containing specifics about
  the table holding the ring data, the configured history depth, sizes for each generation in the
  history, the current generation, and any overrides that should be applied during lookup.
  """
  @type entry :: {
          table :: :ets.tid(),
          depth :: Ring.depth(),
          sizes :: [Ring.size()],
          generation :: Ring.generation(),
          overrides :: Ring.overrides()
        }

  @type t :: %__MODULE__{
    monitored_pids: %{pid() => reference()}
  }
  defstruct monitored_pids: %{}


  ## Client

  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Retrieves the info entry for the specified ring.
  """
  @spec get(name :: Ring.name()) :: {:ok, entry()} | {:error, :no_ring}
  def get(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        {:error, :no_ring}

      pid ->
        get(pid)
    end
  end

  @spec get(pid()) :: {:ok, entry()} | {:error, :no_ring}
  def get(pid) when is_pid(pid) do
    case :ets.lookup(__MODULE__, pid) do
      [{^pid, entry}] ->
        {:ok, entry}

      _ ->
        {:error, :no_ring}
    end
  end

  @doc """
  Sets the info entry for the specified ring.
  """
  @spec set(name :: Ring.name(), entry()) :: :ok | {:error, :no_ring}
  def set(name, entry) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        {:error, :no_ring}

      pid ->
        set(pid, entry)
    end
  end

  @spec set(pid(), entry()) :: :ok
  def set(pid, entry) when is_pid(pid) do
    GenServer.call(__MODULE__, {:set, pid, entry})
  end

  ## Server

  @spec init(:ok) :: {:ok, t}
  def init(:ok) do
    :ets.new(__MODULE__, [
      :protected,
      :set,
      :named_table,
      {:read_concurrency, true}
    ])

    {:ok, %__MODULE__{}}
  end

  def handle_call({:set, pid, entry}, _from, state) do
    state = monitor_ring(state, pid)
    true = :ets.insert(__MODULE__, {pid, entry})
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, %__MODULE__{} = state) do
    monitored_pids =
      case Map.pop(state.monitored_pids, pid) do
        {nil, monitored_pids} ->
          monitored_pids

        {^monitor_ref, monitored_pids} ->
          :ets.delete(__MODULE__, pid)
          monitored_pids
      end

    {:noreply, %__MODULE__{state | monitored_pids: monitored_pids}}
  end

  ## Private

  @spec monitor_ring(state :: t(), pid()) :: t()
  defp monitor_ring(%__MODULE__{} = state, pid) do
    monitored_pids =
      Map.put_new_lazy(state.monitored_pids, pid, fn ->
        Process.monitor(pid)
      end)

    %__MODULE__{state | monitored_pids: monitored_pids}
  end
end
