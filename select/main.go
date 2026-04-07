// Select — A tiny HTTP server that turns URL paths into database queries
// and returns HTML, CSV, or JSON.
//
// Usage:
//   select
//   select -config /path/to/select.json
//
// URL patterns:
//   /                                        → list all tables and views (HTML)
//   /table_or_view                           → SELECT * FROM table_or_view (HTML)
//   /table_or_view.csv                       → same, as CSV
//   /table_or_view.json                      → same, as JSON
//   /table_or_view/col='value'               → adds WHERE col = 'value'
//   /table_or_view/orderby=col               → adds ORDER BY col
//   /table_or_view/orderby=col.desc          → adds ORDER BY col DESC
//   /table_or_view/limit=N                   → adds LIMIT N
//   /table_or_view/col='val'/orderby=col.csv → combined, as CSV
//
// The format extension (.csv, .json) goes on the last path segment.
// No extension defaults to HTML.
//
// Config (select.json):
//   {
//     "driver": "postgres",
//     "host": "localhost",
//     "port": 5432,
//     "database": "mydb",
//     "user": "user",
//     "password": "pass",
//     "listen": ":8080"
//   }
//
// For SQLite, use:
//   {
//     "driver": "sqlite",
//     "database": "/path/to/file.db",
//     "listen": ":8080"
//   }
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"

	_ "github.com/lib/pq"
	_ "modernc.org/sqlite"
)

type Config struct {
	Driver   string `json:"driver"`
	Host     string `json:"host"`
	Port     int    `json:"port"`
	Database string `json:"database"`
	User     string `json:"user"`
	Password string `json:"password"`
	Listen   string `json:"listen"`
}

var namePattern = regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_.]*$`)

func main() {
	configPath := flag.String("config", "select.json", "path to config file")
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	db, err := openDB(cfg)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("database ping: %v", err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		handler(w, r, db, cfg.Driver)
	})

	log.Printf("select listening on %s (%s/%s)", cfg.Listen, cfg.Driver, cfg.Database)
	log.Fatal(http.ListenAndServe(cfg.Listen, nil))
}

func loadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	if cfg.Listen == "" {
		cfg.Listen = ":8080"
	}
	if cfg.Driver == "" {
		cfg.Driver = "postgres"
	}
	if cfg.Port == 0 && cfg.Driver == "postgres" {
		cfg.Port = 5432
	}
	return cfg, nil
}

func openDB(cfg Config) (*sql.DB, error) {
	switch cfg.Driver {
	case "postgres":
		dsn := fmt.Sprintf("host=%s port=%d dbname=%s user=%s password=%s sslmode=disable",
			cfg.Host, cfg.Port, cfg.Database, cfg.User, cfg.Password)
		return sql.Open("postgres", dsn)
	case "sqlite":
		return sql.Open("sqlite", cfg.Database)
	default:
		return nil, fmt.Errorf("unsupported driver: %s", cfg.Driver)
	}
}

// parseFormat strips .csv or .json from the last path segment and returns
// the cleaned path and the format string ("html", "csv", or "json").
func parseFormat(path string) (string, string) {
	if path == "" {
		return path, "html"
	}
	if strings.HasSuffix(path, ".csv") {
		return strings.TrimSuffix(path, ".csv"), "csv"
	}
	if strings.HasSuffix(path, ".json") {
		return strings.TrimSuffix(path, ".json"), "json"
	}
	return path, "html"
}

func handler(w http.ResponseWriter, r *http.Request, db *sql.DB, driver string) {
	w.Header().Set("Access-Control-Allow-Origin", "*")

	path := strings.Trim(r.URL.Path, "/")
	path, format := parseFormat(path)

	// Root path: list tables
	if path == "" {
		listTables(w, db, driver, format)
		return
	}

	segments := strings.Split(path, "/")
	table := segments[0]

	if !namePattern.MatchString(table) {
		http.Error(w, "invalid table name", http.StatusBadRequest)
		return
	}

	query, args, err := buildQuery(table, segments[1:], driver)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	rows, err := db.Query(query, args...)
	if err != nil {
		http.Error(w, fmt.Sprintf("query error: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	switch format {
	case "json":
		writeJSON(w, rows)
	case "csv":
		writeCSV(w, rows)
	default:
		writeHTML(w, rows, query)
	}
}

func buildQuery(table string, segments []string, driver string) (string, []interface{}, error) {
	var wheres []string
	var args []interface{}
	var orderBy string
	var limit int
	paramIndex := 1

	for _, seg := range segments {
		if strings.HasPrefix(seg, "orderby=") {
			col := strings.TrimPrefix(seg, "orderby=")
			dir := "ASC"
			if strings.HasSuffix(col, ".desc") {
				col = strings.TrimSuffix(col, ".desc")
				dir = "DESC"
			} else if strings.HasSuffix(col, ".asc") {
				col = strings.TrimSuffix(col, ".asc")
			}
			if !namePattern.MatchString(col) {
				return "", nil, fmt.Errorf("invalid column name in orderby: %s", col)
			}
			orderBy = fmt.Sprintf("%s %s", col, dir)
			continue
		}

		if strings.HasPrefix(seg, "limit=") {
			n, err := strconv.Atoi(strings.TrimPrefix(seg, "limit="))
			if err != nil || n < 1 {
				return "", nil, fmt.Errorf("invalid limit: %s", seg)
			}
			limit = n
			continue
		}

		// WHERE condition: col='value'
		parts := strings.SplitN(seg, "=", 2)
		if len(parts) != 2 {
			return "", nil, fmt.Errorf("invalid segment: %s", seg)
		}
		col := parts[0]
		val := strings.Trim(parts[1], "'\"")
		if !namePattern.MatchString(col) {
			return "", nil, fmt.Errorf("invalid column name: %s", col)
		}

		placeholder := formatPlaceholder(driver, paramIndex)
		wheres = append(wheres, fmt.Sprintf("%s = %s", col, placeholder))
		args = append(args, val)
		paramIndex++
	}

	q := fmt.Sprintf("SELECT * FROM %s", table)
	if len(wheres) > 0 {
		q += " WHERE " + strings.Join(wheres, " AND ")
	}
	if orderBy != "" {
		q += " ORDER BY " + orderBy
	}
	if limit > 0 {
		q += fmt.Sprintf(" LIMIT %d", limit)
	}

	return q, args, nil
}

func formatPlaceholder(driver string, index int) string {
	if driver == "postgres" {
		return fmt.Sprintf("$%d", index)
	}
	return "?"
}

func listTables(w http.ResponseWriter, db *sql.DB, driver string, format string) {
	var query string
	switch driver {
	case "postgres":
		query = `SELECT table_schema || '.' || table_name AS name, table_type
			FROM information_schema.tables
			WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
			ORDER BY table_schema, table_name`
	case "sqlite":
		query = `SELECT name, type FROM sqlite_master
			WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'
			ORDER BY name`
	}

	rows, err := db.Query(query)
	if err != nil {
		http.Error(w, fmt.Sprintf("query error: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	switch format {
	case "json":
		writeJSON(w, rows)
	case "csv":
		writeCSV(w, rows)
	default:
		writeHTML(w, rows, query)
	}
}

func writeHTML(w http.ResponseWriter, rows *sql.Rows, query string) {
	cols, err := rows.Columns()
	if err != nil {
		http.Error(w, fmt.Sprintf("columns error: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	fmt.Fprint(w, `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>select</title>
