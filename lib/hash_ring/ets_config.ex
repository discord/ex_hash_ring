defmodule ExHashRing.HashRing.ETS.Config do
  use GenServer

  @type t :: %__MODULE__{}
  @type ring_gen :: integer
  @type num_nodes :: integer
  @type override_map :: %{atom => [binary]}
  @type table_config :: {:ets.tid(), num_nodes()}
  @type config ::{current :: table_config(), previous :: table_config(), ring_gen(), override_map()}

  defstruct monitored_pids: %{}

  ## Client

  @spec start_link() :: GenServer.on_start()
  def start_link() do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Retrieves the configuration for the specified ring.
  """
  @spec get(atom) :: {:ok, config} | {:error, :no_ring}
  def get(name) do
    case :ets.lookup(__MODULE__, name) do
      [{^name, config}] ->
        {:ok, config}

      _ ->
        {:error, :no_ring}
    end
  end

  @doc """
  Sets the configuration for the specified ring.
  """
  @spec set(atom, pid, config) :: :ok
  def set(name, owner_pid, config) do
    GenServer.call(__MODULE__, {:set, name, owner_pid, config})
  end

  ## Server

  @spec init(any) :: {:ok, t}
  def init(_) do
    :ets.new(__MODULE__, [
      :protected,
      :set,
      :named_table,
      {:read_concurrency, true}
    ])

    {:ok, %__MODULE__{}}
  end

  def handle_call({:set, name, owner_pid, config}, _from, state) do
    state = monitor_ring(state, name, owner_pid)
    true = :ets.insert(__MODULE__, {name, config})
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

  @spec monitor_ring(state :: t(), name :: binary(), owner_pid :: pid()) :: t()
  defp monitor_ring(%__MODULE__{} = state, name, owner_pid) do
    monitored_pids =
      Map.put_new_lazy(state.monitored_pids, owner_pid, fn ->
        monitor_ref = Process.monitor(owner_pid)
        {monitor_ref, name}
      end)

    %__MODULE__{state | monitored_pids: monitored_pids}
  end
end
