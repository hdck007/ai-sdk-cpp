#ifndef PG_GEN_QUERY_UTILS_H
#define PG_GEN_QUERY_UTILS_H

#include <string>

// Gather DB schema description via SPI. Caller does not need to call SPI_connect/finish.
std::string pg_gen_query_get_schema_description();

// Sanitize generated SQL text: extract fenced SQL, convert double-quoted
// string literals to single quotes for PostgreSQL, and trim whitespace.
std::string pg_gen_query_sanitize_generated_sql(const std::string &in);

// Escape a string for safe single-quoted SQL literal (doubling single quotes)
std::string pg_gen_query_escape_literal(const std::string &in);

#endif // PG_GEN_QUERY_UTILS_H
