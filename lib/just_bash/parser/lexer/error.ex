defmodule JustBash.Parser.Lexer.Error do
  @moduledoc """
  Structured error for lexer failures.

  Raised by `tokenize!/1` and returned as `{:error, t()}` by `tokenize/1`.
  Callers can pattern-match on `type` and `construct` for programmatic handling.
  """

  @type construct ::
          :single_quote
          | :double_quote
          | :backtick
          | :command_substitution
          | :parameter_expansion
          | :arithmetic
          | :expression
          | nil

  @type error_type :: :unterminated | :nesting_depth | :unexpected_character | :expected_delimiter

  @type t :: %__MODULE__{
          type: error_type(),
          construct: construct(),
          line: non_neg_integer(),
          column: non_neg_integer(),
          message: String.t()
        }

  defexception [:type, :construct, :line, :column, :message]

  @doc false
  def unterminated(construct, line \\ 0, column \\ 0) do
    %__MODULE__{
      type: :unterminated,
      construct: construct,
      line: line,
      column: column,
      message: "unterminated #{construct_label(construct)}"
    }
  end

  @doc false
  def nesting_depth(construct, line \\ 0, column \\ 0) do
    %__MODULE__{
      type: :nesting_depth,
      construct: construct,
      line: line,
      column: column,
      message: "nesting depth exceeded in #{construct_label(construct)}"
    }
  end

  @doc false
  def unexpected_character(char, line, column) do
    %__MODULE__{
      type: :unexpected_character,
      construct: nil,
      line: line,
      column: column,
      message: "unexpected character #{inspect(char)} at #{line}:#{column}"
    }
  end

  @doc false
  def expected_delimiter(line, column) do
    %__MODULE__{
      type: :expected_delimiter,
      construct: nil,
      line: line,
      column: column,
      message: "expected heredoc delimiter at #{line}:#{column}"
    }
  end

  defp construct_label(:single_quote), do: "single quote"
  defp construct_label(:double_quote), do: "double quote"
  defp construct_label(:backtick), do: "backtick command substitution"
  defp construct_label(:command_substitution), do: "command substitution"
  defp construct_label(:parameter_expansion), do: "parameter expansion"
  defp construct_label(:arithmetic), do: "arithmetic expansion"
  defp construct_label(:expression), do: "expression"
end
