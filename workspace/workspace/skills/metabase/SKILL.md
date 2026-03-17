# Metabase Query Skill

Query the Brandlovrs Metabase instance via mcporter.

## Configuration
- **MCP server:** `metabase` in `workspace/config/mcporter.json`
- **URL:** https://metabase.brandlovers.ai
- **API Key:** $METABASE_API_KEY env var

## Usage

All Metabase access goes through mcporter:

```bash
# Discover available tools first
mcporter list metabase --schema

# Call any tool
mcporter call metabase.<tool_name> [params] --output json
```

## Common Operations

### Search questions/dashboards
```bash
mcporter call metabase.search q="campaign performance" --output json
```

### Run a saved question
```bash
mcporter call metabase.run_card card_id=123 --output json
```

### Run native SQL
```bash
mcporter call metabase.run_sql database_id=1 "query=SELECT COUNT(*) FROM campaigns" --output json
```

### List dashboards
```bash
mcporter call metabase.list_dashboards --output json
```

### List databases
```bash
mcporter call metabase.list_databases --output json
```
