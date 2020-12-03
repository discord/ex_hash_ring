# Upgrade Guild

## Upgrading to 6.0.0

6.0.0 introduces a number of breaking changes.

### Removal of the In-Memory HashRing

One of the largest changes is that 6.0.0 removes the in-memory HashRing.  The library is now more opinionated about how the ring should be stored and queried.  Rings are owned by a GenServer, which has ownership over the ETS table used to store the Ring.

Even though the Ring is owned by a GenServer, the lookups into the Ring are done in the client context by reading from the ETS table.

### Renaming of Modules

With the In-Memory and ETS versions of the Ring unified into a single model, some Module renaming was done to simplify the library.

| Pre-6.0.0                      | 6.0.0            | Change                                                         |
|--------------------------------|------------------|----------------------------------------------------------------|
| ExHashRing                     | ExHashRing       | No Change                                                      |
| ExHashRing.HashRing            | ExHashRing.Ring  | The datastructure is removed in favor of the GenServer version |
| ExHashRing.HashRing.Utils      | ExHashRing.Utils | No Change                                                      |
| ExHashRing.HashRing.ETS        | ExHashRing.Ring  | Module renamed to Ring, interface has changed                  |
| ExHashRing.HashRing.ETS.Config | ExHashRing.Info  | Module renamed, entry structure changed          |

### History Support

Rings now have the ability to store a history of ring snapshots.  The history is configurable and the default configuration sets the `depth` to 1.  History support allows the caller to handle situations where they want to find out the assignment of a key to a node in a previous configuration of the ring.

These new functions allow the caller to lookup a key in previous configurations of the Ring.

- `find_historical_node/3`
- `find_historical_nodes/4`
- `find_stable_nodes/3,4`

`find_historical_node` and `find_historical_nodes` both accept an argument called `back` which is the number of generations to look back in the history.

`find_stable_nodes` will combine the results of looking back over all or some subset of the history and combines the results together.

Any time the Ring changes a new Generation is written out into the History.  To prevent generating intermediate generations, new batch APIs have been introduced for altering the Ring.

- `add_nodes/2`
- `remove_nodes/2`

These are similar to `add_node/2` and `remove_node/2` but can add or remove multiple nodes while only creating one new generation.

Changing Overrides does not generate a new generation and no history is retained for overrides.

### Ring Interface

In existing code any place where `ExHashRing.HashRing` was being used should be changed to `ExHashRing.Ring`.  This is no longer a datastructure but a Process and the caller is responsible for supervision like any other Elixir Process.

In existing code any plat where `ExHashRing.HashRing.ETS` was being used can use the `ExHashRing.Ring` module as a mostly drop in replacement.

#### `start_link/2` -> `start_link/1`

Pre-6.0.0 every ring had to be named and then optionally the process could be registered.  This could result in some very confusing issues when using unregistered rings becuase the ring names are required to be unique.  Consider the following code and keep in mind that during an iex session it's obvious what is happening, but with supervisors restarting processes the unintuitive behavior can be far away from the start_link calls.

```elixir
iex(1)> {:ok, first} = ExHashRing.HashRing.ETS.start_link(:example, nodes: ["a", "b"])
{:ok, #PID<0.165.0>}
iex(2)> ExHashRing.HashRing.ETS.find_node(:example, "key1")
{:ok, "a"}
iex(3)> {:ok, second} = ExHashRing.HashRing.ETS.start_link(:example, nodes: ["c", "d"])
{:ok, #PID<0.168.0>}
iex(4)> ExHashRing.HashRing.ETS.find_node(:example, "key1")
{:ok, "c"}
iex(5)> Process.alive?(first)
true
iex(6)> Process.alive?(second)
true
iex(7)> ExHashRing.HashRing.ETS.add_node(first, "f")
{:ok, [{"f", 512}, {"a", 512}, {"b", 512}]}
iex(8)> ExHashRing.HashRing.ETS.add_node(second, "g")
{:ok, [{"g", 512}, {"c", 512}, {"d", 512}]}
iex(9)> ExHashRing.HashRing.ETS.add_node(:example, "h")
** (exit) exited in: GenServer.call(:example, {:add_node, "h", nil}, 5000)
    ** (EXIT) no process: the process is not alive or there's no process currently associated with the given name, possibly because its application isn't started
    (elixir) lib/gen_server.ex:914: GenServer.call/3
```

The conflict occurs because the ring's name is used as the global configuration key.  Since the processes don't attempt to register the conflict is never detected and two processes can happily coexists with whoever writes last win semantics.

Pre-6.0.0 when the caller was required to pass the ring's name atom vs when they could provide the ring's pid was fairly inconsistent.

