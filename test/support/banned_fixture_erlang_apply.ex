defmodule BannedCallTracer.Fixture.ErlangApply do
  @moduledoc false
  # Intentional banned call via :erlang.apply/3 for tracer regression testing.
  def run, do: :erlang.apply(File, :read, ["/etc/passwd"])
end
