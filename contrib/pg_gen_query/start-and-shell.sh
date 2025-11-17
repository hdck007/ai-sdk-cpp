#!/bin/bash
set -euo pipefail

# If started as root, re-exec this script as the `postgres` user so
# Postgres tools like pg_ctl are not run as root (they refuse to run).

# Default env variables (can be overridden at runtime)
: ${PG_GEN_QUERY_GEMINI_API_KEY:=}
: ${PG_GEN_QUERY_GEMINI_MODEL:=gemini-2.0-flash}
: ${PG_GEN_QUERY_OPENAI_API_KEY:=}
: ${PG_GEN_QUERY_ANTHROPIC_API_KEY:=}

if [ "$(id -u)" -eq 0 ]; then
	: ${PGDATA:=/var/lib/postgresql/data}
	chown -R postgres:postgres "$PGDATA" || true
	# Export standard provider env vars so they are available to the
	# `postgres` user and inherited by the server process after su
	if [ -n "${PG_GEN_QUERY_GEMINI_API_KEY:-}" ]; then
		export GEMINI_API_KEY="${PG_GEN_QUERY_GEMINI_API_KEY}"
	fi
	if [ -n "${PG_GEN_QUERY_OPENAI_API_KEY:-}" ]; then
		export OPENAI_API_KEY="${PG_GEN_QUERY_OPENAI_API_KEY}"
	fi
	if [ -n "${PG_GEN_QUERY_ANTHROPIC_API_KEY:-}" ]; then
		export ANTHROPIC_API_KEY="${PG_GEN_QUERY_ANTHROPIC_API_KEY}"
	fi
	# Preserve the environment when switching to postgres user (-p)
	exec su -p - postgres -s /bin/bash -c "$0"
fi

# Start Postgres in background
# Ensure PGDATA exists
mkdir -p "$PGDATA"

# If PGDATA is not initialized, run initdb
if [ ! -s "$PGDATA/PG_VERSION" ]; then
	echo "PGDATA not initialized, running initdb..."
	initdb -D "$PGDATA"
fi

# Start Postgres in background. If provider env vars are present, launch
# the server with them using `env` so the server process inherits the keys.
ENV_CMD=""
if [ -n "${PG_GEN_QUERY_GEMINI_API_KEY:-}" ] || [ -n "${PG_GEN_QUERY_OPENAI_API_KEY:-}" ] || [ -n "${PG_GEN_QUERY_ANTHROPIC_API_KEY:-}" ]; then
	ENV_CMD="env"
	if [ -n "${PG_GEN_QUERY_GEMINI_API_KEY:-}" ]; then
		ENV_CMD="$ENV_CMD GEMINI_API_KEY='${PG_GEN_QUERY_GEMINI_API_KEY}'"
	fi
	if [ -n "${PG_GEN_QUERY_OPENAI_API_KEY:-}" ]; then
		ENV_CMD="$ENV_CMD OPENAI_API_KEY='${PG_GEN_QUERY_OPENAI_API_KEY}'"
	fi
	if [ -n "${PG_GEN_QUERY_ANTHROPIC_API_KEY:-}" ]; then
		ENV_CMD="$ENV_CMD ANTHROPIC_API_KEY='${PG_GEN_QUERY_ANTHROPIC_API_KEY}'"
	fi
fi

if [ -n "$ENV_CMD" ]; then
	eval "$ENV_CMD pg_ctl -D \"$PGDATA\" -o \"-c listen_addresses='*'\" -w start"
else
	pg_ctl -D "$PGDATA" -o "-c listen_addresses='*'" -w start
fi

echo "Postgres started. Running initial SQL setup..."

# Default env variables (can be overridden at runtime)
: ${PG_GEN_QUERY_GEMINI_API_KEY:=}
: ${PG_GEN_QUERY_GEMINI_MODEL:=gemini-2.0-flash}
: ${PG_GEN_QUERY_OPENAI_API_KEY:=}
: ${PG_GEN_QUERY_ANTHROPIC_API_KEY:=}

# (provider env vars are exported earlier when running as root so the
# postgres process inherits them)

psql -v ON_ERROR_STOP=1 -d postgres <<SQL || true
CREATE EXTENSION IF NOT EXISTS pg_gen_query;
-- Persist provider GUCs so they are available to all sessions
-- Use dollar-quoting to avoid single-quote escaping issues
-- Create a simple analytics schema: websites (lookup) and analytics_events (FK)
SET client_min_messages = 'log';
-- Drop old tables if present
DROP TABLE IF EXISTS analytics_events;
DROP TABLE IF EXISTS websites;

