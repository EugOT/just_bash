defmodule JustBash.MockHttpClient do
  @moduledoc false
  @behaviour JustBash.HttpClient

  @doc """
  HTTP client for tests. Looks up the response function from the process dictionary
  under the key :mock_http_client_fun, set via `with_mock/2`.
  """
  @impl JustBash.HttpClient
  def request(req) do
    case Process.get(:mock_http_client_fun) do
      nil -> {:error, %{reason: :no_mock_configured}}
      fun -> fun.(req)
    end
  end

  @doc """
  Runs `fun` with the given mock response function registered for this process.
  """
  def with_mock(response_fun, fun) do
    Process.put(:mock_http_client_fun, response_fun)

    try do
      fun.()
    after
      Process.delete(:mock_http_client_fun)
    end
  end
end
