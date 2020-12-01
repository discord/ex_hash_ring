defmodule ExHashRing.Configuration do
  @moduledoc """
  Configuration provides programmatic access into the various configuration settings that can be
  configured for ExHashRing.
  """

  @default_depth 1
  @default_gc_delay 10_000
  @default_replicas 512

  alias ExHashRing.{Node, Ring}

  @doc """
  Clears any custom configuration for depth, this will cause it to revert to the default,
  #{@default_depth}
  """
  @spec clear_depth() :: :ok
  def clear_depth do
    Application.delete_env(:ex_hash_ring, :depth)
  end

  @doc """
  Clears any custom configuration for gc_delay, this will cause it to revert to the default,
  #{@default_gc_delay}
  """
  @spec clear_gc_delay() :: :ok
  def clear_gc_delay do
    Application.delete_env(:ex_hash_ring, :gc_delay)
  end

  @doc """
  Clears any custom configuration for replicas, this will cause it to rever to the default,
  #{@default_replicas}
  """
  @spec clear_replicas() :: :ok
  def clear_replicas do
    Application.delete_env(:ex_hash_ring, :replicas)
  end

  @doc """
  Get the configured history depth.
  """
  @spec get_depth() :: Ring.depth()
  def get_depth do
    Application.get_env(:ex_hash_ring, :depth, @default_depth)
  end


  @doc """
  Get the configured gc delay.  Result is number of milliseconds to delay.
  """
  @spec get_gc_delay() :: pos_integer()
  def get_gc_delay do
    Application.get_env(:ex_hash_ring, :gc_delay, @default_gc_delay)
  end

  @doc """
  Get the configured number of replicas.
  """
  @spec get_replicas() :: Node.replicas()
  def get_replicas do
    Application.get_env(:ex_hash_ring, :replicas, @default_replicas)
  end

  @doc """
  Puts the history depth.
  """
  @spec put_depth(depth :: Ring.depth()) :: :ok
  def put_depth(depth) do
    Application.put_env(:ex_hash_ring, :depth, depth)
  end

  @doc """
  Puts the gc delay, delay is a positive number of milliseconds to wait before gc.
  """
  @spec put_gc_delay(delay :: pos_integer()) :: :ok
  def put_gc_delay(delay) do
    Application.put_env(:ex_hash_ring, :gc_delay, delay)
  end

  @doc """
  Puts the number of replicas.
  """
  @spec put_replicas(replicas :: Node.replicas()) :: :ok
  def put_replicas(replicas) do
    Application.put_env(:ex_hash_ring, :replicas, replicas)
  end
end
