ExHashRing.Ring.start_link(Target, depth: 2, named: true, nodes: ["a", "b", "c"])

ExHashRing.Ring.add_nodes(Target, ["d", "e", "f"])

{:ok, nodes} = ExHashRing.Ring.find_stable_nodes(Target, 1, 2)
