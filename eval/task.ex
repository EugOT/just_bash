defmodule JustBash.Eval.Task do
  @moduledoc """
  Behaviour for eval task modules. Each module provides a list of task definitions.
  """

  @type task :: %{
          name: String.t(),
          description: String.t(),
          files: %{String.t() => String.t()},
          validators: [JustBash.Eval.Validator.validator()]
        }

  @callback tasks() :: [task()]
end
