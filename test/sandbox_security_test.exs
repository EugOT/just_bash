defmodule JustBash.SandboxSecurityTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests that the untrusted bash script cannot observe or manipulate
  JustBash internals, and that network sandboxing is enforced correctly.

  Threat model: the Elixir caller is trusted. The bash script is not.
  """

  alias JustBash.MockHttpClient

  # ---------------------------------------------------------------------------
  # Sentinel keys hidden from scripts
  # ---------------------------------------------------------------------------

  describe "sentinel keys hidden from scripts" do
    test "__STDIN__ is not readable by a script during pipeline execution" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, "echo secret | while read line; do echo $__STDIN__; done")
      refute result.stdout =~ "secret"
    end

    test "__STDIN__ is not exposed via printenv" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, "echo hi | while read line; do printenv __STDIN__; done")
      refute result.stdout =~ "hi"
    end

    test "__locals__ is not readable by a script" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, "f() { local x=1; echo $__locals__; }; f")
      assert String.trim(result.stdout) == ""
    end

    test "__locals__ cannot be set by a script to corrupt function scoping" do
      bash = JustBash.new()

      {result, _} =
        JustBash.exec(bash, "export __locals__=corrupted; f() { local x=42; echo $x; }; f")

      assert String.trim(result.stdout) == "42"
    end

    test "__assoc__ marker keys are not visible via printenv" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, "declare -A arr; arr[k]=v; printenv | grep __assoc__")
      assert result.stdout == ""
    end

    test "no sentinel keys appear in env command output" do
      bash = JustBash.new()
      {result, _} = JustBash.exec(bash, "env | grep '^__'")
      assert result.stdout == ""
    end
  end

  # ---------------------------------------------------------------------------
  # HTTPS-only enforcement
  # ---------------------------------------------------------------------------

  describe "HTTPS enforced for network requests" do
    test "http:// URL is blocked by default even when host is in allow_list" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["example.com"]},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "plaintext data"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl http://example.com/data")
          assert result.exit_code != 0
          assert result.stderr =~ "https"
          refute result.stdout =~ "plaintext data"
        end
      )
    end

    test "https:// URL succeeds when host is in allow_list" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["example.com"]},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "secure data"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl https://example.com/data")
          assert result.exit_code == 0
          assert result.stdout =~ "secure data"
        end
      )
    end

    test "http:// URL is allowed when caller sets allow_insecure: true" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["example.com"], allow_insecure: true},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "insecure data"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl http://example.com/data")
          assert result.exit_code == 0
          assert result.stdout =~ "insecure data"
        end
      )
    end
  end

  # ---------------------------------------------------------------------------
  # -k / --insecure removed from script control
  # ---------------------------------------------------------------------------

  describe "-k/--insecure flag not available to scripts" do
    test "curl -k is rejected as unknown flag" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["example.com"]},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "response"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl -k https://example.com/")
          assert result.exit_code != 0
          assert result.stderr =~ "unknown" or result.stderr =~ "invalid"
        end
      )
    end

    test "curl --insecure is rejected as unknown flag" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["example.com"]},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "response"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl --insecure https://example.com/")
          assert result.exit_code != 0
        end
      )
    end
  end

  # ---------------------------------------------------------------------------
  # allow_list safe-by-default
  # ---------------------------------------------------------------------------

  describe "network allow_list safe-by-default" do
    test "enabled: true with no allow_list blocks all requests" do
      bash =
        JustBash.new(
          network: %{enabled: true},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "should not reach"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl https://example.com/")
          assert result.exit_code != 0
          assert result.stderr =~ "not allowed"
          refute result.stdout =~ "should not reach"
        end
      )
    end

    test "enabled: true with allow_list: :all permits any host" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: :all},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn _req -> {:ok, %{status: 200, headers: %{}, body: "ok"}} end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl https://example.com/")
          assert result.exit_code == 0
          assert result.stdout =~ "ok"
        end
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Redirect allow_list enforcement
  # ---------------------------------------------------------------------------

  describe "redirect targets checked against allow_list" do
    test "redirect to a non-allowed host is blocked" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["allowed.com"]},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn req ->
          case req.url do
            "https://allowed.com/redirect" ->
              {:ok,
               %{
                 status: 301,
                 headers: %{"location" => ["https://evil.com/secret"]},
                 body: ""
               }}

            _ ->
              {:ok, %{status: 200, headers: %{}, body: "exfiltrated"}}
          end
        end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl -L https://allowed.com/redirect")
          refute result.stdout =~ "exfiltrated"
          assert result.exit_code != 0 or result.stderr =~ "not allowed"
        end
      )
    end

    test "redirect to an allowed host succeeds" do
      bash =
        JustBash.new(
          network: %{enabled: true, allow_list: ["allowed.com", "also-allowed.com"]},
          http_client: MockHttpClient
        )

      MockHttpClient.with_mock(
        fn req ->
          case req.url do
            "https://allowed.com/redirect" ->
              {:ok,
               %{
                 status: 301,
                 headers: %{"location" => ["https://also-allowed.com/data"]},
                 body: ""
               }}

            "https://also-allowed.com/data" ->
              {:ok, %{status: 200, headers: %{}, body: "ok data"}}
          end
        end,
        fn ->
          {result, _} = JustBash.exec(bash, "curl -L https://allowed.com/redirect")
          assert result.stdout =~ "ok data"
        end
      )
    end
  end
end
