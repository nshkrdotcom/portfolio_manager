defmodule PortfolioManager.Domain.RelationshipTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Domain.Relationship

  describe "new/1" do
    test "creates a relationship with valid attributes" do
      attrs = %{
        from: "repo-a",
        to: "repo-b",
        type: :depends_on
      }

      assert {:ok, rel} = Relationship.new(attrs)
      assert rel.from == "repo-a"
      assert rel.to == "repo-b"
      assert rel.type == :depends_on
    end

    test "generates id from from/to/type" do
      attrs = %{from: "a", to: "b", type: :port_of}

      assert {:ok, rel} = Relationship.new(attrs)
      assert rel.id == "a--port_of--b"
    end

    test "uses provided id" do
      attrs = %{id: "custom-id", from: "a", to: "b", type: :port_of}

      assert {:ok, rel} = Relationship.new(attrs)
      assert rel.id == "custom-id"
    end

    test "handles string keys" do
      attrs = %{
        "from" => "repo-a",
        "to" => "repo-b",
        "type" => "fork_of"
      }

      assert {:ok, rel} = Relationship.new(attrs)
      assert rel.type == :fork_of
    end

    test "defaults type to :related_to" do
      attrs = %{from: "a", to: "b"}

      assert {:ok, rel} = Relationship.new(attrs)
      assert rel.type == :related_to
    end

    test "fails with missing from" do
      attrs = %{to: "b", type: :depends_on}

      assert {:error, :from_required} = Relationship.new(attrs)
    end

    test "fails with missing to" do
      attrs = %{from: "a", type: :depends_on}

      assert {:error, :to_required} = Relationship.new(attrs)
    end

    test "includes details map" do
      attrs = %{
        from: "a",
        to: "b",
        type: :port_of,
        details: %{"coverage" => "partial"}
      }

      assert {:ok, rel} = Relationship.new(attrs)
      assert rel.details == %{"coverage" => "partial"}
    end

    test "sets created_at timestamp" do
      attrs = %{from: "a", to: "b"}

      assert {:ok, rel} = Relationship.new(attrs)
      assert %DateTime{} = rel.created_at
    end
  end

  describe "new!/1" do
    test "returns relationship on success" do
      attrs = %{from: "a", to: "b", type: :depends_on}
      rel = Relationship.new!(attrs)
      assert rel.from == "a"
    end

    test "raises on failure" do
      assert_raise ArgumentError, fn ->
        Relationship.new!(%{from: "a"})
      end
    end
  end

  describe "to_map/1" do
    test "converts to map with string keys" do
      {:ok, rel} =
        Relationship.new(%{
          from: "a",
          to: "b",
          type: :port_of,
          details: %{"note" => "test"}
        })

      map = Relationship.to_map(rel)

      assert map["from"] == "a"
      assert map["to"] == "b"
      assert map["type"] == "port_of"
      assert map["details"] == %{"note" => "test"}
    end

    test "excludes empty details" do
      {:ok, rel} = Relationship.new(%{from: "a", to: "b"})

      map = Relationship.to_map(rel)

      refute Map.has_key?(map, "details")
    end
  end

  describe "valid_types/0" do
    test "returns list of valid relationship types" do
      types = Relationship.valid_types()

      assert :depends_on in types
      assert :port_of in types
      assert :fork_of in types
      assert :evolved_from in types
      assert :related_to in types
    end
  end
end
