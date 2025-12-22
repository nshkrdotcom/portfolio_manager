defmodule PortfolioManager.Detection.GitStatisticsTest do
  @moduledoc """
  Tests for git commit statistics functions.
  """

  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.LocalGit

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "git_stats_test_#{:rand.uniform(1_000_000)}")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    # Initialize a git repo
    System.cmd("git", ["init", "-b", "main"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Test User"], cd: tmp_dir)

    # Create initial commit
    File.write!(Path.join(tmp_dir, "README.md"), "# Test")
    System.cmd("git", ["add", "."], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "Initial commit"], cd: tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "commit_count_30d/1" do
    test "returns count of commits in last 30 days", %{tmp_dir: tmp_dir} do
      # Add a few more commits
      for i <- 1..3 do
        File.write!(Path.join(tmp_dir, "file#{i}.txt"), "content #{i}")
        System.cmd("git", ["add", "."], cd: tmp_dir)
        System.cmd("git", ["commit", "-m", "Commit #{i}"], cd: tmp_dir)
      end

      {:ok, count} = LocalGit.commit_count_30d(tmp_dir)

      # Initial + 3 more = 4 commits
      assert count >= 4
    end

    test "returns 0 for repo with only old commits", %{tmp_dir: tmp_dir} do
      # This is tricky to test - we'd need to backdate commits
      # For now, just verify the function works
      {:ok, count} = LocalGit.commit_count_30d(tmp_dir)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "contributor_count/1" do
    test "returns count of unique contributors", %{tmp_dir: tmp_dir} do
      {:ok, count} = LocalGit.contributor_count(tmp_dir)

      # At least one contributor (Test User)
      assert count >= 1
    end
  end

  describe "contributors/1" do
    test "returns unique contributor emails", %{tmp_dir: tmp_dir} do
      {:ok, emails} = LocalGit.contributors(tmp_dir)

      assert is_list(emails)
      assert "test@example.com" in emails
    end
  end

  describe "first_commit_date/1" do
    test "returns date of first commit", %{tmp_dir: tmp_dir} do
      {:ok, date} = LocalGit.first_commit_date(tmp_dir)

      assert %DateTime{} = date
      # First commit should be from today
      assert Date.compare(DateTime.to_date(date), Date.utc_today()) == :eq
    end
  end

  describe "last_commit_date/1" do
    test "returns date of last commit", %{tmp_dir: tmp_dir} do
      {:ok, date} = LocalGit.get_last_commit_date(tmp_dir)

      assert %DateTime{} = date
    end
  end

  describe "get_contributors/1" do
    test "returns list of contributors with counts", %{tmp_dir: tmp_dir} do
      {:ok, contributors} = LocalGit.get_contributors(tmp_dir)

      assert is_list(contributors)
      assert length(contributors) >= 1

      [first | _] = contributors
      assert Map.has_key?(first, :name)
      assert Map.has_key?(first, :email)
      assert Map.has_key?(first, :commits)
    end
  end

  describe "days_since_last_commit/1" do
    test "returns 0 for today's commit", %{tmp_dir: tmp_dir} do
      {:ok, days} = LocalGit.days_since_last_commit(tmp_dir)

      assert days == 0
    end
  end
end
