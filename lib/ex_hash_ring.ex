defmodule ExHashRing do
  @moduledoc """
  ExHashRing Application.

  Starts all the components of ExHashRing that must be running for the library to function
  correctly
  """

  use Application

  def start(_type, _args) do
    ExHashRing.Info.start_link()
  end
end