-- Websites lookup table with country metadata
CREATE TABLE websites(
	website_id serial PRIMARY KEY,
	name text NOT NULL,
	domain text NOT NULL UNIQUE,
	country text NOT NULL
);

-- Events table recording simple analytics
CREATE TABLE analytics_events(
	event_id serial PRIMARY KEY,
	website_id int NOT NULL REFERENCES websites(website_id) ON DELETE CASCADE,
	event_type text NOT NULL, -- e.g. 'page_view', 'click', 'signup'
	event_time timestamptz NOT NULL DEFAULT now(),
	user_id text, -- opaque user identifier
	page text, -- page path or name
	metadata jsonb -- additional context (button id, referrer, etc.)
);

-- Seed websites and some analytics events
INSERT INTO websites(name,domain,country) VALUES
	('Example Store','store.example.com','US'),
	('News Site','news.example.com','UK'),
	('Blog','blog.example.com','US');

INSERT INTO analytics_events(website_id,event_type,event_time,user_id,page,metadata) VALUES
	(1,'page_view', now() - interval '2 days','user_1','/home', '{"ref": "google"}'),
	(1,'click', now() - interval '2 days 1 hour','user_1','/product','{"button":"buy_now"}'),
	(2,'page_view', now() - interval '1 day','user_2','/news/abc','{"ref":"twitter"}'),
	(1,'signup', now() - interval '5 hours','user_3','/signup','{"plan":"pro"}'),
	(3,'page_view', now() - interval '3 hours','user_4','/blog/post-1','{"ref":"email"}');
-- Convenience view to make analytics queries easier (matches examples)
CREATE OR REPLACE VIEW events AS
SELECT ae.event_id,
	   ae.website_id,
	   w.domain,
	   w.name,
	   w.country,
	   ae.event_type,
	   ae.event_time,
	   ae.user_id,
	   ae.page,
	   ae.metadata
FROM analytics_events ae
JOIN websites w ON ae.website_id = w.website_id;
SQL

# Persist provider GUCs using ALTER SYSTEM from the shell (avoids psql meta-commands)
if [ -n "${PG_GEN_QUERY_GEMINI_API_KEY:-}" ]; then
	esc=$(printf "%s" "${PG_GEN_QUERY_GEMINI_API_KEY}" | sed "s/'/''/g")
	psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER SYSTEM SET pg_gen_query.gemini_api_key = '$esc';" || true
fi
if [ -n "${PG_GEN_QUERY_GEMINI_MODEL:-}" ]; then
	esc=$(printf "%s" "${PG_GEN_QUERY_GEMINI_MODEL}" | sed "s/'/''/g")
	psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER SYSTEM SET pg_gen_query.gemini_model = '$esc';" || true
fi
if [ -n "${PG_GEN_QUERY_OPENAI_API_KEY:-}" ]; then
	esc=$(printf "%s" "${PG_GEN_QUERY_OPENAI_API_KEY}" | sed "s/'/''/g")
	psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER SYSTEM SET pg_gen_query.openai_api_key = '$esc';" || true
fi
if [ -n "${PG_GEN_QUERY_ANTHROPIC_API_KEY:-}" ]; then
	esc=$(printf "%s" "${PG_GEN_QUERY_ANTHROPIC_API_KEY}" | sed "s/'/''/g")
	psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER SYSTEM SET pg_gen_query.anthropic_api_key = '$esc';" || true
fi

# Reload configuration so ALTER SYSTEM takes effect for new sessions
if [ -n "${PG_GEN_QUERY_GEMINI_API_KEY:-}" ] || [ -n "${PG_GEN_QUERY_OPENAI_API_KEY:-}" ] || [ -n "${PG_GEN_QUERY_ANTHROPIC_API_KEY:-}" ] || [ -n "${PG_GEN_QUERY_GEMINI_MODEL:-}" ]; then
	psql -v ON_ERROR_STOP=1 -d postgres -c "SELECT pg_reload_conf();" || true
fi

# If POSTGRES_PASSWORD is set, ensure postgres user has that password
if [ -n "${POSTGRES_PASSWORD:-}" ]; then
	psql -v ON_ERROR_STOP=1 -d postgres <<SQL || true
ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';
SQL
fi

echo "Entering interactive shell. Use 'psql -d postgres' to run queries."
if [ -t 1 ]; then
	# Interactive terminal: drop to a shell
	exec bash
else
	# Non-interactive / detached container: keep process in foreground by
	# tailing the Postgres logfile so container stays alive and logs stream.
	LOGFILE="$PGDATA/logfile"
	touch "$LOGFILE"
	tail -F "$LOGFILE"
fi
