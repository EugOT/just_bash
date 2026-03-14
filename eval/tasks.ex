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
      # Original 8
      jq_transform(),
      sed_config_rewrite(),
      grep_pipeline(),
      multi_file_processing(),
      jq_api_response(),
      log_rotation(),
      install_script(),
      env_templating(),
      # New 20
      csv_to_json(),
      word_frequency(),
      directory_flattener(),
      base64_pipeline(),
      crontab_parser(),
      markdown_table(),
      checksum_audit(),
      access_log_stats(),
      multi_file_rename(),
      ini_to_env(),
      data_dedup(),
      ascii_bar_chart(),
      package_inventory(),
      split_and_reassemble(),
      nginx_vhost_generator(),
      csv_join(),
      git_log_changelog(),
      json_schema_validator(),
      file_tree_snapshot(),
      pipeline_etl()
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

      Use grep/awk to extract values, then use jq to construct the JSON.
      Tip: use `awk '/^FROM/ {print $2}'` for the base image, `awk '/^EXPOSE/ {print $2}'`
      for ports, `grep '^ENV'` then cut for env vars, and `grep -c '^RUN'` for the count.
      Build the JSON object incrementally with jq: start with `echo '{}' > file` then
      add fields with `jq --arg k "$key" --arg v "$val" '. + {($k): $v}' file > tmp && mv tmp file`.
      Avoid heredocs (<<EOF) — use echo/printf instead.
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

  # ====================================================================
  # NEW EVALS (20)
  # ====================================================================

  # --- 9. CSV to JSON: awk/sed text processing into structured JSON ---

  defp csv_to_json do
    csv_data =
      Enum.join(
        [
          "name,department,salary",
          "Alice,Engineering,95000",
          "Bob,Marketing,72000",
          "Charlie,Engineering,88000",
          "Diana,Marketing,76000",
          "Eve,Engineering,102000"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "csv_to_json",
      description: """
      You have a CSV file at /data/employees.csv with columns: name, department, salary.
      Convert it to a JSON file at /output/employees.json that is an array of objects,
      each with "name" (string), "department" (string), and "salary" (number, not string).
      Skip the header row. Sort by salary descending.

      Use awk or sed to parse the CSV and construct the JSON. You can also use jq to
      format or validate the output.
      """,
      files: %{"/data/employees.csv" => csv_data},
      validators: [
        {:file_contains, "/output/employees.json",
         [
           {:json,
            fn data ->
              cond do
                not is_list(data) ->
                  {:error, "expected array"}

                length(data) != 5 ->
                  {:error, "expected 5 employees, got #{length(data)}"}

                not Enum.all?(data, &is_number(&1["salary"])) ->
                  {:error, "salary should be a number"}

                hd(data)["name"] != "Eve" ->
                  {:error, "first employee should be Eve (highest salary)"}

                List.last(data)["name"] != "Bob" ->
                  {:error, "last employee should be Bob (lowest salary)"}

                true ->
                  :ok
              end
            end}
         ]}
      ]
    }
  end

  # --- 10. Word frequency: classic Unix text pipeline ---

  defp word_frequency do
    text = """
    the quick brown fox jumps over the lazy dog
    the dog barked at the fox and the fox ran away
    a quick red fox outran the brown dog easily
    the lazy dog slept while the quick fox played
    """

    %{
      name: "word_frequency",
      description: """
      You have a text file at /data/passage.txt. Compute word frequencies and write
      the top 5 most frequent words to /output/top_words.txt in the format:
        COUNT WORD
      one per line, sorted by count descending (highest first). In case of ties,
      sort alphabetically by word. Normalize to lowercase.

      Use a pipeline of tr, sort, uniq (and any other tools) to count words.
      """,
      files: %{"/data/passage.txt" => text},
      validators: [
        {:command_used, "sort"},
        {:command_used, "uniq"},
        {:file_contains, "/output/top_words.txt",
         [
           {:line_count, 5},
           {:regex, ~r/the/}
         ]},
        {:custom, "top_word_is_the",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/top_words.txt") do
             {:ok, content} ->
               first_line =
                 content |> String.trim() |> String.split("\n") |> hd() |> String.trim()

               if String.contains?(first_line, "the"),
                 do: :ok,
                 else: {:error, "first word should be 'the', got: #{first_line}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 11. Directory flattener: mv + find + basename collision handling ---

  defp directory_flattener do
    %{
      name: "directory_flattener",
      description: """
      You have a nested directory structure under /src/ with files at various depths.
      Flatten ALL files into /output/flat/ by copying them there. If two files have
      the same basename, rename the duplicate by prepending the parent directory name
      with an underscore (e.g., utils/helper.sh -> utils_helper.sh).

      After flattening, write a manifest of all files in /output/flat/ (one filename
      per line, sorted) to /output/manifest.txt.

      Use find to discover files, and basename/dirname to handle naming.
      """,
      files: %{
        "/src/main.sh" => "#!/bin/bash\necho main\n",
        "/src/lib/utils.sh" => "#!/bin/bash\necho lib-utils\n",
        "/src/lib/helper.sh" => "#!/bin/bash\necho lib-helper\n",
        "/src/tests/helper.sh" => "#!/bin/bash\necho tests-helper\n",
        "/src/tests/runner.sh" => "#!/bin/bash\necho tests-runner\n"
      },
      validators: [
        {:command_used, "find"},
        {:file_contains, "/output/manifest.txt",
         [
           {:regex, ~r/main\.sh/},
           {:regex, ~r/runner\.sh/},
           {:regex, ~r/utils\.sh/}
         ]},
        {:custom, "no_lost_files",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/manifest.txt") do
             {:ok, content} ->
               lines =
                 content |> String.trim() |> String.split("\n") |> Enum.map(&String.trim/1)

               if length(lines) >= 5,
                 do: :ok,
                 else: {:error, "expected at least 5 files, got #{length(lines)}"}

             {:error, _} ->
               {:error, "manifest not found"}
           end
         end},
        {:custom, "helper_conflict_resolved",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/manifest.txt") do
             {:ok, content} ->
               lines =
                 content |> String.trim() |> String.split("\n") |> Enum.map(&String.trim/1)

               helper_files = Enum.filter(lines, &String.contains?(&1, "helper"))

               if length(helper_files) >= 2,
                 do: :ok,
                 else: {:error, "expected 2 helper variants, got: #{inspect(helper_files)}"}

             {:error, _} ->
               {:error, "manifest not found"}
           end
         end}
      ]
    }
  end

  # --- 12. Base64 encode/decode pipeline ---

  defp base64_pipeline do
    secret = "The secret password is: hunter2"
    encoded = Base.encode64(secret)

    %{
      name: "base64_pipeline",
      description: """
      You have an encoded file at /data/secret.b64 containing a base64-encoded message.
      1. Decode it and write the plaintext to /output/decoded.txt
      2. Then create a new file /output/re_encoded.b64 by base64-encoding the decoded content
      3. Verify they match by computing the sha256sum of each file (/data/secret.b64
         and /output/re_encoded.b64) and comparing the hashes. Write "MATCH" or
         "MISMATCH" to /output/verify.txt.

      Use the base64 command for encoding/decoding. Compare using sha256sum (compute
      each hash separately, then compare the hash strings). Do NOT use cmp or diff.
      Do NOT pass multiple files to wc or sha256sum in a single call — process one
      file at a time.
      """,
      files: %{"/data/secret.b64" => encoded <> "\n"},
      validators: [
        {:command_used, "base64"},
        {:file_contains, "/output/decoded.txt", [{:regex, ~r/hunter2/}]},
        {:file_contains, "/output/verify.txt", [{:regex, ~r/MATCH/}]}
      ]
    }
  end

  # --- 13. Crontab parser: extract schedule metadata from cron entries ---

  defp crontab_parser do
    crontab =
      Enum.join(
        [
          "# Database backups",
          "0 2 * * * /usr/bin/pg_dump mydb > /backups/db.sql",
          "30 3 * * 0 /usr/bin/full_backup.sh",
          "",
          "# App maintenance",
          "*/15 * * * * /usr/bin/health_check.sh",
          "0 0 1 * * /usr/bin/rotate_logs.sh",
          "0 6,18 * * 1-5 /usr/bin/report_gen.sh"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "crontab_parser",
      description: """
      You have a crontab file at /etc/crontab. Parse it and produce a JSON report at
      /output/cron_report.json with the following structure:
      {
        "total_jobs": <number>,
        "jobs": [
          {"schedule": "<cron expression>", "command": "<command path>", "frequency": "<human readable>"},
          ...
        ]
      }

      For "frequency", use simple descriptions like "daily", "weekly", "every 15 minutes",
      "monthly", or describe the schedule briefly. Extract the command as just the executable
      path (first element after the 5 cron fields, without arguments).

      Skip comment lines and blank lines. Use grep/sed/awk to parse, and jq to build the JSON.
      """,
      files: %{"/etc/crontab" => crontab},
      validators: [
        {:file_contains, "/output/cron_report.json",
         [
           {:json,
            fn data ->
              cond do
                data["total_jobs"] != 5 ->
                  {:error, "expected 5 jobs, got #{inspect(data["total_jobs"])}"}

                not is_list(data["jobs"]) ->
                  {:error, "jobs should be an array"}

                length(data["jobs"]) != 5 ->
                  {:error, "expected 5 job entries, got #{length(data["jobs"])}"}

                not Enum.all?(data["jobs"], &(is_binary(&1["command"]) and &1["command"] != "")) ->
                  {:error, "all jobs must have a non-empty command string"}

                true ->
                  :ok
              end
            end}
         ]},
        {:command_used, "grep"}
      ]
    }
  end

  # --- 14. Markdown table generation from raw data ---

  defp markdown_table do
    data =
      Enum.join(
        [
          "product:price:quantity:category",
          "Widget A:9.99:150:hardware",
          "Gadget B:24.50:75:electronics",
          "Tool C:5.00:300:hardware",
          "Device D:49.99:20:electronics",
          "Part E:2.50:500:hardware"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "markdown_table",
      description: """
      You have a colon-delimited data file at /data/products.txt (header: product:price:quantity:category).
      Generate a Markdown report at /output/report.md with:

      1. A heading "# Product Report"
      2. A Markdown table with columns: Product, Price, Quantity, Category, Total Value
         where Total Value = price * quantity (formatted as a plain number, no currency symbol needed)
      3. A summary line below the table: "**Total inventory value: X**" where X is the sum
         of all Total Value entries

      Use awk to compute values. The table must have proper Markdown table formatting
      (header row, separator row with dashes, data rows, all pipe-delimited).
      """,
      files: %{"/data/products.txt" => data},
      validators: [
        {:command_used, "awk"},
        {:file_contains, "/output/report.md",
         [
           {:regex, ~r/# Product Report/},
           {:regex, ~r/\|.*Product.*\|.*Price.*\|/},
           {:regex, ~r/\|[-\s|:]+\|/},
           {:regex, ~r/Widget A/},
           {:regex, ~r/Total inventory value/}
         ]},
        {:custom, "has_all_products",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/report.md") do
             {:ok, content} ->
               products = ["Widget A", "Gadget B", "Tool C", "Device D", "Part E"]
               missing = Enum.reject(products, &String.contains?(content, &1))

               if missing == [],
                 do: :ok,
                 else: {:error, "missing products: #{inspect(missing)}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 15. Checksum audit: verify file integrity ---

  defp checksum_audit do
    files = %{
      "/data/files/alpha.txt" => "Hello World\n",
      "/data/files/beta.txt" => "Goodbye World\n",
      "/data/files/gamma.txt" => "Changed Content\n"
    }

    # Pre-compute correct checksums for alpha and beta, wrong one for gamma
    alpha_hash = :crypto.hash(:sha256, "Hello World\n") |> Base.encode16(case: :lower)
    beta_hash = :crypto.hash(:sha256, "Goodbye World\n") |> Base.encode16(case: :lower)
    gamma_hash = :crypto.hash(:sha256, "Original Content\n") |> Base.encode16(case: :lower)

    checksums =
      Enum.join(
        [
          "#{alpha_hash}  /data/files/alpha.txt",
          "#{beta_hash}  /data/files/beta.txt",
          "#{gamma_hash}  /data/files/gamma.txt"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "checksum_audit",
      description: """
      You have files under /data/files/ and a checksum manifest at /data/checksums.txt
      (in sha256sum format: "hash  filepath"). Some files may have been modified since
      the checksums were generated.

      Verify each file against its expected checksum and write a report to
      /output/audit.txt with one line per file in the format:
        filepath: OK
      or
        filepath: FAILED

      At the end, add a summary line: "X of Y files OK"
      Use sha256sum to compute current checksums and compare.
      """,
      files: Map.merge(files, %{"/data/checksums.txt" => checksums}),
      validators: [
        {:command_used, "sha256sum"},
        {:file_contains, "/output/audit.txt",
         [
           {:regex, ~r/alpha\.txt.*OK/},
           {:regex, ~r/beta\.txt.*OK/},
           {:regex, ~r/gamma\.txt.*FAIL/},
           {:regex, ~r/2 of 3/}
         ]}
      ]
    }
  end

  # --- 16. Access log statistics: awk-heavy analytics ---

  defp access_log_stats do
    log =
      Enum.join(
        [
          ~s(192.168.1.1 - - [01/Jan/2024:10:00:00] "GET /index.html HTTP/1.1" 200 1024),
          ~s(192.168.1.2 - - [01/Jan/2024:10:01:00] "POST /api/login HTTP/1.1" 200 512),
          ~s(192.168.1.1 - - [01/Jan/2024:10:02:00] "GET /about.html HTTP/1.1" 200 2048),
          ~s(10.0.0.5 - - [01/Jan/2024:10:03:00] "GET /index.html HTTP/1.1" 304 0),
          ~s(192.168.1.1 - - [01/Jan/2024:10:04:00] "GET /api/users HTTP/1.1" 500 128),
          ~s(192.168.1.2 - - [01/Jan/2024:10:05:00] "GET /index.html HTTP/1.1" 200 1024),
          ~s(10.0.0.5 - - [01/Jan/2024:10:06:00] "POST /api/login HTTP/1.1" 401 64),
          ~s(192.168.1.3 - - [01/Jan/2024:10:07:00] "GET /contact.html HTTP/1.1" 200 768),
          ~s(192.168.1.1 - - [01/Jan/2024:10:08:00] "GET /index.html HTTP/1.1" 200 1024),
          ~s(10.0.0.5 - - [01/Jan/2024:10:09:00] "GET /api/users HTTP/1.1" 403 128)
        ],
        "\n"
      ) <> "\n"

    %{
      name: "access_log_stats",
      description: """
      You have a web server access log at /var/log/access.log in common log format.
      Analyze it and produce /output/stats.txt with the following sections:

      1. "Total requests: N"
      2. "Unique IPs: N"
      3. "Top IP:" followed by the IP with the most requests and its count
      4. "Status codes:" followed by lines showing each status code and count,
         sorted by code (e.g., "  200: 6")
      5. "Error rate: X%" — percentage of requests with status >= 400

      Use awk for the heavy lifting. The exact format should match what's described above.
      """,
      files: %{"/var/log/access.log" => log},
      validators: [
        {:command_used, "awk"},
        {:file_contains, "/output/stats.txt",
         [
           {:regex, ~r/Total requests:\s*10/},
           {:regex, ~r/Unique IPs:\s*4/},
           {:regex, ~r/192\.168\.1\.1/},
           {:regex, ~r/200:\s*6/},
           {:regex, ~r/Error rate:\s*30/}
         ]}
      ]
    }
  end

  # --- 17. Batch file rename with pattern substitution ---

  defp multi_file_rename do
    %{
      name: "multi_file_rename",
      description: """
      You have image files under /photos/ with inconsistent naming:
        IMG_20240101_001.jpg, photo-2024-02-15.jpg, DSC00042.jpg,
        Screenshot 2024-03-20.png, IMG_20240101_002.jpg

      Rename (move) ALL files to /photos/organized/ using a consistent naming scheme:
        YYYY-MM-DD_NNN.ext
      where NNN is a zero-padded sequential number (001, 002, ...) assigned in the
      original alphabetical order of the source filenames. For files that don't contain
      a date, use "0000-00-00" as the date.

      Write a rename log to /output/rename_log.txt with exactly 5 lines (one per file),
      each in the format:
        old_name -> new_name
      Do NOT include any header or extra lines — just the 5 rename entries.

      IMPORTANT: One filename has a space in it ("Screenshot 2024-03-20.png").
      Use `find /photos -maxdepth 1 -type f | sort` piped into a while-read
      loop to handle filenames with spaces safely. Do NOT use `for f in $(ls)`.
      Use `basename` to get just the filename from the full path.
      """,
      files: %{
        "/photos/IMG_20240101_001.jpg" => "jpeg data 1",
        "/photos/IMG_20240101_002.jpg" => "jpeg data 2",
        "/photos/DSC00042.jpg" => "jpeg data 3",
        "/photos/Screenshot 2024-03-20.png" => "png data",
        "/photos/photo-2024-02-15.jpg" => "jpeg data 4"
      },
      validators: [
        {:file_contains, "/output/rename_log.txt",
         [
           {:line_count, 5},
           {:regex, ~r/->/}
         ]},
        {:custom, "files_in_organized",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.readdir(bash.fs, "/photos/organized") do
             {:ok, entries} ->
               if length(entries) == 5,
                 do: :ok,
                 else: {:error, "expected 5 files in /photos/organized/, got #{length(entries)}"}

             {:error, _} ->
               {:error, "/photos/organized/ directory not found"}
           end
         end}
      ]
    }
  end

  # --- 18. INI config to environment variables ---

  defp ini_to_env do
    ini =
      Enum.join(
        [
          "[database]",
          "host = db.example.com",
          "port = 5432",
          "name = production_db",
          "",
          "[redis]",
          "host = cache.example.com",
          "port = 6379",
          "",
          "[app]",
          "debug = false",
          "workers = 4",
          "secret = s3cr3t_k3y"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "ini_to_env",
      description: """
      You have an INI-style configuration file at /etc/app.ini with sections like
      [database], [redis], [app], each containing key=value pairs.

      Convert it to a flat .env file at /output/app.env where each variable is named
      SECTION_KEY=value (section and key in UPPERCASE, spaces trimmed from values).
      For example, [database] host = db.example.com becomes DATABASE_HOST=db.example.com.

      Sort the output alphabetically by variable name.
      Suggested approach: use sed to do it all. First, use sed to track sections
      by converting [section] lines to a PREFIX= marker, then for key=value lines
      prepend the current section prefix. Alternatively, read the file line by line
      in a while loop and use case statements to detect sections vs key-value lines.
      Use tr a-z A-Z for uppercasing. Use sed 's/ //g' to strip spaces.
      Pipe through sort for the final output.
      IMPORTANT: Do NOT use awk for this task (it has limitations with regex character
      classes in this environment). Use sed and shell builtins instead.
      """,
      files: %{"/etc/app.ini" => ini},
      validators: [
        {:file_contains, "/output/app.env",
         [
           {:regex, ~r/DATABASE_HOST=db\.example\.com/},
           {:regex, ~r/DATABASE_PORT=5432/},
           {:regex, ~r/REDIS_PORT=6379/},
           {:regex, ~r/APP_DEBUG=false/},
           {:regex, ~r/APP_SECRET=s3cr3t_k3y/}
         ]},
        {:custom, "sorted_output",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/app.env") do
             {:ok, content} ->
               lines =
                 content
                 |> String.trim()
                 |> String.split("\n")
                 |> Enum.map(&String.trim/1)
                 |> Enum.reject(&(&1 == ""))

               if lines == Enum.sort(lines),
                 do: :ok,
                 else: {:error, "output is not sorted alphabetically"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 19. Data deduplication with merge ---

  defp data_dedup do
    file1 =
      Enum.join(
        [
          "id,email,name",
          "1,alice@example.com,Alice Smith",
          "2,bob@example.com,Bob Jones",
          "3,charlie@example.com,Charlie Brown",
          "4,diana@example.com,Diana Prince"
        ],
        "\n"
      ) <> "\n"

    file2 =
      Enum.join(
        [
          "id,email,name",
          "3,charlie@example.com,Charlie Brown",
          "5,eve@example.com,Eve Wilson",
          "2,bob@corp.com,Bob Jones",
          "6,frank@example.com,Frank Castle"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "data_dedup",
      description: """
      You have two CSV files: /data/users1.csv and /data/users2.csv, both with
      columns: id, email, name. Merge them into /output/merged.csv by:

      1. Combine both files (skip duplicate headers)
      2. Deduplicate by id — if the same id appears in both files, keep the version
         from users2.csv (it's newer)
      3. Sort by id ascending
      4. Include a single header row

      The result should have exactly 6 unique users. Use sort, awk, or other
      text processing tools.
      """,
      files: %{"/data/users1.csv" => file1, "/data/users2.csv" => file2},
      validators: [
        {:file_contains, "/output/merged.csv",
         [
           {:line_count, 7},
           {:regex, ~r/^id,email,name/m},
           {:regex, ~r/alice@example\.com/},
           {:regex, ~r/bob@corp\.com/},
           {:regex, ~r/eve@example\.com/},
           {:regex, ~r/frank@example\.com/}
         ]},
        {:custom, "bob_uses_new_email",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/merged.csv") do
             {:ok, content} ->
               if String.contains?(content, "bob@example.com"),
                 do: {:error, "bob should have bob@corp.com from users2, not bob@example.com"},
                 else: :ok

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 20. ASCII bar chart from data ---

  defp ascii_bar_chart do
    data =
      Enum.join(
        [
          "JavaScript:45",
          "Python:38",
          "Rust:12",
          "Go:22",
          "Elixir:8"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "ascii_bar_chart",
      description: """
      You have a data file at /data/languages.txt with lines in the format "Language:Count".
      Generate an ASCII horizontal bar chart at /output/chart.txt.

      Format each line as:
        Language   | ####... | Count
      where # characters represent the count (one # per unit value). Left-pad the language
      name to 12 characters for alignment. Sort by count descending (highest first).

      Example line: "  JavaScript | ############################################# | 45"

      Use awk or printf for formatting.
      """,
      files: %{"/data/languages.txt" => data},
      validators: [
        {:file_contains, "/output/chart.txt",
         [
           {:line_count, 5},
           {:regex, ~r/JavaScript/},
           {:regex, ~r/Elixir/},
           {:regex, ~r/\#{3,}/}
         ]},
        {:custom, "correct_order",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/chart.txt") do
             {:ok, content} ->
               lines =
                 content |> String.trim() |> String.split("\n") |> Enum.map(&String.trim/1)

               first_has_js = String.contains?(hd(lines), "JavaScript")
               last_has_elixir = String.contains?(List.last(lines), "Elixir")

               if first_has_js and last_has_elixir,
                 do: :ok,
                 else: {:error, "expected JavaScript first and Elixir last (by count desc)"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 21. Package inventory from multiple package files ---

  defp package_inventory do
    pkg1 =
      Jason.encode!(%{
        name: "web-app",
        version: "2.1.0",
        dependencies: %{
          "express" => "^4.18.0",
          "lodash" => "^4.17.21",
          "axios" => "^1.4.0"
        }
      })

    pkg2 =
      Jason.encode!(%{
        name: "api-server",
        version: "1.5.3",
        dependencies: %{
          "express" => "^4.17.0",
          "mongoose" => "^7.0.0",
          "axios" => "^1.3.0"
        }
      })

    pkg3 =
      Jason.encode!(%{
        name: "cli-tool",
        version: "0.9.1",
        dependencies: %{
          "commander" => "^11.0.0",
          "chalk" => "^5.3.0",
          "lodash" => "^4.17.20"
        }
      })

    %{
      name: "package_inventory",
      description: """
      You have three package.json files at /projects/web-app/package.json,
      /projects/api-server/package.json, and /projects/cli-tool/package.json.

      Create a dependency inventory at /output/inventory.json with:
      {
        "total_dependencies": <number of unique dependency names across all projects>,
        "shared_dependencies": [<list of dependency names that appear in 2+ projects, sorted>],
        "projects": {
          "<project-name>": {"version": "...", "dep_count": N},
          ...
        }
      }

      Use jq to parse the JSON files and construct the output.
      """,
      files: %{
        "/projects/web-app/package.json" => pkg1,
        "/projects/api-server/package.json" => pkg2,
        "/projects/cli-tool/package.json" => pkg3
      },
      validators: [
        {:command_used, "jq"},
        {:file_contains, "/output/inventory.json",
         [
           {:json,
            fn data ->
              cond do
                data["total_dependencies"] != 6 ->
                  {:error,
                   "total_dependencies should be 6, got #{inspect(data["total_dependencies"])}"}

                not is_list(data["shared_dependencies"]) ->
                  {:error, "shared_dependencies should be an array"}

                Enum.sort(data["shared_dependencies"]) != ["axios", "express", "lodash"] ->
                  {:error,
                   "shared_dependencies should be [axios, express, lodash], got #{inspect(data["shared_dependencies"])}"}

                not is_map(data["projects"]) ->
                  {:error, "projects should be an object"}

                data["projects"]["web-app"]["dep_count"] != 3 ->
                  {:error, "web-app dep_count should be 3"}

                true ->
                  :ok
              end
            end}
         ]}
      ]
    }
  end

  # --- 22. Split file and reassemble ---

  defp split_and_reassemble do
    lines = Enum.map_join(1..30, "\n", &"Line #{String.pad_leading(to_string(&1), 2, "0")}: data")

    %{
      name: "split_and_reassemble",
      description: """
      You have a file at /data/big_file.txt with 30 lines. Perform these operations:

      1. Split it into chunks of 10 lines each, writing to /tmp/chunk_01.txt,
         /tmp/chunk_02.txt, /tmp/chunk_03.txt (use head/tail or sed to extract ranges)
      2. Reverse the order of lines within each chunk (use tac or sed)
      3. Reassemble the reversed chunks back into /output/reversed_chunks.txt
         (chunk_01 reversed, then chunk_02 reversed, then chunk_03 reversed)
      4. Write the total line count of the output to /output/count.txt

      Use head, tail, and tac (or equivalent) for splitting and reversing.
      Note: wc does not support multiple file arguments — process one file at a time.
      """,
      files: %{"/data/big_file.txt" => lines <> "\n"},
      validators: [
        {:file_contains, "/output/reversed_chunks.txt",
         [
           {:line_count, 30},
           {:not_empty}
         ]},
        {:file_contains, "/output/count.txt", [{:regex, ~r/30/}]},
        {:custom, "chunks_reversed",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/reversed_chunks.txt") do
             {:ok, content} ->
               lines = content |> String.trim() |> String.split("\n")
               # First line should be Line 10 (last of first chunk, reversed)
               first = hd(lines)

               if String.contains?(first, "Line 10"),
                 do: :ok,
                 else:
                   {:error, "first line should be 'Line 10...' (reversed chunk 1), got: #{first}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 23. Nginx virtual host generator ---

  defp nginx_vhost_generator do
    domains =
      Enum.join(
        [
          "example.com:8080:/var/www/example",
          "api.example.com:3000:/var/www/api",
          "blog.example.com:4000:/var/www/blog"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "nginx_vhost_generator",
      description: """
      You have a domain configuration at /data/domains.txt where each line is:
        domain:port:document_root

      Generate Nginx virtual host config files under /output/sites/ — one file per domain
      named <domain>.conf. Each file should contain a server block like:

      server {
          listen 80;
          server_name <domain>;
          root <document_root>;

          location / {
              proxy_pass http://127.0.0.1:<port>;
          }
      }

      Also create /output/sites/all_domains.txt listing all domain names, one per line, sorted.

      Use a while-read loop to process each line, and printf/echo to generate the configs.
      Avoid heredocs (<<EOF) — use printf or multiple echo commands instead.
      """,
      files: %{"/data/domains.txt" => domains},
      validators: [
        {:file_contains, "/output/sites/example.com.conf",
         [
           {:regex, ~r/server_name\s+example\.com/},
           {:regex, ~r/proxy_pass\s+http:\/\/127\.0\.0\.1:8080/},
           {:regex, ~r/root\s+\/var\/www\/example/}
         ]},
        {:file_contains, "/output/sites/api.example.com.conf",
         [
           {:regex, ~r/proxy_pass\s+http:\/\/127\.0\.0\.1:3000/}
         ]},
        {:file_contains, "/output/sites/all_domains.txt",
         [
           {:line_count, 3}
         ]}
      ]
    }
  end

  # --- 24. CSV join: merge two CSVs on a shared key ---

  defp csv_join do
    employees =
      Enum.join(
        [
          "emp_id,name,dept_id",
          "E001,Alice,D10",
          "E002,Bob,D20",
          "E003,Charlie,D10",
          "E004,Diana,D30",
          "E005,Eve,D20"
        ],
        "\n"
      ) <> "\n"

    departments =
      Enum.join(
        [
          "dept_id,dept_name,location",
          "D10,Engineering,Building A",
          "D20,Marketing,Building B",
          "D30,Sales,Building C"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "csv_join",
      description: """
      You have two CSV files:
      - /data/employees.csv (emp_id, name, dept_id)
      - /data/departments.csv (dept_id, dept_name, location)

      Join them on dept_id to produce /output/joined.csv with columns:
        emp_id,name,dept_name,location
      (drop the dept_id column from the output). Sort by emp_id ascending.
      Include a header row.

      Approach — use awk plus a while-read loop with grep -F:
      1. Use awk on departments.csv (NR > 1) to create a lookup file with TAB
         delimiters: dept_id<TAB>dept_name<TAB>location. Use OFS="\\t".
      2. Use a while-read loop over employees.csv (skip header with sed '1d').
         For each employee, use `grep -F "$dept_id" /tmp/lookup.txt` to find
         the matching line, then use cut with TAB delimiter to extract fields.
         The -F flag is CRITICAL — without it, grep treats special chars as
         regex. Append each joined row to a temp file.
      3. Sort the temp file by emp_id and prepend the header row.
      IMPORTANT: awk does NOT support multiple file arguments or getline —
      process one file at a time. Do NOT pass multiple files to wc either.
      """,
      files: %{"/data/employees.csv" => employees, "/data/departments.csv" => departments},
      validators: [
        {:command_used, "awk"},
        {:file_contains, "/output/joined.csv",
         [
           {:line_count, 6},
           {:regex, ~r/emp_id,name,dept_name,location/},
           {:regex, ~r/E001,Alice,Engineering,Building A/},
           {:regex, ~r/E002,Bob,Marketing,Building B/},
           {:regex, ~r/E004,Diana,Sales,Building C/}
         ]}
      ]
    }
  end

  # --- 25. Git-log-style changelog generator ---

  defp git_log_changelog do
    commits =
      Enum.join(
        [
          "abc1234|2024-01-15|fix: resolve login timeout issue",
          "def5678|2024-01-14|feat: add dark mode toggle",
          "ghi9012|2024-01-14|fix: correct calculation in reports",
          "jkl3456|2024-01-13|feat: implement user profiles",
          "mno7890|2024-01-13|docs: update API documentation",
          "pqr1234|2024-01-12|feat: add search functionality",
          "stu5678|2024-01-12|fix: memory leak in worker pool",
          "vwx9012|2024-01-11|chore: upgrade dependencies"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "git_log_changelog",
      description: """
      You have a git log export at /data/commits.txt with lines in the format:
        hash|date|message

      Commit messages follow conventional commits (feat:, fix:, docs:, chore:).
      Generate a changelog at /output/CHANGELOG.md grouped by type:

      # Changelog

      ## Features
      - add dark mode toggle (def5678)
      - implement user profiles (jkl3456)
      - add search functionality (pqr1234)

      ## Fixes
      - resolve login timeout issue (abc1234)
      - ...

      ## Documentation
      - ...

      ## Other
      - ...

      Within each section, list items in the order they appear in the input.
      Strip the "type: " prefix from each message.
      Use grep/sed/awk to categorize and format the entries.
      """,
      files: %{"/data/commits.txt" => commits},
      validators: [
        {:file_contains, "/output/CHANGELOG.md",
         [
           {:regex, ~r/# Changelog/},
           {:regex, ~r/## Features/},
           {:regex, ~r/## Fixes/},
           {:regex, ~r/dark mode toggle/},
           {:regex, ~r/login timeout/},
           {:regex, ~r/def5678/}
         ]},
        {:custom, "correct_categorization",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/CHANGELOG.md") do
             {:ok, content} ->
               # Verify features section has 3 items and fixes has 3
               features_section =
                 content
                 |> String.split(~r/## Fix/i)
                 |> hd()
                 |> String.split(~r/## Feature/i)
                 |> List.last()

               feature_items =
                 features_section
                 |> String.split("\n")
                 |> Enum.filter(&String.starts_with?(String.trim(&1), "-"))

               if length(feature_items) == 3,
                 do: :ok,
                 else: {:error, "expected 3 features, got #{length(feature_items)}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 26. JSON schema validator (lightweight) ---

  defp json_schema_validator do
    valid1 = Jason.encode!(%{name: "Alice", age: 30, email: "alice@example.com"})
    valid2 = Jason.encode!(%{name: "Bob", age: 25, email: "bob@example.com"})
    invalid1 = Jason.encode!(%{name: "Charlie", email: "charlie@example.com"})
    invalid2 = Jason.encode!(%{name: "", age: -5, email: "not-an-email"})
    invalid3 = Jason.encode!(%{name: "Diana", age: "thirty", email: "diana@example.com"})

    data =
      Enum.join([valid1, valid2, invalid1, invalid2, invalid3], "\n") <> "\n"

    %{
      name: "json_schema_validator",
      description: """
      You have a file at /data/records.jsonl (one JSON object per line). Each record
      should have: "name" (non-empty string), "age" (positive number), and
      "email" (string containing "@").

      Validate each line and write results:
      - /output/valid.jsonl — lines that pass all checks (one JSON per line)
      - /output/invalid.jsonl — lines that fail any check (one JSON per line)
      - /output/summary.txt — "Valid: N, Invalid: M"

      Use jq to parse and validate each line. Process the file line by line.
      """,
      files: %{"/data/records.jsonl" => data},
      validators: [
        {:command_used, "jq"},
        {:file_contains, "/output/summary.txt", [{:regex, ~r/Valid:\s*2.*Invalid:\s*3/}]},
        {:custom, "valid_count",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/valid.jsonl") do
             {:ok, content} ->
               lines =
                 content
                 |> String.trim()
                 |> String.split("\n")
                 |> Enum.reject(&(&1 == ""))

               if length(lines) == 2,
                 do: :ok,
                 else: {:error, "expected 2 valid records, got #{length(lines)}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end},
        {:custom, "invalid_count",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/invalid.jsonl") do
             {:ok, content} ->
               lines =
                 content
                 |> String.trim()
                 |> String.split("\n")
                 |> Enum.reject(&(&1 == ""))

               if length(lines) == 3,
                 do: :ok,
                 else: {:error, "expected 3 invalid records, got #{length(lines)}"}

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end

  # --- 27. File tree snapshot: generate a tree representation ---

  defp file_tree_snapshot do
    %{
      name: "file_tree_snapshot",
      description: """
      You have a project structure under /project/ with various files and directories.
      Generate two outputs:

      1. /output/tree.txt — an indented tree view showing the directory structure,
         using 2 spaces per indent level. Directories should end with / and files
         should show their byte size. Example:
           project/
             src/
               main.sh (45 bytes)

      2. /output/summary.json — a JSON object with:
         {"total_files": N, "total_dirs": M, "total_bytes": B, "extensions": {"sh": 3, "md": 1, ...}}

      Use find to discover the structure and wc -c for sizes (one file at a time).
      Build the tree output with a while-read loop and printf for indentation.
      Count depth by using `grep -o '/' | wc -l` on the relative path.
      For the JSON summary, use echo/printf to build the JSON string and pipe
      through jq for formatting. Do NOT use heredocs (<<EOF) — use echo/printf
      to construct the JSON instead. Do NOT use `declare -A` — it is not
      supported. Instead, count extensions with `grep -c` on a temp file or
      use `sort | uniq -c` on a collected list.
      """,
      files: %{
        "/project/README.md" => "# My Project\nA sample project.\n",
        "/project/src/main.sh" => "#!/bin/bash\necho hello\n",
        "/project/src/lib/utils.sh" => "#!/bin/bash\nlog() { echo \"$1\"; }\n",
        "/project/src/lib/config.sh" => "#!/bin/bash\nexport APP=myapp\n",
        "/project/tests/test_main.sh" => "#!/bin/bash\necho test\n",
        "/project/docs/guide.md" => "# Guide\nUsage instructions.\n"
      },
      validators: [
        {:command_used, "find"},
        {:file_contains, "/output/tree.txt",
         [
           {:regex, ~r/project/},
           {:regex, ~r/src/},
           {:regex, ~r/main\.sh/},
           {:regex, ~r/bytes/}
         ]},
        {:file_contains, "/output/summary.json",
         [
           {:json,
            fn data ->
              cond do
                data["total_files"] != 6 ->
                  {:error, "expected 6 total_files, got #{inspect(data["total_files"])}"}

                not is_map(data["extensions"]) ->
                  {:error, "extensions should be an object"}

                true ->
                  :ok
              end
            end}
         ]}
      ]
    }
  end

  # --- 28. ETL pipeline: extract, transform, load ---

  defp pipeline_etl do
    sales =
      Enum.join(
        [
          "date,product,region,quantity,unit_price",
          "2024-01-01,Widget,North,10,25.00",
          "2024-01-01,Gadget,South,5,50.00",
          "2024-01-02,Widget,North,8,25.00",
          "2024-01-02,Widget,South,12,25.00",
          "2024-01-02,Gadget,North,3,50.00",
          "2024-01-03,Widget,North,15,25.00",
          "2024-01-03,Gadget,South,7,50.00",
          "2024-01-03,Widget,South,6,25.00"
        ],
        "\n"
      ) <> "\n"

    %{
      name: "pipeline_etl",
      description: """
      You have sales data at /data/sales.csv. Build an ETL pipeline that produces
      three output files:

      1. /output/by_product.csv — aggregate by product:
         product,total_quantity,total_revenue
         sorted by total_revenue descending. Revenue = quantity * unit_price.

      2. /output/by_region.csv — aggregate by region:
         region,total_quantity,total_revenue
         sorted by region name ascending.

      3. /output/daily_summary.csv — aggregate by date:
         date,num_transactions,total_revenue
         sorted by date ascending.

      Include header rows in all files. Use awk for aggregation.
      """,
      files: %{"/data/sales.csv" => sales},
      validators: [
        {:command_used, "awk"},
        {:file_contains, "/output/by_product.csv",
         [
           {:regex, ~r/product,total_quantity,total_revenue/},
           {:regex, ~r/Widget/},
           {:regex, ~r/Gadget/}
         ]},
        {:file_contains, "/output/by_region.csv",
         [
           {:regex, ~r/region,total_quantity,total_revenue/},
           {:regex, ~r/North/},
           {:regex, ~r/South/}
         ]},
        {:file_contains, "/output/daily_summary.csv",
         [
           {:regex, ~r/date,num_transactions,total_revenue/},
           {:regex, ~r/2024-01-01/},
           {:regex, ~r/2024-01-02/},
           {:regex, ~r/2024-01-03/}
         ]},
        {:custom, "widget_revenue",
         fn %{bash: bash} ->
           case JustBash.Fs.InMemoryFs.read_file(bash.fs, "/output/by_product.csv") do
             {:ok, content} ->
               widget_line =
                 content
                 |> String.split("\n")
                 |> Enum.find(&String.starts_with?(&1, "Widget"))

               case widget_line do
                 nil ->
                   {:error, "Widget row not found"}

                 line ->
                   # Widget: (10+8+12+15+6)*25 = 51*25 = 1275
                   if String.contains?(line, "1275"),
                     do: :ok,
                     else: {:error, "Widget total_revenue should be 1275, got: #{line}"}
               end

             {:error, _} ->
               {:error, "file not found"}
           end
         end}
      ]
    }
  end
end
