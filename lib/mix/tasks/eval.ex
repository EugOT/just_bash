defmodule Mix.Tasks.JustBash.Eval do
  @shortdoc "Run JustBash agent evals"
  @moduledoc """
  Runs the JustBash agent eval suite.

  ## Usage

      mix just_bash.eval                       # Run all evals
      mix just_bash.eval --task jq_transform   # Run a specific eval
      mix just_bash.eval --verbose             # Verbose output

  Requires ANTHROPIC_API_KEY in environment or config.
  """

  use Mix.Task

  alias JustBash.Eval.Runner

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, strict: [task: :string, verbose: :boolean])

    verbose = Keyword.get(opts, :verbose, true)
    runner_opts = [verbose: verbose]

    results =
      case Keyword.get(opts, :task) do
        nil ->
          Runner.run_all(runner_opts)

        name ->
          [Runner.run_by_name(name, runner_opts)]
      end

    Runner.print_summary(results)

    if Enum.all?(results, & &1.passed) do
      :ok
    else
      Mix.raise("Some evals failed")
    end
  end
end
