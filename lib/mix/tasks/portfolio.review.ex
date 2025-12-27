defmodule Mix.Tasks.Portfolio.Review do
  @moduledoc """
  Review pending agentic detections.

  ## Usage

      mix portfolio.review [repo-id]

  ## Options

    * `--accept-all` - Accept all with confidence > threshold
    * `--threshold` - Confidence threshold (default: 0.9)
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.review
      mix portfolio.review instructor_ex
      mix portfolio.review --accept-all --threshold=0.85
  """
  @shortdoc "Review pending detections"

  use Mix.Task

  alias PortfolioManager.CLI.Exit
  alias PortfolioManager.Detection.{Agentic, ReviewStore}

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          accept_all: :boolean,
          threshold: :string,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      repo_id = List.first(args)
      review_pending(repo_id, opts)
    end
  end

  defp review_pending(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        handle_review_pending(portfolio, repo_id, opts)

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
        Exit.halt(:config)
    end
  end

  defp handle_review_pending(portfolio, repo_id, opts) do
    {:ok, items} = ReviewStore.list_pending(portfolio)
    filtered = filter_items(items, repo_id)

    if Enum.empty?(filtered) do
      Mix.shell().info("No pending detections to review.")
    else
      process_review_items(portfolio, filtered, opts)
    end
  end

  defp process_review_items(portfolio, filtered, opts) do
    threshold = parse_threshold(opts[:threshold])

    if opts[:accept_all] do
      accept_all(portfolio, filtered, threshold, opts[:json])
    else
      interactive_review(portfolio, filtered, opts[:json])
    end
  end

  defp accept_all(portfolio, items, threshold, json?) do
    {accepted, remaining} =
      Enum.split_with(items, fn item ->
        is_number(item["confidence"]) and item["confidence"] >= threshold
      end)

    {applied, failed} =
      Enum.reduce(accepted, {0, []}, fn item, {ok_count, failures} ->
        case Agentic.apply_review_item(portfolio, item) do
          :ok -> {ok_count + 1, failures}
          {:error, reason} -> {ok_count, [{item, reason} | failures]}
        end
      end)

    :ok = ReviewStore.save_pending(portfolio, remaining ++ Enum.map(failed, &elem(&1, 0)))

    if applied > 0 do
      case PortfolioManager.sync(portfolio) do
        :ok ->
          :ok

        {:error, reason} ->
          Mix.shell().error("Failed to save portfolio: #{inspect(reason)}")
          Exit.halt(:error)
      end
    end

    if json? do
      Mix.shell().info(
        Jason.encode!(%{accepted: applied, failed: length(failed), remaining: length(remaining)},
          pretty: true
        )
      )
    else
      Mix.shell().info("Accepted #{applied} items. Remaining: #{length(remaining)}.")

      if failed != [] do
        Mix.shell().info("Failed to apply #{length(failed)} items.")
      end
    end
  end

  defp interactive_review(portfolio, items, json?) do
    {accepted, rejected, pending} =
      Enum.reduce(items, {0, 0, []}, fn item, acc ->
        display_item(item)
        handle_review_action(portfolio, item, prompt_action(), acc)
      end)

    :ok = ReviewStore.save_pending(portfolio, Enum.reverse(pending))

    if accepted > 0 do
      case PortfolioManager.sync(portfolio) do
        :ok ->
          :ok

        {:error, reason} ->
          Mix.shell().error("Failed to save portfolio: #{inspect(reason)}")
          Exit.halt(:error)
      end
    end

    if json? do
      Mix.shell().info(
        Jason.encode!(%{accepted: accepted, rejected: rejected, pending: length(pending)},
          pretty: true
        )
      )
    else
      Mix.shell().info("Review complete. Accepted: #{accepted}. Rejected: #{rejected}.")
    end
  end

  defp handle_review_action(portfolio, item, :accept, {acc_ok, acc_reject, acc_pending}) do
    case Agentic.apply_review_item(portfolio, item) do
      :ok ->
        Mix.shell().info("✓ Accepted")
        {acc_ok + 1, acc_reject, acc_pending}

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
        {acc_ok, acc_reject, [item | acc_pending]}
    end
  end

  defp handle_review_action(_portfolio, _item, :reject, {acc_ok, acc_reject, acc_pending}) do
    Mix.shell().info("✗ Rejected")
    {acc_ok, acc_reject + 1, acc_pending}
  end

  defp handle_review_action(portfolio, item, :modify, {acc_ok, acc_reject, acc_pending}) do
    case modify_item(item) do
      {:ok, updated_item} ->
        apply_modified_item(portfolio, item, updated_item, {acc_ok, acc_reject, acc_pending})

      :skip ->
        {acc_ok, acc_reject, [item | acc_pending]}
    end
  end

  defp handle_review_action(_portfolio, item, :skip, {acc_ok, acc_reject, acc_pending}) do
    {acc_ok, acc_reject, [item | acc_pending]}
  end

  defp apply_modified_item(portfolio, item, updated_item, {acc_ok, acc_reject, acc_pending}) do
    case Agentic.apply_review_item(portfolio, updated_item) do
      :ok ->
        Mix.shell().info("✓ Accepted (modified)")
        {acc_ok + 1, acc_reject, acc_pending}

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
        {acc_ok, acc_reject, [item | acc_pending]}
    end
  end

  defp display_item(item) do
    Mix.shell().info("""
    \nReview item: #{item["repo_id"]} - #{item["field"]}
      Value: #{format_value(item["value"])}
      Confidence: #{item["confidence"]}
      Reasoning: #{item["reasoning"] || "N/A"}
    """)
  end

  defp format_value(value) when is_map(value), do: Jason.encode!(value)
  defp format_value(value), do: to_string(value)

  defp prompt_action do
    case IO.gets("Accept (a), Reject (r), Modify (m), Skip (s)? ") do
      :eof ->
        :skip

      {:error, _} ->
        :skip

      input ->
        case String.trim(String.downcase(input)) do
          "a" -> :accept
          "r" -> :reject
          "m" -> :modify
          "s" -> :skip
          _ -> :skip
        end
    end
  end

  defp modify_item(item) do
    field = item["field"]

    case field do
      "purpose" ->
        new_value = IO.gets("Enter new purpose: ") |> to_string() |> String.trim()
        {:ok, Map.put(item, "value", new_value)}

      "type" ->
        new_value = IO.gets("Enter new type: ") |> to_string() |> String.trim()
        {:ok, Map.put(item, "value", new_value)}

      "status" ->
        new_value = IO.gets("Enter new status: ") |> to_string() |> String.trim()
        {:ok, Map.put(item, "value", new_value)}

      "relationship" ->
        to = IO.gets("Enter related repo id or URL: ") |> to_string() |> String.trim()
        type = IO.gets("Enter relationship type: ") |> to_string() |> String.trim()
        value = %{"from" => item["repo_id"], "to" => to, "type" => type}
        {:ok, Map.put(item, "value", value)}

      _ ->
        :skip
    end
  end

  defp filter_items(items, nil), do: items
  defp filter_items(items, repo_id), do: Enum.filter(items, &(&1["repo_id"] == repo_id))

  defp parse_threshold(nil), do: 0.9

  defp parse_threshold(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      _ -> 0.9
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.review [repo-id]

    Review pending agentic detections.

    Options:
      --accept-all   Accept all with confidence > threshold
      --threshold    Confidence threshold (default: 0.9)
      --json         Output as JSON
      --help         Show this help message

    Examples:
      mix portfolio.review
      mix portfolio.review instructor_ex
      mix portfolio.review --accept-all --threshold=0.85
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
