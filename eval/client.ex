defmodule JustBash.Eval.Client do
  @moduledoc """
  Minimal Anthropic API client for the eval agent loop.
  """

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"

  def chat(messages, opts \\ []) do
    api_key = api_key!()
    tools = Keyword.get(opts, :tools, [])
    system = Keyword.get(opts, :system, nil)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    body =
      %{
        model: @model,
        max_tokens: max_tokens,
        messages: messages
      }
      |> maybe_put(:system, system)
      |> maybe_put(:tools, if(tools != [], do: tools))

    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_key! do
    case Application.get_env(:just_bash, :anthropic_api_key) ||
           System.get_env("ANTHROPIC_API_KEY") do
      nil -> raise "Missing ANTHROPIC_API_KEY — set it in env or config/runtime.exs"
      "" -> raise "ANTHROPIC_API_KEY is empty"
      key -> key
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
