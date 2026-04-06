defmodule JustBash.Parser.LexerRobustnessTest do
  @moduledoc """
  Robustness tests for the hand-written lexer.

  Covers unterminated constructs, nesting depth limits, heredoc edge cases,
  and multi-byte safety. These tests target the lexer directly, not the
  full interpreter, because the lexer is the first line of defense against
  malformed or adversarial input.
  """
  use ExUnit.Case, async: true

  alias JustBash.Parser.Lexer
  alias JustBash.Parser.Lexer.Error, as: LexerError

  defp tokenize!(input), do: Lexer.tokenize!(input)

  # ── Unterminated Constructs ──────────────────────────────────────────
  #
  # Each of these must return a structured LexerError — silently producing
  # a token from malformed input leads to confusing downstream failures.

  describe "unterminated constructs raise LexerError" do
    test "unterminated $( raises with :command_substitution" do
      assert {:error, %LexerError{type: :unterminated, construct: :command_substitution}} =
               Lexer.tokenize("echo $(")
    end

    test "unterminated $( with content raises" do
      assert {:error, %LexerError{type: :unterminated, construct: :command_substitution}} =
               Lexer.tokenize("echo $(echo hello")
    end

    test "unterminated ${ raises with :parameter_expansion" do
      assert {:error, %LexerError{type: :unterminated, construct: :parameter_expansion}} =
               Lexer.tokenize("echo ${")
    end

    test "unterminated ${VAR raises" do
      assert {:error, %LexerError{type: :unterminated, construct: :parameter_expansion}} =
               Lexer.tokenize("echo ${VAR")
    end

    test "unterminated $(( raises with :arithmetic" do
      assert {:error, %LexerError{type: :unterminated, construct: :arithmetic}} =
               Lexer.tokenize("echo $((1 + 2")
    end

    test "unterminated backtick raises with :backtick" do
      assert {:error, %LexerError{type: :unterminated, construct: :backtick}} =
               Lexer.tokenize("echo `hostname")
    end

    test "unterminated single quote raises with :single_quote" do
      assert {:error, %LexerError{type: :unterminated, construct: :single_quote}} =
               Lexer.tokenize("echo 'hello")
    end

    test "unterminated double quote raises with :double_quote" do
      assert {:error, %LexerError{type: :unterminated, construct: :double_quote}} =
               Lexer.tokenize("echo \"hello")
    end

    test "unterminated $( nested inside double quotes raises" do
      assert {:error, %LexerError{type: :unterminated}} =
               Lexer.tokenize("echo \"$(echo hello\"")
    end

    test "unterminated ${ nested inside double quotes raises" do
      assert {:error, %LexerError{type: :unterminated}} =
               Lexer.tokenize("echo \"${VAR\"")
    end

    test "error message is human-readable" do
      {:error, error} = Lexer.tokenize("echo $(")
      assert error.message =~ "unterminated"
      assert error.message =~ "command substitution"
    end

    test "errors include line and column of the opening construct" do
      {:error, error} = Lexer.tokenize("echo 'hello")
      assert error.line == 1
      assert error.column == 6

      {:error, error} = Lexer.tokenize("echo \"hello")
      assert error.line == 1
      assert error.column == 6

      {:error, error} = Lexer.tokenize("echo `hello")
      assert error.line == 1
      assert error.column == 6

      {:error, error} = Lexer.tokenize("echo $(hello")
      assert error.line == 1
      assert error.column == 6

      {:error, error} = Lexer.tokenize("echo ${hello")
      assert error.line == 1
      assert error.column == 6

      {:error, error} = Lexer.tokenize("echo $((1 + 2")
      assert error.line == 1
      assert error.column == 6
    end

    test "multiline errors report correct line" do
      {:error, error} = Lexer.tokenize("line1\nline2\necho 'hello")
      assert error.line == 3
      assert error.column == 6
    end
  end

  # ── Nesting Depth Protection ─────────────────────────────────────────

  describe "nesting depth limits" do
    test "deeply nested $(...) raises :nesting_depth" do
      deep = "echo " <> String.duplicate("$(", 300) <> "x" <> String.duplicate(")", 300)

      assert {:error, %LexerError{type: :nesting_depth}} = Lexer.tokenize(deep)
    end

    test "deeply nested ${...} raises :nesting_depth" do
      deep = "echo " <> String.duplicate("${", 300) <> "x" <> String.duplicate("}", 300)

      assert {:error, %LexerError{type: :nesting_depth}} = Lexer.tokenize(deep)
    end

    test "deeply nested ((...)) raises" do
      deep = "echo " <> String.duplicate("$((", 300) <> "1" <> String.duplicate("))", 300)

      assert {:error, %LexerError{}} = Lexer.tokenize(deep)
    end

    test "moderate nesting succeeds" do
      deep = "echo " <> String.duplicate("$(", 20) <> "x" <> String.duplicate(")", 20)
      assert {:ok, tokens} = Lexer.tokenize(deep)
      assert tokens != []
    end
  end

  # ── Heredoc Edge Cases ──────────────────────────────────────────────

  describe "heredoc edge cases" do
    test "heredoc at end of input with no final newline" do
      input = "cat <<EOF\nhello\nEOF"
      tokens = tokenize!(input)
      content_tokens = Enum.filter(tokens, &(&1.type == :heredoc_content))
      assert [content] = content_tokens
      assert content.value == "hello\n"
    end

    test "heredoc with empty body" do
      input = "cat <<EOF\nEOF\n"
      tokens = tokenize!(input)
      content_tokens = Enum.filter(tokens, &(&1.type == :heredoc_content))
      assert [content] = content_tokens
      assert content.value == ""
    end

    test "heredoc with empty delimiter is rejected" do
      assert {:error, %LexerError{type: :expected_delimiter}} =
               Lexer.tokenize("cat << \n")
    end

    test "multiple heredocs on same line" do
      input = "diff <(cat <<A\nfoo\nA\n) <(cat <<B\nbar\nB\n)"
      tokens = tokenize!(input)
      content_tokens = Enum.filter(tokens, &(&1.type == :heredoc_content))
      assert length(content_tokens) == 2
    end

    test "heredoc with tab-stripped delimiter (<<-)" do
      input = "cat <<-EOF\n\thello\n\tEOF\n"
      tokens = tokenize!(input)
      content_tokens = Enum.filter(tokens, &(&1.type == :heredoc_content))
      assert [content] = content_tokens
      # <<- strips leading tabs from body lines
      assert content.value == "hello\n"
    end

    test "heredoc body with all ASCII special chars" do
      specials = "!@#$%^&*()_+-=[]{}|;':\",./<>?`~"

      input = "cat <<'EOF'\n#{specials}\nEOF\n"
      tokens = tokenize!(input)
      content_tokens = Enum.filter(tokens, &(&1.type == :heredoc_content))
      assert hd(content_tokens).value == specials <> "\n"
    end

    test "heredoc missing terminator still produces content" do
      input = "cat <<EOF\nline 1\nline 2\n"
      tokens = tokenize!(input)
      content_tokens = Enum.filter(tokens, &(&1.type == :heredoc_content))
      assert [content] = content_tokens
      assert content.value =~ "line 1"
    end
  end

  # ── Multi-byte Safety ───────────────────────────────────────────────

  describe "multi-byte character safety" do
    test "emoji in word" do
      tokens = tokenize!("echo 🐾")
      values = Enum.map(tokens, & &1.value)
      assert "🐾" in values
    end

    test "CJK characters in word" do
      tokens = tokenize!("echo 日本語")
      values = Enum.map(tokens, & &1.value)
      assert "日本語" in values
    end

    test "emoji in double-quoted string" do
      tokens = tokenize!("echo \"hello 🐾 world\"")
      word_token = Enum.find(tokens, &(&1.type == :word))
      assert word_token.value =~ "🐾"
    end

    test "emoji in single-quoted string" do
      tokens = tokenize!("echo '🐾🎉'")
      word_token = Enum.find(tokens, &(&1.type == :word))
      assert word_token.value == "🐾🎉"
    end

    test "multi-byte in variable assignment" do
      tokens = tokenize!("MSG=héllo")
      assign = Enum.find(tokens, &(&1.type == :assignment_word))
      assert assign.value == "MSG=héllo"
    end

    test "mixed ASCII and multi-byte in heredoc body" do
      input = "cat <<'EOF'\nHello 🌍 World café\nEOF\n"
      tokens = tokenize!(input)
      content = Enum.find(tokens, &(&1.type == :heredoc_content))
      assert content.value == "Hello 🌍 World café\n"
    end
  end

  # ── Valid Constructs Still Work ─────────────────────────────────────

  describe "correctly terminated constructs still work" do
    test "command substitution $(...)" do
      tokens = tokenize!("echo $(hostname)")
      word = Enum.find(tokens, &(&1.value =~ "hostname"))
      assert word != nil
    end

    test "parameter expansion ${...}" do
      tokens = tokenize!("echo ${VAR:-default}")
      word = Enum.find(tokens, &(&1.value =~ "VAR"))
      assert word != nil
    end

    test "arithmetic expansion $(( ... ))" do
      tokens = tokenize!("echo $((1 + 2))")
      word = Enum.find(tokens, &(&1.value =~ "1 + 2"))
      assert word != nil
    end

    test "backtick substitution" do
      tokens = tokenize!("echo `hostname`")
      word = Enum.find(tokens, &(&1.value =~ "hostname"))
      assert word != nil
    end

    test "nested $( inside double quotes" do
      tokens = tokenize!(~s[echo "hello $(echo world)"])
      word = Enum.find(tokens, &(&1.type == :word && &1.value =~ "hello"))
      assert word != nil
    end

    test "nested parameter expansion inside double quotes" do
      tokens = tokenize!(~s[echo "hello ${VAR}"])
      word = Enum.find(tokens, &(&1.type == :word && &1.value =~ "hello"))
      assert word != nil
    end

    test "escaped backtick inside backticks" do
      tokens = tokenize!(~S[echo `echo \`date\``])
      assert length(tokens) > 1
    end

    test "escaped backtick inside double-quoted backtick" do
      # echo "`echo \`date\``" — backtick with escapes inside double quotes
      tokens = tokenize!(~S[echo "`echo \`date\``"])
      word = Enum.find(tokens, &(&1.type == :word))
      assert word != nil
      assert word.value =~ "date"
    end

    test "escaped backtick inside $() inside double quotes" do
      # echo "$(echo `echo \`inner\``)" — backtick with escapes inside $() inside double quotes
      tokens = tokenize!(~S[echo "$(echo `echo \`inner\``)"])
      word = Enum.find(tokens, &(&1.type == :word))
      assert word != nil
      assert word.value =~ "inner"
    end

    test "complex nested: double quote containing $( containing double quote" do
      tokens = tokenize!(~s[echo "$(echo "inner")"])
      assert length(tokens) > 1
    end
  end

  # ── Large Input / Tail Recursion Safety ─────────────────────────────

  describe "tail recursion safety — large inputs do not blow the stack" do
    @tag timeout: 15_000

    test "500KB double-quoted string (find_close_dq)" do
      big = "echo \"" <> String.duplicate("x", 500_000) <> "\""
      tokens = tokenize!(big)
      word = Enum.find(tokens, &(&1.type == :word))
      assert byte_size(word.value) == 500_000
    end

    test "500KB single-quoted string (skip_past_sq via skip_balanced)" do
      big = "echo $(" <> "'" <> String.duplicate("a", 500_000) <> "'" <> ")"
      tokens = tokenize!(big)
      assert tokens != []
    end

    test "500KB ANSI-C quoted string (read_ansi_c_content)" do
      big = "echo $'" <> String.duplicate("x", 500_000) <> "'"
      tokens = tokenize!(big)
      word = Enum.find(tokens, &(&1.type == :word))
      assert byte_size(word.value) == 500_000
    end

    test "500KB plain word (read_plain / do_read_plain)" do
      big = "echo " <> String.duplicate("a", 500_000)
      tokens = tokenize!(big)
      word = Enum.find(tokens, &(&1.value =~ ~r/^a{100}/))
      assert byte_size(word.value) == 500_000
    end

    test "500KB comment (scan_to_newline)" do
      big = "# " <> String.duplicate("x", 500_000) <> "\necho ok"
      tokens = tokenize!(big)
      echo = Enum.find(tokens, &(&1.value == "echo"))
      assert echo != nil
    end

    test "500KB heredoc body (do_read_heredoc_body / read_line_at)" do
      body = String.duplicate("line of content here\n", 25_000)
      big = "cat <<EOF\n" <> body <> "EOF\n"
      tokens = tokenize!(big)
      content = Enum.find(tokens, &(&1.type == :heredoc_content))
      assert byte_size(content.value) > 400_000
    end

    test "1000 sequential command substitutions (find_close_dq mutual recursion)" do
      pieces = for _ <- 1..1000, do: "$(echo \"x\")"
      big = "echo " <> Enum.join(pieces)
      tokens = tokenize!(big)
      assert tokens != []
    end

    test "100K levels of nesting with quotes (skip_balanced + skip_past_dq)" do
      inner = "x"

      s =
        Enum.reduce(1..100_000, inner, fn _, acc ->
          "\"$(echo #{acc})\""
        end)

      input = "echo #{s}"
      tokens = tokenize!(input)
      assert tokens != []
    end

    test "500KB backtick expression (find_close_backtick)" do
      big = "echo `" <> String.duplicate("x", 500_000) <> "`"
      tokens = tokenize!(big)
      assert tokens != []
    end

    test "500KB parameter expansion (skip_balanced with braces)" do
      big = "echo ${VAR:-" <> String.duplicate("x", 500_000) <> "}"
      tokens = tokenize!(big)
      assert tokens != []
    end
  end

  # ── Special Variable Expansion ────────────────────────────────────
  #
  # Special variables ($#, $$, $?, etc.) followed by text must expand
  # correctly end-to-end. The lexer produces one word token ("$#args"),
  # but internally splits "$#" and "args" as separate parts so the
  # expansion layer handles the boundary correctly.

  describe "special variable expansion end-to-end" do
    test "$# followed by literal produces correct output" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, ~S(echo $#args))
      assert result.stdout == "0args\n"
    end

    test "$$ followed by literal produces PID + literal" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, ~S(echo $$x))
      assert result.stdout =~ ~r/^[0-9]+x\n$/
    end

    test "$? followed by literal produces exit code + literal" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, ~S(true; echo $?foo))
      assert result.stdout == "0foo\n"
    end

    test "$@ followed by literal in function" do
      bash = JustBash.new()

      {result, _} =
        JustBash.exec(bash, """
        f() { for a in "$@"; do echo "$a"; done; }
        f x y z
        """)

      assert result.stdout == "x\ny\nz\n"
    end

    test "regular variable $VAR_NAME consumes full identifier" do
      tokens = tokenize!("echo $MY_VAR123")
      values = Enum.map(tokens, & &1.value)
      assert "$MY_VAR123" in values
    end

    test "bare $ before non-variable character" do
      tokens = tokenize!("echo $ end")
      values = Enum.map(tokens, & &1.value)
      assert "$" in values
    end
  end
end
