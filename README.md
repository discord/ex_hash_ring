# ExHashRing

[![Master](https://travis-ci.org/discordapp/ex_hash_ring.svg?branch=master)](https://travis-ci.org/discordapp/ex_hash_ring)
[![Hex.pm Version](http://img.shields.io/hexpm/v/ex_hash_ring.svg?style=flat)](https://hex.pm/packages/ex_hash_ring)

A pure Elixir consistent hash ring implemention based on the excellent [C hash-ring lib](https://github.com/chrismoos/hash-ring) by [Chris Moos](https://github.com/chrismoos).

ExHashRing is a production ready library actively maintained and in use at [Discord](https://discord.com).

ExHashRing provides the following features.

- Lookup optimized ring storage. A ring is stored in an [ETS table](https://erlang.org/doc/man/ets.html) which provides excellent lookup performance.
- Key overrides that allow the client to pin a key to a member.
- Configurable replica count for virtual nodes.
- Configurable history that allows for stable lookups over time.

## Installation

Add it to `mix.exs`.

```elixir
defp deps do
  [{:ex_hash_ring, "~> 6.0"}]
end
```

## Upgrading to 6.0.0

Version 6.0.0 introduces a number of breaking changes.  Refer to the [Upgrade Guide](/pages/upgrade.md) for instructions.

## Quickstart

Each Ring is managed by a GenServer, here's an example of starting an empty Ring.

```elixir
iex(1)> alias ExHashRing.Ring
ExHashRing.Ring
iex(2)> {:ok, _} = Ring.start_link(:example, named: true)
{:ok, #PID<0.166.0>}
```

We can add a single node with `add_node/2`

```elixir
iex(3)> Ring.add_node(:example, "a")
{:ok, [{"a", 512}]}
```

The `512` above is the number of replicas for this node.  Since we did not specify a custom number of replicas, it was added with the default for this Ring, which itself defaults to `512`.  We can control the number of default replicas when we start_link the Ring and we can control the number of replicas on a per-node basis.

We can add another node with a custom replica count with `add_node/3`

```elixir
iex(4)> Ring.add_node(:example, "b", 100)
{:ok, [{"b", 100}, {"a", 512}]}
```

Now that we have some nodes we can use our Ring to map keys to nodes with the `find_node/2` function.

```elixir
iex(5)> Ring.find_node(:example, "key1")
{:ok, "a"}
iex(6)> Ring.find_node(:example, "key37")
{:ok, "b"}
```

## Documentation

The Quickstart above just scratches the surface of the functionality that ExHashRing provides.  For more details see the [HexDocs](https://hexdocs.pm/ex_hash_ring)

## Configuration

ExHashRing exposes some configuration options under the `:ex_hash_ring` key.

| Key         | Description                                                                              | Default |
|-------------|------------------------------------------------------------------------------------------|---------|
| `:depth`    | Default history depth for new rings                                                      | 1       |
| `:gc_delay` | The amount of time, in milliseconds, to wait before garbage collecting stale generations | 10_000  |
| `:replicas` | Default replicas setting for new rings                                                   | 512     |

## License

Hash Ring is released under [the MIT License](LICENSE). Check [LICENSE](LICENSE) file for more information.
