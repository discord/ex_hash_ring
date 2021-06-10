defmodule ExHashRing.Node.Test do
  use ExUnit.Case

  alias ExHashRing.Node

  def counts(expanded) do
    expanded
    |> Enum.group_by(fn {_, name} -> name end)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, Enum.count(value))
    end)
  end

  describe "expand/1" do
    test "empty list is returned" do
      assert [] == Node.expand([])
    end

    test "handles a list of all Node.t()" do
      nodes = [
        {"test-node-a", 2},
        {"test-node-b", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      assert Map.get(counts, "test-node-a") == 2
      assert Map.get(counts, "test-node-b") == 3
    end

    test "zero-replicas are dropped" do
      nodes = [
        {"test-node-a", 0},
        {"test-node-b", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      refute Map.has_key?(counts, "test-node-a")
      assert Map.get(counts, "test-node-b") == 3
    end

    test "negative-replicas are dropped" do
      nodes = [
        {"test-node-a", -1},
        {"test-node-b", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      refute Map.has_key?(counts, "test-node-a")
      assert Map.get(counts, "test-node-b") == 3
    end
  end

  describe "expand/2" do
    test "handles a list of all Node.t() (ignores the replicas argument)" do
      nodes = [
        {"test-node-a", 2},
        {"test-node-b", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      assert Map.get(counts, "test-node-a") == 2
      assert Map.get(counts, "test-node-b") == 3
    end

    test "handles a list of all Node.t() with zero-replica count (ignores the replicas argument)" do
      nodes = [
        {"test-node-a", 0},
        {"test-node-b", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      refute Map.has_key?(counts, "test-node-a")
      assert Map.get(counts, "test-node-b") == 3
    end

    test "handles a list of all Node.t() with negative-replica count (ignores the replicas argument)" do
      nodes = [
        {"test-node-a", -1},
        {"test-node-b", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      refute Map.has_key?(counts, "test-node-a")
      assert Map.get(counts, "test-node-b") == 3
    end

    test "handles a list of all Node.name() (creates replicas argument number of virtual nodes)" do
      nodes = ["test-node-a", "test-node-b"]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      assert Map.get(counts, "test-node-a") == 5
      assert Map.get(counts, "test-node-b") == 5
    end

    test "handles a list of mixed Node.t() and Node.name() (ignores replicas argument for Node.t(), uses it for Node.name())" do
      nodes = [
        "test-node-a",
        {"test-node-b", 2},
        "test-node-c",
        {"test-node-d", 3}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      assert Map.get(counts, "test-node-a") == 5
      assert Map.get(counts, "test-node-b") == 2
      assert Map.get(counts, "test-node-c") == 5
      assert Map.get(counts, "test-node-d") == 3
    end

    test "handles a list of mixed Node.t() and Node.name() with zero and negative replicas (ignores replicas argument for Node.t(), uses it for Node.name())" do
      nodes = [
        "test-node-a",
        {"test-node-b", 0},
        "test-node-c",
        {"test-node-d", -1},
        "test-node-e",
        {"test-node-f", 2}
      ]

      counts =
        nodes
        |> Node.expand(5)
        |> counts()

      assert Map.get(counts, "test-node-a") == 5
      refute Map.has_key?(counts, "test-node-b")
      assert Map.get(counts, "test-node-c") == 5
      refute Map.has_key?(counts, "test-node-d")
      assert Map.get(counts, "test-node-e") == 5
      assert Map.get(counts, "test-node-f") == 2
    end
  end

  describe "normalize/2" do
    test "ignores replicas argument for Node.t()" do
      node = {"test-node", 100}
      assert node == Node.normalize(node, 200)
    end

    test "uses replicas argument for Node.name()" do
      assert {"test-node", 200} = Node.normalize("test-node", 200)
    end

    test "handles a list of all Node.t() (ignores the replicas argument)" do
      nodes = [
        {"test-node-a", 100},
        {"test-node-b", 200},
        {"test-node-c", 300}
      ]

      assert nodes == Node.normalize(nodes, 500)
    end

    test "handles a list of all Node.name() (decorates with the replicas argument)" do
      nodes = ["test-node-a", "test-node-b", "test-node-c"]

      expected = for node <- nodes, do: {node, 100}

      assert expected == Node.normalize(nodes, 100)
    end

    test "handles a list of mixed Node.t() and Node.name() (ignores for Node.t(), decorates for Node.name())" do
      nodes = [
        "test-node-a",
        {"test-node-b", 100},
        "test-node-c",
        {"test-node-d", 200}
      ]

      expected = [
        {"test-node-a", 300},
        {"test-node-b", 100},
        {"test-node-c", 300},
        {"test-node-d", 200}
      ]

      assert expected == Node.normalize(nodes, 300)
    end
  end
end
