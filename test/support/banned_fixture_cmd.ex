defmodule BannedCallTracer.Fixture.Cmd do
  @moduledoc false
  # Intentional banned call for tracer regression testing.
  def run, do: System.cmd("echo", ["hello"])
end
