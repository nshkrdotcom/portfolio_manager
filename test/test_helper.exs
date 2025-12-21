ExUnit.start()

# Ensure tmp directories are cleaned up after tests
ExUnit.after_suite(fn _ ->
  # Clean up any test portfolio directories
  tmp_dir = System.tmp_dir!()

  tmp_dir
  |> File.ls!()
  |> Enum.filter(&String.starts_with?(&1, "portfolio_test_"))
  |> Enum.each(fn dir ->
    File.rm_rf!(Path.join(tmp_dir, dir))
  end)
end)
