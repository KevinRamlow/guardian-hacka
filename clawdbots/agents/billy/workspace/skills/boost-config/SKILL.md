# Boost Configuration Skill

Conversational interface for managing boost configurations.

## Usage

**Show config:**
- "show boost config for Kibon"
- "what's the boost limit for Sprite?"
- "boost config for all brands"

**Update limit:**
- "update boost limit for Kibon to 1000 per month"
- "set boost limit to 500 for Sprite"

**Enable/disable:**
- "disable boost for Kibon Summer2024"
- "enable boost for Sprite campaign"

## Commands

```bash
# Show config for brand
bash skills/boost-config/boost-config.sh show "Kibon"

# Update limit
bash skills/boost-config/boost-config.sh update "Kibon" 1000

# Disable/enable
bash skills/boost-config/boost-config.sh disable "Kibon" "Summer2024"
bash skills/boost-config/boost-config.sh enable "Kibon" "Summer2024"
```

## Database

Tables: `boost_configurations`, `brands`, `campaigns`

Schema:
- boost_configurations: brand_id, campaign_id, enabled, monthly_limit, current_usage
- brands: id, name
- campaigns: id, name, brand_id

## Requirements

- MySQL/Cloud SQL Proxy access
- Read/write permissions on boost_configurations table
