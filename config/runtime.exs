import Config

config :just_bash,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")
