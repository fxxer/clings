#!/usr/bin/env bash
# update-schema-baseline.sh
# Dumps the live Things 3 database schema to the baseline file.
# Run this after confirming a Things 3 update is compatible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_FILE="$REPO_ROOT/Tests/SchemaBaseline/schema-baseline.json"

# Find the Things 3 database
THINGS_BASE="$HOME/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac"
DB_PATH=""

for dir in "$THINGS_BASE"/ThingsData-*; do
    candidate="$dir/Things Database.thingsdatabase/main.sqlite"
    if [ -f "$candidate" ]; then
        DB_PATH="$candidate"
        break
    fi
done

if [ -z "$DB_PATH" ]; then
    # Fallback to old location
    candidate="$THINGS_BASE/Things Database.thingsdatabase/main.sqlite"
    if [ -f "$candidate" ]; then
        DB_PATH="$candidate"
    fi
fi

if [ -z "$DB_PATH" ]; then
    echo "Error: Things 3 database not found. Is Things 3 installed?" >&2
    exit 1
fi

echo "Using database: $DB_PATH"

TABLES="TMTask TMArea TMTag TMTaskTag TMAreaTag TMChecklistItem"

python3 - "$DB_PATH" "$TABLES" > "$BASELINE_FILE" <<'PYTHON_SCRIPT'
import sqlite3, json, sys

db_path = sys.argv[1]
tables = sys.argv[2].split()
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
schema = {}

for table in tables:
    cursor.execute(f'PRAGMA table_info({table})')
    columns = []
    for row in cursor.fetchall():
        columns.append({
            'cid': row[0],
            'name': row[1],
            'type': row[2],
            'notnull': row[3],
            'pk': row[5]
        })
    schema[table] = {
        'columns': columns,
        'column_count': len(columns)
    }

conn.close()
print(json.dumps(schema, indent=2))
PYTHON_SCRIPT

echo "Schema baseline updated: $BASELINE_FILE"
echo "Tables captured: $TABLES"

# Show summary
for table in $TABLES; do
    count=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['$table']['column_count'])")
    echo "  $table: $count columns"
done
