defmodule ExHashRing.HashRing.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_hash_ring,
      version: "3.0.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      elixirc_paths: elixirc_paths(Mix.env),
      deps: deps(),
      package: package()
   ]
  end

  def application do
    [
      applications: [],
      mod: {ExHashRing, []}
    ]
  end

  def deps do
    [
      {:benchfella, "~> 0.3.0", only: :dev}
    ]
  end

  defp elixirc_paths(:test) do
    elixirc_paths(:dev) ++ ["test/support"]
  end

  defp elixirc_paths(_),
    do: ["lib"]

  def package do
    [
      name: :ex_hash_ring,
      description: "A fast consistent hash ring implementation in Elixir.",
      maintainers: [],
      licenses: ["MIT"],
      files: ["lib/*", "mix.exs", "README*", "LICENSE*"],
      links: %{
        "GitHub" => "https://github.com/discordapp/ex_hash_ring",
      },
    ]
  end
end
