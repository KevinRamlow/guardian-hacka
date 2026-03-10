# Metabase Query Skill

Query the Brandlovrs Metabase instance for dashboards, questions, and data.

## Configuration
- **URL:** https://metabase.brandlovers.ai
- **API Key:** $METABASE_API_KEY in `$OPENCLAW_HOME/.env`

## Usage

### Search for questions/dashboards
```bash
curl -s -H "x-api-key: $METABASE_API_KEY" "https://metabase.brandlovers.ai/api/search?q=SEARCH_TERM" | python3 -m json.tool
```

### Get a specific question's data
```bash
curl -s -H "x-api-key: $METABASE_API_KEY" "https://metabase.brandlovers.ai/api/card/CARD_ID" | python3 -m json.tool
```

### Run a question (get results)
```bash
curl -s -X POST -H "x-api-key: $METABASE_API_KEY" -H "Content-Type: application/json" "https://metabase.brandlovers.ai/api/card/CARD_ID/query" | python3 -m json.tool
```

### Run native SQL query
```bash
curl -s -X POST -H "x-api-key: $METABASE_API_KEY" -H "Content-Type: application/json" \
  "https://metabase.brandlovers.ai/api/dataset" \
  -d '{"database": 1, "type": "native", "native": {"query": "SELECT 1"}}' | python3 -m json.tool
```

### List databases
```bash
curl -s -H "x-api-key: $METABASE_API_KEY" "https://metabase.brandlovers.ai/api/database" | python3 -m json.tool
```

### List dashboards
```bash
curl -s -H "x-api-key: $METABASE_API_KEY" "https://metabase.brandlovers.ai/api/dashboard" | python3 -m json.tool
```
