defmodule HashRing.ETS.Config do
    use GenServer

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

    def set(name, owner_pid, config) do
      GenServer.call(__MODULE__, {:set, name, owner_pid, config})
    end

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

    defp monitor_ring(%{monitored_pids: monitored_pids}=state, name, owner_pid) do
      ## TODO: implement me
      ## TODO: implement handle down.
      state
    end
end