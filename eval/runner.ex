defmodule JustBash.Eval.Runner do
  @moduledoc """
  Runs eval tasks and reports results.
  """

  alias JustBash.Eval.{Agent, Tasks, Validator}
  alias JustBash.Fs.InMemoryFs

  @type validator_result :: Validator.validator_result()

  @type task_result :: %{
          name: String.t(),
          passed: boolean(),
          validators: [validator_result()],
          turns: non_neg_integer(),
          error: String.t() | nil,
          time_ms: non_neg_integer()
        }

  @doc """
  Run all eval tasks and return results.
  """
  @spec run_all(keyword()) :: [task_result()]
  def run_all(opts \\ []) do
    tasks = Keyword.get(opts, :tasks, Tasks.all())
    Enum.map(tasks, &run_task(&1, opts))
  end

  @doc """
  Run a single eval task by name.
  """
  @spec run_by_name(String.t(), keyword()) :: task_result()
  def run_by_name(name, opts \\ []) do
    case Enum.find(Tasks.all(), &(&1.name == name)) do
      nil ->
        %{
          name: name,
          passed: false,
          validators: [],
          turns: 0,
          error: "Task not found",
          time_ms: 0
        }

      task ->
        run_task(task, opts)
    end
  end

  @doc """
  Run a single task and return the result.
  """
  @spec run_task(Tasks.task(), keyword()) :: task_result()
  def run_task(task, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)

    if verbose, do: IO.puts("\n--- Running: #{task.name} ---")

    start = System.monotonic_time(:millisecond)
    bash = setup_filesystem(task.files)

    try do
      case Agent.run(task.description, Keyword.merge(opts, bash: bash)) do
        {:ok, agent_result} ->
          time_ms = System.monotonic_time(:millisecond) - start
          validator_results = Validator.run_all(task.validators, agent_result)
          all_passed = Enum.all?(validator_results, & &1.passed)

          if verbose,
            do: print_validator_results(task.name, validator_results, agent_result.turns, time_ms)

          %{
            name: task.name,
            passed: all_passed,
            validators: validator_results,
            turns: agent_result.turns,
            error: nil,
            time_ms: time_ms
          }

        {:error, reason} ->
          time_ms = System.monotonic_time(:millisecond) - start
          error_msg = inspect(reason)
          if verbose, do: IO.puts("  ERROR: #{error_msg} (#{time_ms}ms)")

          %{
            name: task.name,
            passed: false,
            validators: [],
            turns: 0,
            error: error_msg,
            time_ms: time_ms
          }
      end
    rescue
      e ->
        time_ms = System.monotonic_time(:millisecond) - start
        error_msg = "CRASH: #{Exception.message(e)}"
        if verbose, do: IO.puts("  #{error_msg} (#{time_ms}ms)")

        %{
          name: task.name,
          passed: false,
          validators: [],
          turns: 0,
          error: error_msg,
          time_ms: time_ms
        }
    end
  end

  @doc """
  Print a summary table of results.
  """
  @spec print_summary([task_result()]) :: :ok
  def print_summary(results) do
    passed = Enum.count(results, & &1.passed)
    total = length(results)
    total_time = results |> Enum.map(& &1.time_ms) |> Enum.sum()

    total_validators = results |> Enum.flat_map(& &1.validators) |> length()
    passed_validators = results |> Enum.flat_map(& &1.validators) |> Enum.count(& &1.passed)

    IO.puts("\n" <> String.duplicate("=", 70))

    IO.puts(
      "EVAL RESULTS: #{passed}/#{total} tasks passed | #{passed_validators}/#{total_validators} validators passed | #{total_time}ms"
    )

    IO.puts(String.duplicate("=", 70))

    for r <- results do
      status = if r.passed, do: color("PASS", :green), else: color("FAIL", :red)
      IO.puts("  #{status}  #{r.name} (#{r.turns} turns, #{r.time_ms}ms)")

      if r.error do
        IO.puts("        #{color(r.error, :red)}")
      end

      for v <- r.validators do
        v_status = if v.passed, do: color("ok", :green), else: color("FAIL", :red)
        line = "        #{v_status} #{v.name}"
        line = if v.error, do: line <> " — #{v.error}", else: line
        IO.puts(line)
      end
    end

    IO.puts(String.duplicate("=", 70))
    :ok
  end

  # --- Private ---

  defp print_validator_results(_task_name, results, turns, time_ms) do
    all_passed = Enum.all?(results, & &1.passed)
    status = if all_passed, do: "PASS", else: "FAIL"
    IO.puts("  #{status} (#{turns} turns, #{time_ms}ms)")

    for r <- results do
      indicator = if r.passed, do: color("ok", :green), else: color("FAIL", :red)
      line = "    #{indicator} #{r.name}"
      line = if r.error, do: line <> " — #{r.error}", else: line
      IO.puts(line)
    end
  end

  defp setup_filesystem(files) do
    bash = JustBash.new()

    fs =
      Enum.reduce(files, bash.fs, fn {path, content}, fs ->
        fs = ensure_parent_dirs(fs, path)
        {:ok, fs} = InMemoryFs.write_file(fs, path, content)
        fs
      end)

    %{bash | fs: fs}
  end

  defp ensure_parent_dirs(fs, path) do
    path
    |> Path.dirname()
    |> Path.split()
    |> Enum.reduce({"", fs}, fn segment, {current, fs} ->
      dir = Path.join(current, segment)

      case InMemoryFs.mkdir(fs, dir) do
        {:ok, fs} -> {dir, fs}
        {:error, :eexist} -> {dir, fs}
      end
    end)
    |> elem(1)
  end

  defp color(text, :green), do: IO.ANSI.green() <> text <> IO.ANSI.reset()
  defp color(text, :red), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
end
