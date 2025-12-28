defmodule PortfolioManager.Mocks do
  @moduledoc """
  Mox mock definitions for testing.
  """
end

# Define mocks for all ports
Mox.defmock(PortfolioManager.Mocks.VectorStore, for: PortfolioCore.Ports.VectorStore)
Mox.defmock(PortfolioManager.Mocks.GraphStore, for: PortfolioCore.Ports.GraphStore)
Mox.defmock(PortfolioManager.Mocks.DocumentStore, for: PortfolioCore.Ports.DocumentStore)
Mox.defmock(PortfolioManager.Mocks.Embedder, for: PortfolioCore.Ports.Embedder)
Mox.defmock(PortfolioManager.Mocks.LLM, for: PortfolioCore.Ports.LLM)
Mox.defmock(PortfolioManager.Mocks.Chunker, for: PortfolioCore.Ports.Chunker)
