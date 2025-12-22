defmodule PortfolioManager.Adapters.LocalGitTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.LocalGit

  import PortfolioManager.TestHelpers

  describe "is_repo?/1" do
    test "returns true for git repo" do
      path = Path.join(System.tmp_dir!(), "git_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      assert LocalGit.is_repo?(path)
    end

    test "returns false for non-repo directory" do
      path = Path.join(System.tmp_dir!(), "not_git_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf!(path) end)

      refute LocalGit.is_repo?(path)
    end

    test "returns false for non-existent path" do
      refute LocalGit.is_repo?("/tmp/definitely_not_a_path_#{:rand.uniform(10000)}")
    end
  end

  describe "get_info/1" do
    test "returns info for git repo" do
      path = Path.join(System.tmp_dir!(), "info_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      assert {:ok, info} = LocalGit.get_info(path)
      assert info.path == path
      assert is_binary(info.branch)
      assert is_binary(info.last_commit)
      assert info.is_dirty == false
    end

    test "returns error for non-repo" do
      path = Path.join(System.tmp_dir!(), "not_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:error, :not_a_repo} = LocalGit.get_info(path)
    end
  end

  describe "is_dirty?/1" do
    test "returns false for clean repo" do
      path = Path.join(System.tmp_dir!(), "clean_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      refute LocalGit.is_dirty?(path)
    end

    test "returns true for dirty repo" do
      path = Path.join(System.tmp_dir!(), "dirty_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      # Make it dirty
      File.write!(Path.join(path, "new_file.txt"), "content")

      assert LocalGit.is_dirty?(path)
    end
  end

  describe "get_current_branch/1" do
    test "returns branch name" do
      path = Path.join(System.tmp_dir!(), "branch_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      assert {:ok, branch} = LocalGit.get_current_branch(path)
      assert branch in ["main", "master"]
    end
  end

  describe "get_last_commit/1" do
    test "returns commit hash" do
      path = Path.join(System.tmp_dir!(), "commit_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      assert {:ok, hash} = LocalGit.get_last_commit(path)
      assert is_binary(hash)
      assert String.length(hash) >= 7
    end
  end

  describe "get_last_commit_date/1" do
    test "returns commit date" do
      path = Path.join(System.tmp_dir!(), "date_repo_#{:rand.uniform(10000)}")
      create_test_repo(path)
      on_exit(fn -> cleanup_test_repo(path) end)

      assert {:ok, date} = LocalGit.get_last_commit_date(path)
      assert %DateTime{} = date
    end
  end

  describe "discover_repos/1" do
    test "finds repos in directory" do
      base = Path.join(System.tmp_dir!(), "discover_#{:rand.uniform(10000)}")
      File.mkdir_p!(base)

      # Create some repos
      create_test_repo(Path.join(base, "repo1"))
      create_test_repo(Path.join(base, "repo2"))

      # Create non-repo
      File.mkdir_p!(Path.join(base, "not-a-repo"))

      on_exit(fn -> File.rm_rf!(base) end)

      repos = LocalGit.discover_repos(base)

      assert length(repos) == 2
      assert Enum.any?(repos, &String.ends_with?(&1, "repo1"))
      assert Enum.any?(repos, &String.ends_with?(&1, "repo2"))
    end

    test "respects max depth" do
      base = Path.join(System.tmp_dir!(), "depth_#{:rand.uniform(10000)}")
      File.mkdir_p!(base)

      # Create nested repos
      create_test_repo(Path.join(base, "level1"))
      create_test_repo(Path.join([base, "a", "b", "c", "deep"]))

      on_exit(fn -> File.rm_rf!(base) end)

      # With default depth, should find level1
      repos = LocalGit.discover_repos(base, max_depth: 1)
      assert length(repos) == 1

      # With more depth, should find both
      all_repos = LocalGit.discover_repos(base, max_depth: 5)
      assert length(all_repos) == 2
    end

    test "excludes specified patterns" do
      base = Path.join(System.tmp_dir!(), "exclude_#{:rand.uniform(10000)}")
      File.mkdir_p!(base)

      create_test_repo(Path.join(base, "good-repo"))
      create_test_repo(Path.join(base, "node_modules"))

      on_exit(fn -> File.rm_rf!(base) end)

      repos = LocalGit.discover_repos(base, exclude: ["node_modules"])

      assert length(repos) == 1
      assert hd(repos) |> String.ends_with?("good-repo")
    end

    test "excludes glob patterns with path segments" do
      base = Path.join(System.tmp_dir!(), "exclude_glob_#{:rand.uniform(10000)}")
      File.mkdir_p!(base)

      create_test_repo(Path.join(base, "keep-repo"))
      create_test_repo(Path.join(base, "skip-repo"))

      on_exit(fn -> File.rm_rf!(base) end)

      repos = LocalGit.discover_repos(base, exclude: ["**/skip-repo/**"])

      assert length(repos) == 1
      assert hd(repos) |> String.ends_with?("keep-repo")
    end
  end
end
