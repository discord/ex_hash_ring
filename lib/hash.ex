defmodule ExHashRing.Hash do
  @moduledoc """
  Hash encapsulates the hashing logic for converting keys into ring locations.

  Any term that implements the String.Char protocol can be used as a key.
  """

  @typedoc """
  Any term that can be coerced into a string (String.Char.t()) is a hashable term.
  """
  @type hashable :: String.Char.t()

  @typedoc """
  Hash for the term, this is used to locate Nodes in the Ring
  """
  @type t :: integer()

  @spec of(hashable()) :: t()
  def of(key) when is_binary(key) do
    <<_::binary-size(8), value::unsigned-little-integer-size(64)>> = :erlang.md5(key)
    value
  end

  def of(key) do
    key
    |> to_string()
    |> of()
  end
end
