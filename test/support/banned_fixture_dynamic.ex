defmodule BannedCallTracer.Fixture.Dynamic do
  @moduledoc false
  # Intentional dynamic dispatch of a banned module for grep test regression testing.
  # This must be caught by the grep check, NOT the BEAM walker.
  def run do
    mod = File
    mod.read("/etc/passwd")
  end
end
