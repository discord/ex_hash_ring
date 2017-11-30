defmodule HashRing.ETS.Config do
    use GenServer

    @type config :: {reference, integer, integer}
    defstruct monitored_pids: %{}

    def start_link() do
      GenServer.start_link(__MODULE__, nil, name: __MODULE__)
    end

    def init(_) do
      :ets.new(__MODULE__, [
        :protected,
        :set,
        :named_table,
        {:read_concurrency, true}
      ])
      {:ok, %__MODULE__{}}
    end

    @spec set(atom, pid, config) :: :ok
    def set(name, owner_pid, config) do
      GenServer.call(__MODULE__, {:set, name, owner_pid, config})
    end

    @spec get(atom) :: {:ok, config} | :error
    def get(name) do
      case :ets.lookup(__MODULE__, name) do
        [{^name, config}] -> {:ok, config}
        _ -> :error
      end
    end

    def handle_call({:set, name, owner_pid, config}, _from, state) do
      state = state |> monitor_ring(name, owner_pid)
      true = :ets.insert(__MODULE__, {name, config})
      {:reply, :ok, state}
    end

    def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, %{monitored_pids: monitored_pids}=state) do
       monitored_pids = case Map.pop(monitored_pids, monitor_ref) do
         {nil, monitored_pids} -> monitored_pids
         {name, monitored_pids} ->
            :ets.delete(__MODULE__, name)
            monitored_pids
       end

       {:noreply, %{state | monitored_pids: monitored_pids}}
    end

    defp monitor_ring(%{monitored_pids: monitored_pids}=state, name, owner_pid) do
      monitor_ref = Process.monitor(owner_pid)
      %{state | monitored_pids: Map.put(monitored_pids, monitor_ref, name)}
    end
end