defmodule JustBash.Eval.Tasks do
  @moduledoc """
  Eval task definitions. Each task has a description, initial filesystem state,
  and a list of validators that check the agent's output.
  """

  alias JustBash.Eval.Validator

  @type task :: %{
          name: String.t(),
          description: String.t(),
          files: %{String.t() => String.t()},
          validators: [Validator.validator()]
        }

  @doc """
  Returns all eval tasks.
  """
  @spec all() :: [task()]
  def all do
    [
      jq_transform(),
      sed_config_rewrite(),
      grep_pipeline(),
      multi_file_processing(),
      jq_api_response(),
      log_rotation(),
      install_script(),
      env_templating()
    ]
  end

  # --- jq: filter, project, sort ---

  defp jq_transform do
    %{
      name: "jq_transform",
      description: """
      You have a JSON file at /data/users.json containing an array of user objects,
      each with "name", "email", and "age" fields. Use jq to:
      1. Filter to users aged 30 or older
      2. Transform each to have only "name" and "email"
      3. Sort by name
      4. Write the result to /output/senior_users.json
      """,
      files: %{
        "/data/users.json" =>
          Jason.encode!([
            %{name: "Charlie", email: "charlie@example.com", age: 35},
            %{name: "Alice", email: "alice@example.com", age: 28},
            %{name: "Bob", email: "bob@example.com", age: 42},
            %{name: "Diana", email: "diana@example.com", age: 31},
            %{name: "Eve", email: "eve@example.com", age: 22}
          ])
      },
      validators: [
        {:command_used, "jq"},
        {:tool_call_count, :max, 6},
        {:file_contains, "/output/senior_users.json",
         [
           {:json,
            fn data ->
              cond do
                not is_list(data) ->
                  {:error, "expected array"}

                length(data) != 3 ->
                  {:error, "expected 3 users, got #{length(data)}"}

                Enum.any?(data, &Map.has_key?(&1, "age")) ->
                  {:error, "age field should be removed"}

                Enum.map(data, & &1["name"]) != ["Bob", "Charlie", "Diana"] ->
                  {:error, "wrong names or order"}

                true ->
                  :ok
              end
            end}
         ]},
        {:llm_judge,
         "Did the agent accomplish the task by using jq to filter users aged 30+, keep only name/email, and sort by name? Ignore missing output in tool results — focus on whether the commands used were correct."}
      ]
    }
  end

  # --- sed: find-and-replace in config files ---

  defp sed_config_rewrite do
    %{
      name: "sed_config_rewrite",
      description: """
      You have a configuration file at /etc/app.conf in KEY=VALUE format.
      Use sed (and any other tools) to:
      1. Change the DATABASE_HOST from "localhost" to "db.production.internal"
      2. Change the DATABASE_PORT from "5432" to "5433"
      3. Change LOG_LEVEL from "debug" to "warn"
      4. Add a new line "CACHE_ENABLED=true" at the end if it doesn't exist
      Write the result back to /etc/app.conf.
      """,
      files: %{
        "/etc/app.conf" =>
          Enum.join(
            [
              "APP_NAME=myapp",
              "DATABASE_HOST=localhost",
              "DATABASE_PORT=5432",
              "LOG_LEVEL=debug",
              "MAX_CONNECTIONS=100"
            ],
            "\n"
          )
      },
      validators: [
        {:command_used, "sed"},
        {:file_contains, "/etc/app.conf",
         [
           {:regex, ~r/DATABASE_HOST="?db\.production\.internal"?/},
           {:regex, ~r/DATABASE_PORT="?5433"?/},
           {:regex, ~r/LOG_LEVEL="?warn"?/},
           {:regex, ~r/CACHE_ENABLED="?true"?/},
           {:regex, ~r/APP_NAME="?myapp"?/},
           {:regex, ~r/MAX_CONNECTIONS="?100"?/}
         ]}
      ]
    }
  end

  # --- grep + sed + sort + uniq: log analysis pipeline ---

  defp grep_pipeline do
    %{
      name: "grep_pipeline",
      description: """
      You have a log file at /var/log/app.log. Find all ERROR lines, extract the
      unique error messages (the part after "ERROR: "), sort them alphabetically,
      and write the count of unique errors as the first line followed by each
      unique error message on its own line to /output/errors.txt.
      """,
      files: %{
        "/var/log/app.log" =>
          Enum.join(
            [
              "2024-01-01 10:00:00 INFO: Server started",
              "2024-01-01 10:01:00 ERROR: Connection refused",
              "2024-01-01 10:02:00 INFO: Request processed",
              "2024-01-01 10:03:00 ERROR: Timeout exceeded",
              "2024-01-01 10:04:00 WARN: High memory usage",
              "2024-01-01 10:05:00 ERROR: Connection refused",
              "2024-01-01 10:06:00 ERROR: Disk full",
              "2024-01-01 10:07:00 INFO: Request processed",
              "2024-01-01 10:08:00 ERROR: Timeout exceeded",
              "2024-01-01 10:09:00 ERROR: Connection refused"
            ],
            "\n"
          )
      },
      validators: [
        {:command_used, "grep"},
        {:file_contains, "/output/errors.txt",
         [
           {:not_empty},
           {:regex, ~r/Connection refused/},
           {:regex, ~r/Disk full/},
           {:regex, ~r/Timeout exceeded/}
         ]},
        {:custom, "correct_count",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/errors.txt") do
             {:ok, content} ->
               first_line = content |> String.split("\n") |> hd() |> String.trim()

               if first_line == "3",
                 do: :ok,
                 else: {:error, "first line should be '3', got '#{first_line}'"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end},
        {:llm_judge,
         "Did the agent use a pipeline approach (grep | sed | sort | uniq or similar) rather than manually constructing the output?"}
      ]
    }
  end

  # --- find + sha256sum + wc: build manifest ---

  defp multi_file_processing do
    %{
      name: "multi_file_processing",
      description: """
      You have several source files under /src/. Create a build manifest at /output/manifest.txt.
      For each .sh file under /src/, produce a line with the format:
        filename <tab> line_count <tab> sha256_hash
      Sort the output by filename. The sha256 hash should be the hex digest of the file contents.
      """,
      files: %{
        "/src/deploy.sh" => "#!/bin/bash\necho \"deploying...\"\nrsync -av . server:/app\n",
        "/src/test.sh" => "#!/bin/bash\nset -e\nmix test\n",
        "/src/build.sh" => "#!/bin/bash\nset -e\nmix deps.get\nmix compile\nmix release\n",
        "/src/README.md" => "# Scripts\nThese are deployment scripts.\n"
      },
      validators: [
        {:command_used, "sha256sum"},
        {:file_contains, "/output/manifest.txt",
         [
           {:line_count, 3},
           {:regex, ~r/build\.sh\t/},
           {:regex, ~r/deploy\.sh\t/},
           {:regex, ~r/test\.sh\t/}
         ]},
        {:custom, "sorted_by_filename",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/manifest.txt") do
             {:ok, content} ->
               names =
                 content
                 |> String.trim()
                 |> String.split("\n")
                 |> Enum.map(&(String.split(&1, "\t") |> hd()))

               if names == Enum.sort(names),
                 do: :ok,
                 else: {:error, "not sorted: #{inspect(names)}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- jq: reshape a nested API response into a flat CSV ---

  defp jq_api_response do
    %{
      name: "jq_api_response",
      description: """
      You have a JSON API response at /data/api_response.json. It contains a nested structure
      with a "data" array of order objects. Each order has "id", "customer" (object with "name"),
      "items" (array of objects with "product" and "price"), and "status".

      Create /output/orders.csv with columns: order_id,customer_name,total,status
      where "total" is the sum of all item prices for that order. Include a header row.
      Sort by order_id ascending.
      """,
      files: %{
        "/data/api_response.json" =>
          Jason.encode!(%{
            data: [
              %{
                id: 1003,
                customer: %{name: "Charlie"},
                items: [%{product: "Mouse", price: 25}, %{product: "Keyboard", price: 75}],
                status: "shipped"
              },
              %{
                id: 1001,
                customer: %{name: "Alice"},
                items: [%{product: "Laptop", price: 999}, %{product: "Case", price: 49}],
                status: "delivered"
              },
              %{
                id: 1002,
                customer: %{name: "Bob"},
                items: [%{product: "Monitor", price: 300}],
                status: "pending"
              }
            ],
            meta: %{total: 3, page: 1}
          })
      },
      validators: [
        {:command_used, "jq"},
        {:file_contains, "/output/orders.csv",
         [
           {:line_count, 4},
           {:regex, ~r/order_id/},
           {:regex, ~r/1001.*Alice.*1048.*delivered/},
           {:regex, ~r/1002.*Bob.*300.*pending/},
           {:regex, ~r/1003.*Charlie.*100.*shipped/}
         ]},
        {:llm_judge,
         "Did the agent correctly use jq to flatten the nested JSON structure and compute totals? Was the CSV properly formatted?"}
      ]
    }
  end

  # --- Realistic: log rotation with mv/rm/touch ---

  defp log_rotation do
    %{
      name: "log_rotation",
      description: """
      The filesystem already contains these log files (do NOT create or overwrite them):
      - /var/log/app.log (current log with content)
      - /var/log/app.log.1 (previous log with content)
      - /var/log/app.log.2 (oldest log with content)

      Perform log rotation directly on these EXISTING files:
      1. Delete /var/log/app.log.2 (oldest)
      2. Move /var/log/app.log.1 to /var/log/app.log.2
      3. Move /var/log/app.log to /var/log/app.log.1
      4. Create a new empty /var/log/app.log
      5. Write a summary to /output/rotation.log listing what was done (one action per line).

      After rotation, /var/log/app.log should be empty, .log.1 should have the original
      .log content, and .log.2 should have the original .log.1 content.
      """,
      files: %{
        "/var/log/app.log" => "current log line 1\ncurrent log line 2\n",
        "/var/log/app.log.1" => "previous log line 1\nprevious log line 2\n",
        "/var/log/app.log.2" => "ancient log line 1\n"
      },
      validators: [
        {:custom, "app.log_empty",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/var/log/app.log") do
             {:ok, content} ->
               if String.trim(content) == "", do: :ok, else: {:error, "app.log should be empty"}

             {:error, _} ->
               {:error, "app.log not found"}
           end
         end},
        {:file_contains, "/var/log/app.log.1", [{:regex, ~r/current log line/}]},
        {:file_contains, "/var/log/app.log.2", [{:regex, ~r/previous log line/}]},
        {:file_contains, "/output/rotation.log", [{:not_empty}]}
      ]
    }
  end

  # --- Realistic: parse a Dockerfile and extract metadata as JSON ---

  defp install_script do
    %{
      name: "install_script",
      description: """
      You have a Dockerfile at /app/Dockerfile. Parse it and produce a JSON report
      at /output/dockerfile_report.json with the following fields:
      - "base_image": the image from the FROM instruction (string)
      - "exposed_ports": array of port numbers (integers) from EXPOSE instructions
      - "env_vars": object mapping ENV variable names to their values
      - "num_run_commands": count of RUN instructions (integer)

      Use grep/sed to extract values, then use jq to construct the JSON.
      Tip: use jq --arg and --argjson to pass extracted values into a jq filter that
      builds the final JSON object. Avoid heredocs (<<EOF) — use echo/printf to pass
      data to jq via pipes instead.
      """,
      files: %{
        "/app/Dockerfile" =>
          Enum.join(
            [
              "FROM elixir:1.15-alpine",
              "ENV MIX_ENV=prod",
              "ENV PORT=4000",
              "ENV SECRET_KEY_BASE=supersecret123",
              "WORKDIR /app",
              "COPY mix.exs mix.lock ./",
              "RUN mix deps.get --only prod",
              "RUN mix deps.compile",
              "COPY . .",
              "RUN mix compile",
              "RUN mix release",
              "EXPOSE 4000",
              "EXPOSE 4001",
              ~s(CMD ["_build/prod/rel/myapp/bin/myapp", "start"])
            ],
            "\n"
          ) <> "\n"
      },
      validators: [
        {:file_contains, "/output/dockerfile_report.json",
         [
           {:json,
            fn data ->
              cond do
                data["base_image"] != "elixir:1.15-alpine" ->
                  {:error,
                   "base_image: expected elixir:1.15-alpine, got #{inspect(data["base_image"])}"}

                Enum.sort(data["exposed_ports"] || []) != [4000, 4001] ->
                  {:error,
                   "exposed_ports: expected [4000,4001], got #{inspect(data["exposed_ports"])}"}

                not is_map(data["env_vars"]) ->
                  {:error, "env_vars should be an object"}

                data["env_vars"]["MIX_ENV"] != "prod" ->
                  {:error, "env_vars.MIX_ENV should be 'prod'"}

                data["num_run_commands"] != 4 ->
                  {:error,
                   "num_run_commands: expected 4, got #{inspect(data["num_run_commands"])}"}

                true ->
                  :ok
              end
            end}
         ]},
        {:command_used, "grep"}
      ]
    }
  end

  # --- Realistic: template .env file from a vars file + defaults ---

  defp env_templating do
    %{
      name: "env_templating",
      description: """
      You have a template file at /app/.env.template and an overrides file at /app/overrides.conf.
      The template has lines like KEY={{VALUE}} or KEY={{VALUE:-default}}.
      The overrides file has KEY=VALUE pairs.

      Generate /app/.env by:
      1. For each line in the template, if the KEY exists in overrides, use the override value
      2. If not, use the default value after :- (if present)
      3. If no override and no default, leave the value as empty string
      Write the result to /app/.env as plain KEY=VALUE lines.

      Suggested approach: start by copying the template, then use sed to replace each
      {{...}} placeholder. Read overrides with a while-read loop. Use grep to check if
      a key exists in the overrides file, and cut/sed to extract its value.
      Avoid [[ =~ ]] regex matching — use grep or case patterns instead.
      """,
      files: %{
        "/app/.env.template" =>
          Enum.join(
            [
              "DATABASE_URL={{DATABASE_URL}}",
              "REDIS_URL={{REDIS_URL:-redis://localhost:6379}}",
              "SECRET_KEY={{SECRET_KEY}}",
              "LOG_LEVEL={{LOG_LEVEL:-info}}",
              "PORT={{PORT:-3000}}"
            ],
            "\n"
          ) <> "\n",
        "/app/overrides.conf" =>
          Enum.join(
            [
              "DATABASE_URL=postgres://prod-db:5432/myapp",
              "SECRET_KEY=abc123secret",
              "PORT=8080"
            ],
            "\n"
          ) <> "\n"
      },
      validators: [
        {:file_contains, "/app/.env",
         [
           {:line_count, 5},
           {:regex, ~r/DATABASE_URL=postgres:\/\/prod-db:5432\/myapp/},
           {:regex, ~r/REDIS_URL=redis:\/\/localhost:6379/},
           {:regex, ~r/SECRET_KEY=abc123secret/},
           {:regex, ~r/LOG_LEVEL=info/},
           {:regex, ~r/PORT=8080/}
         ]},
        {:llm_judge,
         "Did the agent write a script that processes the template programmatically (using loops, sed, or grep) rather than hardcoding the exact 5 output values? Answer PASS if the approach is generalizable."}
      ]
    }
  end
end
