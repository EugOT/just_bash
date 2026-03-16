defmodule BannedCallTracer.Fixture do
  @moduledoc false
  # This module intentionally contains a banned call so that
  # BannedCallTracerTest can assert the tracer detects it.
  def run, do: System.get_env("HOME")
end
