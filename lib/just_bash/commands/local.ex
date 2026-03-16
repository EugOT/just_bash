defmodule JustBash.Commands.Local do
  @moduledoc """
  The `local` builtin command - declare local variables within a function.

  In JustBash, `local` simply performs variable assignments in the current scope.
  Since function calls already use isolated environments, this matches the expected
  behavior of local variable declarations.
  """
  @behaviour JustBash.Commands.Command

  alias JustBash.Commands.Command

  @impl true
  def names, do: ["local", "declare", "typeset"]

  @impl true
  def execute(bash, args, _stdin) do
    {flags, rest} = extract_flags(args)
    bash = process_declarations(bash, rest, flags)
    {Command.ok(""), bash}
  end

  defp extract_flags(args) do
    Enum.split_with(args, &String.starts_with?(&1, "-"))
  end

  defp process_declarations(bash, args, flags) do
    is_assoc = "-A" in flags

    Enum.reduce(args, bash, fn arg, acc ->
      process_arg(arg, acc, is_assoc)
    end)
  end

  defp process_arg(arg, bash, is_assoc) do
    case String.split(arg, "=", parts: 2) do
      [name, value] when name != "" ->
        bash
        |> put_env(name, value)
        |> track_local(name)
        |> maybe_mark_assoc(name, is_assoc)

      [name] when name != "" ->
        bash
        |> put_env(name, "")
        |> track_local(name)
        |> maybe_mark_assoc(name, is_assoc)

      _ ->
        bash
    end
  end

  defp put_env(bash, name, value), do: %{bash | env: Map.put(bash.env, name, value)}

  defp maybe_mark_assoc(bash, name, true) do
    new_assoc = MapSet.put(bash.interpreter.assoc_arrays, name)
    %{bash | interpreter: %{bash.interpreter | assoc_arrays: new_assoc}}
  end

  defp maybe_mark_assoc(bash, _name, false), do: bash

  # Register a variable name as local so execute_function can revert it on return.
  # Only has effect when inside a function call (locals tracker is a MapSet).
  # Outside a function, local/declare still sets the variable but doesn't track it.
  defp track_local(bash, name) do
    new_locals = MapSet.put(bash.interpreter.locals, name)
    %{bash | interpreter: %{bash.interpreter | locals: new_locals}}
  end
end
