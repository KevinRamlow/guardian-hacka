#!/bin/bash
# Metabase query helper for Son of Anton
set -euo pipefail
source ~/workspace/.env.secrets 2>/dev/null || true

ACTION="${1:-help}"
ARG="${2:-}"

case "$ACTION" in
  search)
    curl -s -H "x-api-key: $METABASE_API_KEY" "$METABASE_URL/api/search?q=$ARG" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(f'{r[\"model\"]}: {r[\"name\"]} (id={r[\"id\"]})') for r in d.get('data',[])]"
    ;;
  query)
    curl -s -X POST -H "x-api-key: $METABASE_API_KEY" -H "Content-Type: application/json" "$METABASE_URL/api/card/$ARG/query" | python3 -m json.tool
    ;;
  sql)
    shift
    SQL="$*"
    curl -s -X POST -H "x-api-key: $METABASE_API_KEY" -H "Content-Type: application/json" \
      "$METABASE_URL/api/dataset" \
      -d "{\"database\": 1, \"type\": \"native\", \"native\": {\"query\": \"$SQL\"}}" | python3 -c "
import json,sys
d = json.load(sys.stdin)
rows = d.get('data',{}).get('rows',[])
cols = [c['name'] for c in d.get('data',{}).get('cols',[])]
print('\t'.join(cols))
for r in rows[:50]:
    print('\t'.join(str(x) for x in r))
"
    ;;
  dashboards)
    curl -s -H "x-api-key: $METABASE_API_KEY" "$METABASE_URL/api/dashboard" | python3 -c "import json,sys; [print(f'id={d[\"id\"]}: {d[\"name\"]}') for d in json.load(sys.stdin)]"
    ;;
  *)
    echo "Usage: metabase-query.sh {search|query|sql|dashboards} [args]"
    echo "  search <term>     - Search questions/dashboards"
    echo "  query <card_id>   - Run a saved question"
    echo "  sql <query>       - Run raw SQL"
    echo "  dashboards        - List all dashboards"
    ;;
esac
