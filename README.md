# Hash Ring

[![Master](https://travis-ci.org/discordapp/ex_hash_ring.svg?branch=master)](https://travis-ci.org/discordapp/ex_hash_ring)
[![Hex.pm Version](http://img.shields.io/hexpm/v/ex_hash_ring.svg?style=flat)](https://hex.pm/packages/ex_hash_ring)

A pure Elixir consistent hash ring implemention based on the excellent [C hash-ring lib](https://github.com/chrismoos/hash-ring)
by [Chris Moos](https://github.com/chrismoos).

It does not try to performantly build the hash ring, but provides  fast node lookup. It deliberately does not provide encapsulation
within a `GenServer` and leaves that up to the user. At [Discord](https://discordapp.com) we found using a `GenServer` for such
frequently accessed data proved to be overwhelming so we rewrote the hash ring in pure Elixir and paired it with
[FastGlobal](https://github.com/discordapp/fastglobal) to allow the calling process to use it's CPU time to interact with
the hash ring and therefore avoiding overloading a central GenServer.

## Usage

Add it to `mix.exs`.

```elixir
defp deps do
  [{:ex_hash_ring, "~> 1.0"}]
end
```

Create a new HashRing.

```elixir
ring = HashRing.new
{:ok, ring} = HashRing.add_node(ring, "a")
{:ok, ring} = HashRing.add_node(ring, "b")
```

Find the node for a key.

```elixir
"a" = HashRing.find_node(ring, "key1")
"b" = HashRing.find_node(ring, "key3")
```

## License

Hash Ring is released under [the MIT License](LICENSE).
Check [LICENSE](LICENSE) file for more information.