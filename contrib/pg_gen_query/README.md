Usage

```sql
SET pg_gen_query.gemini_api_key = 'YOUR_GEMINI_API_KEY';
SELECT pg_gen_query('number of events from Texas');
```

Using Podman
-
The repo includes a `Dockerfile` and a small startup script that builds the in-tree SDK, installs the extension into a Postgres image, seeds test data and drops to an interactive shell. If you prefer `podman`, use the steps below to run the prepared development image locally.

1) Build the image from the repository root (may take several minutes):

```fish
podman build -f contrib/pg_gen_query/Dockerfile -t localhost/pg-gen-query-dev:latest .
```

2) Run the container detached and expose Postgres on localhost:5432. Provide your Gemini (or other provider) API key via env var. The startup script will create a sample `events` table and seed rows on first run.

```fish
podman run -d --name pgdev \
	-p 5432:5432 \
	-e POSTGRES_PASSWORD=postgres \
	-e PG_GEN_QUERY_GEMINI_API_KEY='YOUR_GEMINI_API_KEY' \
	localhost/pg-gen-query-dev:latest
```

3) Exec into the container or use `psql` from your host:

```fish
# interactive shell inside container
podman exec -it pgdev /bin/bash

# or run psql directly from host (psql must be installed on host)
psql -h localhost -p 5432 -U postgres -d postgres
```

4) In `psql`, set any provider GUCs for the session and run example prompts:

```sql
SET pg_gen_query.gemini_api_key = 'YOUR_GEMINI_API_KEY';
SET pg_gen_query.gemini_model = 'gemini-2.0-flash';
SELECT pg_gen_query('List events in Texas with name and state');
```

Quick start (run, exec, connect, run)
-
This sequence shows the minimal steps to start the dev container, exec into it, connect to Postgres and run `pg_gen_query`. The startup script exports provider environment variables so passing `PG_GEN_QUERY_GEMINI_API_KEY` when starting the container is sufficient and you don't need to `SET` the GUC in every psql session.

```fish
# 1) Start the container (replace with your key or use --env-file)
podman run -d --name pgdev \
	-p 5432:5432 \
	-e POSTGRES_PASSWORD=postgres \
	-e PG_GEN_QUERY_GEMINI_API_KEY='YOUR_GEMINI_API_KEY' \
	localhost/pg-gen-query-dev:latest

# 2) Exec into the container (optional interactive shell)
podman exec -it pgdev /bin/bash

# 3) Connect to Postgres from inside the container (or from host)
psql -h localhost -p 5432 -U postgres -d postgres

# 4) Run example query directly (no per-session SET required)
"SELECT pg_gen_query('List events in Texas with name and state');"
```

Security notes
-
- Do not hard-code API keys into images or commit them to the repository. Use runtime env vars or mounted secret files.
- The example startup script seeds the `events` table for convenience; adjust or disable seeding for production usage.

Troubleshooting
-
- If `pg_gen_query` reports `No AI provider configured`, ensure you set a provider GUC in the same `psql` session before calling the function, or pass the key as an env var when starting the container.
- If the container exits immediately, inspect the logs with `podman logs pgdev` for errors (common causes: missing extension files in image or permission issues on mounted startup script).
Features

Build & Install

```fish
mkdir -p build && cd build
cmake .. -DCMAKE_PREFIX_PATH=/path/to/ai-sdk-cpp/build/install
cmake --build . --config Release
```


```fish
cp build/pg_gen_query.so /opt/homebrew/lib/postgresql@14/
```


Examples (exact commands and results)

Run the setup and insert the sample rows (API key masked):

```fish
psql -d postgres -c "SET client_min_messages = 'log'; SET pg_gen_query.gemini_model = 'gemini-2.0-flash'; SET pg_gen_query.gemini_api_key = 'YOUR_GEMINI_API_KEY'; -- The container startup also seeds an analytics schema: websites + analytics_events"
```

Run each example query (analytics-focused examples):

```sql
-- 1) Total events per country (join websites -> analytics_events)
SELECT pg_gen_query('Total events per country');

-- 2) Recent page views for a specific website domain
SELECT pg_gen_query('List page_view events for store.example.com in the last 24 hours with user_id and page');

-- 3) Count of signups by website
SELECT pg_gen_query('Count signups grouped by website name and country');
```



