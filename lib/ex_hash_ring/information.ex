defmodule ExHashRing.Information do
  @moduledoc """
  Provides an interface for querying information about Rings.

  Each Ring has some associated information that is available at all times to aid in performing
  client-context queries into the underlying ETS table.non_neg_integer()
  """

  use GenServer

  alias ExHashRing.Ring

  @type t :: %__MODULE__{}

  @typedoc """
  For any ring name information can be looked up that will provide an entry containing specifics
  about the table holding the ring data, the configured history depth, sizes for each generation
  in the history, the current generation, and any overrides that should be applied during lookup.
  """
  @type entry :: {
          table :: :ets.tid(),
          depth :: Ring.depth(),
          sizes :: [Ring.size()],
          generation :: Ring.generation(),
          overrides :: Ring.overrides()
        }

  defstruct monitored_pids: %{}

  ## Client

  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Retrieves the information for the specified ring.
  """
  @spec get(name :: Ring.name()) :: {:ok, entry()} | {:error, :no_ring}
  def get(name) do
    case :ets.lookup(__MODULE__, name) do
      [{^name, information}] ->
        {:ok, information}

      _ ->
        {:error, :no_ring}
    end
  end

  @doc """
  Sets the information for the specified ring.
  """
  @spec set(name :: Ring.name(), owner_pid :: pid(), information :: entry) :: :ok
  def set(name, owner_pid, information) do
    GenServer.call(__MODULE__, {:set, name, owner_pid, information})
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

  def handle_call({:set, name, owner_pid, information}, _from, state) do
    state = monitor_ring(state, name, owner_pid)
    true = :ets.insert(__MODULE__, {name, information})
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, monitor_ref, :process, pid, _reason}, %__MODULE__{} = state) do
    monitored_pids =
      case Map.pop(state.monitored_pids, pid) do
        {nil, monitored_pids} ->
          monitored_pids

        {{^monitor_ref, name}, monitored_pids} ->
          :ets.delete(__MODULE__, name)
          monitored_pids
      end

    {:noreply, %__MODULE__{state | monitored_pids: monitored_pids}}
  end

  ## Private

  @spec monitor_ring(state :: t(), name :: Ring.name(), owner_pid :: pid()) :: t()
  defp monitor_ring(%__MODULE__{} = state, name, owner_pid) do
    monitored_pids =
      Map.put_new_lazy(state.monitored_pids, owner_pid, fn ->
        monitor_ref = Process.monitor(owner_pid)
        {monitor_ref, name}
      end)

    %__MODULE__{state | monitored_pids: monitored_pids}
  end
end
