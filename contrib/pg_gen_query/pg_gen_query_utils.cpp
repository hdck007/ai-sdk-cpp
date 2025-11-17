#include "pg_gen_query_utils.h"

extern "C" {
#include <postgres.h>
#include <executor/spi.h>
#include <access/htup_details.h>
}

#include <regex>
#include <sstream>
#include <algorithm>
#include <cctype>

std::string pg_gen_query_get_schema_description() {
  std::ostringstream out;
  if (SPI_connect() != SPI_OK_CONNECT) return "";
  const char* q = "SELECT table_schema, table_name, column_name, data_type FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY table_schema, table_name, ordinal_position";
  int rc = SPI_execute(q, true, 0);
  if (rc == SPI_OK_SELECT && SPI_processed > 0) {
    TupleDesc tup = SPI_tuptable->tupdesc;
    SPITupleTable *tuptable = SPI_tuptable;
    std::string last_table;
    for (uint64_t i = 0; i < (uint64_t)SPI_processed; ++i) {
      HeapTuple ht = tuptable->vals[i];
      char* schema = SPI_getvalue(ht, tup, 1);
      char* tbl = SPI_getvalue(ht, tup, 2);
      char* col = SPI_getvalue(ht, tup, 3);
      char* dt = SPI_getvalue(ht, tup, 4);
      if (!schema || !tbl || !col || !dt) continue;
      std::string table_full = std::string(schema) + "." + std::string(tbl);
      if (table_full != last_table) {
        out << table_full << "\n";
        last_table = table_full;
      }
      out << "  - " << col << " : " << dt << "\n";
    }
  }
  SPI_finish();
  return out.str();
}

std::string pg_gen_query_sanitize_generated_sql(const std::string &in) {
  std::string s = in;
  try {
    std::regex fence_re(R"(```(?:sql)?\n([\s\S]*?)\n```)" , std::regex::icase);
    std::smatch m;
    if (std::regex_search(s, m, fence_re) && m.size() > 1) {
      s = m[1].str();
    }
  } catch (...) {
  }

  try {
    std::regex string_eq_re("(=)\\s*\"([^\"]*)\"");
    s = std::regex_replace(s, string_eq_re, "$1 '$2'");
    std::regex string_literal_re("\"([^\"]*)\"");
    s = std::regex_replace(s, string_literal_re, "'$1'");
  } catch (...) {
  }

  auto ltrim = [](std::string &str) {
    str.erase(str.begin(), std::find_if(str.begin(), str.end(), [](unsigned char ch) { return !std::isspace(ch); }));
  };
  auto rtrim = [](std::string &str) {
    str.erase(std::find_if(str.rbegin(), str.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(), str.end());
  };
  ltrim(s);
  rtrim(s);
  return s;
}

std::string pg_gen_query_escape_literal(const std::string &in) {
  std::string out;
  out.reserve(in.size() + 2);
  for (char c : in) {
    if (c == '\'') out.push_back('\'');
    out.push_back(c);
  }
  return out;
}
