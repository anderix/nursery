# select

A tiny HTTP server that turns URL paths into database queries and returns HTML,
CSV, or JSON. Point it at a SQLite or PostgreSQL database and browse tables and
views by visiting URLs — no query writing for the common cases.

## Usage

```
select
select -config /path/to/select.json
```

By default it reads `select.json` in the working directory.

## URL patterns

```
/                                        list all tables and views (HTML)
/table_or_view                           SELECT * FROM table_or_view (HTML)
/table_or_view.csv                       same, as CSV
/table_or_view.json                      same, as JSON
/table_or_view/col='value'               adds WHERE col = 'value'
/table_or_view/orderby=col               adds ORDER BY col
/table_or_view/orderby=col.desc          adds ORDER BY col DESC
/table_or_view/limit=N                   adds LIMIT N
/table_or_view/col='val'/orderby=col.csv combined, as CSV
```

The format extension (`.csv`, `.json`) goes on the last path segment; no
extension defaults to HTML.

## Config

`select.json`:

```json
{
  "driver": "postgres",
  "host": "localhost",
  "port": 5432,
  "database": "mydb",
  "user": "user",
  "password": "pass",
  "listen": ":8080"
}
```

For SQLite:

```json
{
  "driver": "sqlite",
  "database": "/path/to/file.db",
  "listen": ":8080"
}
```

## Build

```
go build -o select .
```

`select` is a Go tool and builds in place; it is not copied into `~/bin` by
`install-most.sh`.