<style>
body { font-family: -apple-system, system-ui, sans-serif; margin: 1rem; font-size: 14px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 0.4rem 0.6rem; text-align: left; }
th { background: #f5f5f5; font-weight: 600; position: sticky; top: 0; }
tr:hover { background: #f9f9f9; }
.query { color: #666; font-family: monospace; font-size: 0.85rem; margin-bottom: 1rem; }
</style>
</head>
<body>
`)
	fmt.Fprintf(w, "<p class=\"query\">%s</p>\n", escapeHTML(query))
	fmt.Fprint(w, "<table>\n<tr>")
	for _, col := range cols {
		fmt.Fprintf(w, "<th>%s</th>", escapeHTML(col))
	}
	fmt.Fprint(w, "</tr>\n")

	values := make([]interface{}, len(cols))
	ptrs := make([]interface{}, len(cols))
	for i := range values {
		ptrs[i] = &values[i]
	}

	for rows.Next() {
		if err := rows.Scan(ptrs...); err != nil {
			log.Printf("scan error: %v", err)
			return
		}
		fmt.Fprint(w, "<tr>")
		for _, v := range values {
			fmt.Fprintf(w, "<td>%s</td>", escapeHTML(fmt.Sprintf("%v", v)))
		}
		fmt.Fprint(w, "</tr>\n")
	}

	fmt.Fprint(w, "</table>\n</body>\n</html>")
}

func escapeHTML(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	s = strings.ReplaceAll(s, "\"", "&quot;")
	return s
}

func writeCSV(w http.ResponseWriter, rows *sql.Rows) {
	cols, err := rows.Columns()
	if err != nil {
		http.Error(w, fmt.Sprintf("columns error: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/csv")

	writer := csv.NewWriter(w)
	writer.Write(cols)

	values := make([]interface{}, len(cols))
	ptrs := make([]interface{}, len(cols))
	for i := range values {
		ptrs[i] = &values[i]
	}

	for rows.Next() {
		if err := rows.Scan(ptrs...); err != nil {
			log.Printf("scan error: %v", err)
			return
		}
		record := make([]string, len(cols))
		for i, v := range values {
			record[i] = fmt.Sprintf("%v", v)
		}
		writer.Write(record)
	}
	writer.Flush()
}

func writeJSON(w http.ResponseWriter, rows *sql.Rows) {
	cols, err := rows.Columns()
	if err != nil {
		http.Error(w, fmt.Sprintf("columns error: %v", err), http.StatusInternalServerError)
		return
	}

	var results []map[string]interface{}
	values := make([]interface{}, len(cols))
	ptrs := make([]interface{}, len(cols))
	for i := range values {
		ptrs[i] = &values[i]
	}

	for rows.Next() {
		if err := rows.Scan(ptrs...); err != nil {
			log.Printf("scan error: %v", err)
			return
		}
		row := make(map[string]interface{})
		for i, col := range cols {
			val := values[i]
			if b, ok := val.([]byte); ok {
				val = string(b)
			}
			row[col] = val
		}
		results = append(results, row)
	}

	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(results)
}
