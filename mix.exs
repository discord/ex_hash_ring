defmodule HashRing.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_hash_ring,
      version: "1.0.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      package: package()
   ]
  end

  def application do
    [
      applications: []
    ]
  end

  def deps do
    [
      {:benchfella, "~> 0.3.0", only: :dev}
    ]
  end

  def package do
    [
      name: :ex_hash_ring,
      description: "A fast consistent hash ring implementation in Elixir.",
      maintainers: [],
      licenses: ["MIT"],
      files: ["lib/*", "mix.exs", "README*", "LICENSE*"],
      links: %{
        "GitHub" => "https://github.com/hammerandchisel/ex_hash_ring",
      },
    ]
  end
end
