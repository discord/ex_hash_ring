defmodule ExHashRing do
  use Application

  def start(_type, _args) do
    ExHashRing.HashRing.ETS.Config.start_link()
  end
end
