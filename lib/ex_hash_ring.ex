defmodule ExHashRing do
  use Application

  def start(_type, _args) do
    ExHashRing.Config.start_link()
  end
end
