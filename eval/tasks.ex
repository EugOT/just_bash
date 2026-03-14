defmodule JustBash.Eval.Tasks do
  @moduledoc """
  Eval task registry. Collects tasks from all category modules.

  Categories:
  - JsonProcessing — jq, JSON/CSV conversion, schema validation
  - TextProcessing — sed, grep, word frequency, INI/changelog
  - FileOperations — file rename, symlinks, flattening, tree snapshots
  - DataPipelines — templating, dedup, joins, ETL, checksums
  - Reporting — Dockerfile parsing, crontab, markdown, access logs
  - ShellFeatures — functions, loops, comm, paste, tee, xargs
  """

  alias JustBash.Eval.Tasks.{
    DataPipelines,
    FileOperations,
    JsonProcessing,
    Reporting,
    ShellFeatures,
    TextProcessing
  }

  @task_modules [
    JsonProcessing,
    TextProcessing,
    FileOperations,
    DataPipelines,
    Reporting,
    ShellFeatures
  ]

  @type task :: JustBash.Eval.Task.task()

  @doc """
  Returns all eval tasks from all category modules.
  """
  @spec all() :: [task()]
  def all do
    Enum.flat_map(@task_modules, & &1.tasks())
  end

  @doc """
  Returns the list of task category modules.
  """
  @spec modules() :: [module()]
  def modules, do: @task_modules
end