| function                  | Ring `named: false` | Ring `named: true` |
|---------------------------|---------------------|--------------------|
| add_node/2,3              | pid                 | pid OR name        |
| find_node/2               | name                | name               |
| find_nodes/3              | name                | name               |
| force_gc/1,2              | pid                 | pid OR name        |
| get_overrides/1           | pid                 | pid OR name        |
| get_nodes/1               | pid                 | pid OR name        |
| get_nodes_with_replicas/1 | pid                 | pid OR name        |
| get_ring_gen/1            | name                | name               |
| remove_node/2             | pid                 | pid OR name        |
| set_nodes/2               | pid                 | pid OR name        |
| set_overrides/2           | pid                 | pid OR name        |
| stop/1                    | pid                 | pid OR name        |

6.0.0 allows the caller to create either named rings (via the `name` option) or unnamed rings.  Both named and unnamed rings can be operated on via their pid.  Named rings can also be operated on by their name.  The equivalent table in 6.0.0 would look like this.

| function                  | Unnamed Ring | Named Ring  |
|---------------------------|--------------|-------------|
| any function              | pid          | pid OR name |

#### Naming and Registering

Pre-6.0.0 every ring was required to have a name and the `:named` option was a boolean that would control whether or not the ring's process registered under that name as well.  This meant that `start_link/2` has a single required argument, the name, and an optional argument, a Keyword of options.

6.0.0 no longer requires that every ring be named, unnamed rings can be operated on entirely through their pid alone.  Naming a ring now requires that the process also register under that name to prevent ring collisions.  To create a named ring use the `:name` option which accepts an atom to name the ring and its process after.
#### New Options for `start_link/2`

`start_link/2` has gained a new option, `:depth` which controls how many generations of history the ring should retain.

#### Renamed Options for `start_link/2`

The option `:default_num_replicas` was renamed to `:replicas`.

The option `:named` was renamed to `:name` and accepts the name directly instead of a boolean, see the Naming and Registering section for more details.
#### Renamed `get_ring_gen/1`

Since a Generation is now a more important concepts in the library this function was renamed from `get_ring_gen/1` to `get_generation/1`.

### Ring Info

`ExHashRing.HashRing.ETS.Config` was renamed to `ExHashRing.Info` and serves a similar purpose.  The interface is largely the same, but the entry tuple that can be saved and read to has been changed.

The module was renamed from `Config` to `Info` because it holds look-aside information similar to `Process.info`.  This is also to deconflict it with the concept of Application Configuration.

#### Pre-6.0.0

Pre-6.0.0 each entry in the Config was structured as a tuple containing the following information

```elixir
{
    ets_table_reference :: reference(),
    ring_generation :: integer(),
    num_nodes :: integer()
}
```

or

```elixir
{
    ets_table_reference :: reference()
    ring_generation :: integer(),
    num_nodes :: integer(),
    override_map :: %{atom() => [binary()]}
}
```

#### 6.0.0

In 6.0.0 more ring information is required to support the history functionality and to unify the two older representations into a single coherent representation.

The entries in the table are always structured as follows.

```elixir
{
    ets_table_reference :: reference(),
    depth :: Ring.depth() :: pos_integer(),
    sizes :: [Ring.size()] :: [non_neg_integer()],
    generation :: integer(),
    overrides :: %{Ring.key() :: Hash.hashable() :: String.Chars.t() => [Node.name() :: binary()]}
}
```

Note that the sizes is a list up to `depth` entries long that holds the number of nodes in each generation of the history starting with the current generation and then continuing with each subsequent generation.

#### Upgrading

The `ExHashRing.HashRing.ETS.Config` is largely an internal implementation detail and in the vast majority of cases nothing needs to be done to upgrade.  Code that was manually reading or writing configuration should be updated to read the new structure and write out the new structure.

### ExHashRing.Utils

The `take_max/2` utility function has been left in this module but the `hash/1` and `gen_items/1,2` functions have been relocated.

`ExHashRing.Utils.hash/1` has been replaced by the `ExHashRing.Hash.of/1` function.

`ExHashRing.Utils.gen_items/1,2` has been replaced by the `ExHashRing.Node.expand/1,2` functions.

Both of these replacements work largely in the same way as the previous versions and were moved out of Utils into more appropriate modules.

### Application Configuration

Prior to version 6.0.0 ExHashRing only had a single configuration value that could be set, `:hash_ring` `:ring_gen_gc_delay`

This keyspace is non-conventional since it disagrees with the OTP Application name.  6.0.0 corrects this and stores configuration under the `:ex_hash_ring` key.

Refer to the following table for more migration details

| Pre-6.0.0            | 6.0.0       | Description                                                                                                               |
|----------------------|-------------|---------------------------------------------------------------------------------------------------------------------------|
| `:ring_gen_gc_delay` | `:gc_delay` | The amount of time, in milliseconds, to wait before garbage collecting stale generations, defaults to 10_000 (10 seconds) |
| N / A                | `:depth`    | Default history depth for new rings, defaults to 1                                                                        |
| N / A                | `:replicas` | Default replicas setting for new rings, defaults to 512                                                                   |