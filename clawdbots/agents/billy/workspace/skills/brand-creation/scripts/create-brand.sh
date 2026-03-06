#!/bin/bash
# create-brand.sh - Create brands in CreatorAds via validated DB inserts
# Usage: bash create-brand.sh "Brand Name" ["Description"]

set -e

BRAND_NAME="$1"
DESCRIPTION="${2:-}"

if [ -z "$BRAND_NAME" ]; then
    echo "❌ Usage: bash create-brand.sh \"Brand Name\" [\"Description\"]"
    exit 1
fi

# Database connection
DB="db-maestro-prod"

# Function to generate slug
generate_slug() {
    local name="$1"
    # Lowercase, remove accents, replace spaces with hyphens, remove special chars
    echo "$name" | tr '[:upper:]' '[:lower:]' | \
        iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-//' | \
        sed 's/-$//'
}

# Function to check if brand exists
check_existing() {
    local name="$1"
    mysql -e "SELECT id, name, brand_slug FROM brands WHERE name LIKE '%$name%' AND deleted_at IS NULL LIMIT 5;" "$DB"
}

# Function to check slug uniqueness
check_slug() {
    local slug="$1"
    mysql -s -N -e "SELECT COUNT(*) FROM brands WHERE brand_slug = '$slug';" "$DB"
}

# Function to get default owner_id
get_default_owner() {
    mysql -s -N -e "SELECT owner_id FROM organizations GROUP BY owner_id ORDER BY COUNT(*) DESC LIMIT 1;" "$DB"
}

echo "🔍 Checking for existing brands..."
EXISTING=$(check_existing "$BRAND_NAME")

if [ -n "$EXISTING" ]; then
    echo "⚠️  Brand(s) found with similar name:"
    echo "$EXISTING"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled."
        exit 1
    fi
fi

echo "🏷️  Generating slug..."
BASE_SLUG=$(generate_slug "$BRAND_NAME")
SLUG="$BASE_SLUG"
ATTEMPT=1

while [ $(check_slug "$SLUG") -gt 0 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    SLUG="${BASE_SLUG}-${ATTEMPT}"
    if [ $ATTEMPT -gt 5 ]; then
        echo "❌ Failed to generate unique slug after 5 attempts."
        exit 1
    fi
done

echo "✅ Slug: $SLUG"

echo "🏢 Getting default owner_id..."
OWNER_ID=$(get_default_owner)
if [ -z "$OWNER_ID" ]; then
    OWNER_ID=1  # Fallback to admin
fi
echo "✅ Owner ID: $OWNER_ID"

echo "🏗️  Creating organization..."
ORG_INSERT="INSERT INTO organizations (name, owner_id, created_at, updated_at) VALUES ('$BRAND_NAME', $OWNER_ID, NOW(), NOW());"
mysql -e "$ORG_INSERT" "$DB"

ORG_ID=$(mysql -s -N -e "SELECT LAST_INSERT_ID();" "$DB")
if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "0" ]; then
    echo "❌ Failed to create organization."
    exit 1
fi
echo "✅ Organization created: ID $ORG_ID"

echo "🎨 Creating brand..."
if [ -n "$DESCRIPTION" ]; then
    DESC_SQL="'$(echo "$DESCRIPTION" | sed "s/'/''/g")'"
else
    DESC_SQL="NULL"
fi

BRAND_INSERT="INSERT INTO brands (name, organization_id, brand_slug, description, created_at, updated_at) VALUES ('$BRAND_NAME', $ORG_ID, '$SLUG', $DESC_SQL, NOW(), NOW());"
mysql -e "$BRAND_INSERT" "$DB"

BRAND_ID=$(mysql -s -N -e "SELECT LAST_INSERT_ID();" "$DB")
if [ -z "$BRAND_ID" ] || [ "$BRAND_ID" = "0" ]; then
    echo "❌ Failed to create brand. Rolling back organization..."
    mysql -e "DELETE FROM organizations WHERE id = $ORG_ID;" "$DB"
    exit 1
fi
echo "✅ Brand created: ID $BRAND_ID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BRAND CREATED SUCCESSFULLY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mysql -e "SELECT b.id, b.name, b.brand_slug, b.description, b.created_at, o.id as org_id, o.name as org_name FROM brands b JOIN organizations o ON b.organization_id = o.id WHERE b.id = $BRAND_ID;" "$DB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
