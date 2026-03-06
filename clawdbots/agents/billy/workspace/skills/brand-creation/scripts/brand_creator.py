#!/usr/bin/env python3
"""
brand_creator.py - Create brands in CreatorAds via validated DB inserts
"""

import sys
import re
import subprocess
from typing import Optional, Dict, Any
import unicodedata


def generate_slug(name: str) -> str:
    """Generate URL-safe slug from brand name."""
    # Lowercase
    slug = name.lower()
    
    # Remove accents
    slug = unicodedata.normalize('NFKD', slug)
    slug = slug.encode('ASCII', 'ignore').decode('ASCII')
    
    # Replace non-alphanumeric with hyphens
    slug = re.sub(r'[^a-z0-9]+', '-', slug)
    
    # Remove leading/trailing hyphens
    slug = slug.strip('-')
    
    # Remove consecutive hyphens
    slug = re.sub(r'-+', '-', slug)
    
    return slug


def check_existing_brands(name: str) -> list:
    """Check if brand with similar name exists."""
    query = f"SELECT id, name, brand_slug FROM brands WHERE name LIKE '%{name}%' AND deleted_at IS NULL LIMIT 5;"
    
    try:
        result = subprocess.run(
            ['mysql', '-e', query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        lines = result.stdout.strip().split('\n')
        if len(lines) <= 1:  # Only header or empty
            return []
        
        brands = []
        for line in lines[1:]:  # Skip header
            parts = line.split('\t')
            if len(parts) >= 3:
                brands.append({
                    'id': parts[0],
                    'name': parts[1],
                    'slug': parts[2]
                })
        
        return brands
    
    except subprocess.CalledProcessError:
        return []


def check_slug_exists(slug: str) -> bool:
    """Check if slug already exists."""
    query = f"SELECT COUNT(*) FROM brands WHERE brand_slug = '{slug}';"
    
    try:
        result = subprocess.run(
            ['mysql', '-s', '-N', '-e', query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        count = int(result.stdout.strip())
        return count > 0
    
    except (subprocess.CalledProcessError, ValueError):
        return True  # Assume exists on error (safe default)


def get_unique_slug(base_slug: str, max_attempts: int = 5) -> Optional[str]:
    """Generate unique slug by appending numbers if needed."""
    slug = base_slug
    
    for attempt in range(1, max_attempts + 1):
        if not check_slug_exists(slug):
            return slug
        
        slug = f"{base_slug}-{attempt + 1}"
    
    return None


def get_default_owner_id() -> int:
    """Get most common owner_id (likely platform admin)."""
    query = "SELECT owner_id FROM organizations GROUP BY owner_id ORDER BY COUNT(*) DESC LIMIT 1;"
    
    try:
        result = subprocess.run(
            ['mysql', '-s', '-N', '-e', query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        owner_id = result.stdout.strip()
        return int(owner_id) if owner_id else 1
    
    except (subprocess.CalledProcessError, ValueError):
        return 1  # Fallback to admin


def create_organization(name: str, owner_id: int) -> Optional[int]:
    """Create organization and return its ID."""
    # Escape single quotes in name
    escaped_name = name.replace("'", "''")
    
    insert_query = f"INSERT INTO organizations (name, owner_id, created_at, updated_at) VALUES ('{escaped_name}', {owner_id}, NOW(), NOW());"
    
    try:
        subprocess.run(
            ['mysql', '-e', insert_query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Get last insert ID
        result = subprocess.run(
            ['mysql', '-s', '-N', '-e', 'SELECT LAST_INSERT_ID();', 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        org_id = int(result.stdout.strip())
        return org_id if org_id > 0 else None
    
    except (subprocess.CalledProcessError, ValueError):
        return None


def create_brand(name: str, org_id: int, slug: str, description: Optional[str] = None) -> Optional[int]:
    """Create brand and return its ID."""
    # Escape single quotes
    escaped_name = name.replace("'", "''")
    
    if description:
        escaped_desc = description.replace("'", "''")
        desc_sql = f"'{escaped_desc}'"
    else:
        desc_sql = "NULL"
    
    insert_query = f"INSERT INTO brands (name, organization_id, brand_slug, description, created_at, updated_at) VALUES ('{escaped_name}', {org_id}, '{slug}', {desc_sql}, NOW(), NOW());"
    
    try:
        subprocess.run(
            ['mysql', '-e', insert_query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Get last insert ID
        result = subprocess.run(
            ['mysql', '-s', '-N', '-e', 'SELECT LAST_INSERT_ID();', 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        brand_id = int(result.stdout.strip())
        return brand_id if brand_id > 0 else None
    
    except (subprocess.CalledProcessError, ValueError):
        return None


def delete_organization(org_id: int):
    """Rollback: delete organization if brand creation fails."""
    query = f"DELETE FROM organizations WHERE id = {org_id};"
    
    try:
        subprocess.run(
            ['mysql', '-e', query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError:
        pass  # Best effort rollback


def get_brand_details(brand_id: int) -> Optional[Dict[str, Any]]:
    """Fetch created brand details."""
    query = f"""
    SELECT b.id, b.name, b.brand_slug, b.description, 
           b.created_at, o.id as org_id, o.name as org_name
    FROM brands b
    JOIN organizations o ON b.organization_id = o.id
    WHERE b.id = {brand_id};
    """
    
    try:
        result = subprocess.run(
            ['mysql', '-e', query, 'db-maestro-prod'],
            capture_output=True,
            text=True,
            check=True
        )
        
        lines = result.stdout.strip().split('\n')
        if len(lines) <= 1:
            return None
        
        # Parse result (skip header)
        parts = lines[1].split('\t')
        if len(parts) >= 7:
            return {
                'id': parts[0],
                'name': parts[1],
                'slug': parts[2],
                'description': parts[3] if parts[3] != 'NULL' else None,
                'created_at': parts[4],
                'org_id': parts[5],
                'org_name': parts[6]
            }
        
        return None
    
    except subprocess.CalledProcessError:
        return None


def create_brand_workflow(name: str, description: Optional[str] = None, force: bool = False) -> Dict[str, Any]:
    """
    Full brand creation workflow with validation.
    
    Returns:
        dict with keys: success (bool), message (str), brand (dict or None)
    """
    
    # Step 1: Check for existing brands
    if not force:
        existing = check_existing_brands(name)
        if existing:
            return {
                'success': False,
                'message': f"⚠️  Brand(s) with similar name found: {', '.join([b['name'] for b in existing])}",
                'existing': existing,
                'brand': None
            }
    
    # Step 2: Generate unique slug
    base_slug = generate_slug(name)
    slug = get_unique_slug(base_slug)
    
    if not slug:
        return {
            'success': False,
            'message': f"❌ Failed to generate unique slug for '{name}' (tried {base_slug}, {base_slug}-2, ..., {base_slug}-5)",
            'brand': None
        }
    
    # Step 3: Get default owner
    owner_id = get_default_owner_id()
    
    # Step 4: Create organization
    org_id = create_organization(name, owner_id)
    
    if not org_id:
        return {
            'success': False,
            'message': "❌ Failed to create organization",
            'brand': None
        }
    
    # Step 5: Create brand
    brand_id = create_brand(name, org_id, slug, description)
    
    if not brand_id:
        # Rollback organization
        delete_organization(org_id)
        return {
            'success': False,
            'message': "❌ Failed to create brand (organization rolled back)",
            'brand': None
        }
    
    # Step 6: Fetch created brand
    brand = get_brand_details(brand_id)
    
    if not brand:
        return {
            'success': False,
            'message': f"⚠️  Brand created (ID: {brand_id}) but failed to fetch details",
            'brand': {'id': brand_id, 'org_id': org_id}
        }
    
    return {
        'success': True,
        'message': f"✅ Brand '{name}' created successfully!",
        'brand': brand
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 brand_creator.py \"Brand Name\" [\"Description\"] [--force]")
        sys.exit(1)
    
    name = sys.argv[1]
    description = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else None
    force = '--force' in sys.argv
    
    # Run workflow
    result = create_brand_workflow(name, description, force)
    
    print(result['message'])
    
    if 'existing' in result:
        print("\nExisting brands:")
        for b in result['existing']:
            print(f"  - {b['name']} (ID: {b['id']}, slug: {b['slug']})")
        print("\nRun with --force to create anyway.")
        sys.exit(1)
    
    if result['success'] and result['brand']:
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("BRAND DETAILS")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        brand = result['brand']
        print(f"ID:           {brand['id']}")
        print(f"Name:         {brand['name']}")
        print(f"Slug:         {brand['slug']}")
        if brand.get('description'):
            print(f"Description:  {brand['description']}")
        print(f"Organization: {brand['org_name']} (ID: {brand['org_id']})")
        print(f"Created:      {brand['created_at']}")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
