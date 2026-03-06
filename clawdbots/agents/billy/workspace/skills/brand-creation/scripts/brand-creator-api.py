#!/usr/bin/env python3
"""
brand-creator-api.py - Create brands via user-management-api

This script provides a Python interface for Billy to create brands using the
user-management-api POST /v1/brands endpoint.

Features:
- Duplicate detection (checks existing brands by name/slug)
- Slug validation and generation
- API error handling
- Structured JSON output for Billy

Usage:
    python3 brand-creator-api.py "Brand Name" "Description" [fee_percentage] [auto_approve_groups]

Environment Variables:
    USER_MGMT_API_URL    - Base URL for user-management-api
    USER_MGMT_API_TOKEN  - Bearer token with platform admin permissions

Example:
    export USER_MGMT_API_URL="https://user-management-api.brandlovers.ai"
    export USER_MGMT_API_TOKEN="your-platform-admin-token"
    python3 brand-creator-api.py "Nike" "Sportswear brand" 5 false
"""

import os
import sys
import json
import re
import requests
from typing import Optional, Dict, Any


class BrandCreatorAPI:
    """Creates brands via user-management-api"""

    def __init__(self):
        self.api_url = os.getenv("USER_MGMT_API_URL")
        self.api_token = os.getenv("USER_MGMT_API_TOKEN")

        if not self.api_url:
            self._error("USER_MGMT_API_URL environment variable not set")
            sys.exit(1)

        if not self.api_token:
            self._error("USER_MGMT_API_TOKEN environment variable not set")
            sys.exit(1)

        # Remove trailing slash from URL
        self.api_url = self.api_url.rstrip("/")

    def _error(self, message: str):
        """Print error message to stderr"""
        print(f"❌ ERROR: {message}", file=sys.stderr)

    def _info(self, message: str):
        """Print info message"""
        print(f"ℹ️  {message}", file=sys.stderr)

    def _success(self, message: str):
        """Print success message"""
        print(f"✅ {message}", file=sys.stderr)

    def _warning(self, message: str):
        """Print warning message"""
        print(f"⚠️  {message}", file=sys.stderr)

    def generate_slug(self, name: str) -> str:
        """
        Generate brand slug from name.
        Rules: lowercase, alphanumeric only, hyphens for spaces
        """
        # Convert to lowercase
        slug = name.lower()
        # Replace non-alphanumeric with hyphens
        slug = re.sub(r"[^a-z0-9]+", "-", slug)
        # Remove leading/trailing hyphens
        slug = slug.strip("-")
        # Collapse multiple hyphens
        slug = re.sub(r"-+", "-", slug)
        return slug

    def check_duplicate(self, name: str, slug: str) -> Optional[Dict[str, Any]]:
        """
        Check if a brand with similar name or slug already exists.
        Returns the existing brand if found, None otherwise.
        """
        try:
            # Search by name
            response = requests.get(
                f"{self.api_url}/v1/brands",
                headers={"Authorization": f"Bearer {self.api_token}"},
                params={"search": name, "perPage": 10},
                timeout=10,
            )

            if response.status_code == 200:
                data = response.json()
                brands = data.get("data", [])

                # Check for exact name match or slug match
                for brand in brands:
                    if (
                        brand.get("name", "").lower() == name.lower()
                        or brand.get("brandSlug", "") == slug
                    ):
                        return brand

            return None
        except Exception as e:
            self._warning(f"Could not check for duplicates: {e}")
            return None

    def create_brand(
        self,
        name: str,
        description: str = "",
        default_fee: int = 5,
        auto_approve_groups: bool = False,
    ) -> Dict[str, Any]:
        """
        Create a new brand via API.

        Args:
            name: Brand name (1-100 chars, required)
            description: Brand description (max 2048 chars, optional)
            default_fee: Default fee percentage (0-100, default 5)
            auto_approve_groups: Auto-approve groups flag (default false)

        Returns:
            Dict with status, brand data, or error message
        """
        # Validate inputs
        if not name or len(name) < 1 or len(name) > 100:
            return {
                "success": False,
                "error": "Brand name must be between 1 and 100 characters",
            }

        if description and len(description) > 2048:
            return {
                "success": False,
                "error": "Description must be max 2048 characters",
            }

        if not isinstance(default_fee, int) or default_fee < 0 or default_fee > 100:
            return {
                "success": False,
                "error": "defaultFeePercentage must be between 0 and 100",
            }

        # Generate slug
        slug = self.generate_slug(name)

        if not slug or len(slug) < 1 or len(slug) > 150:
            return {
                "success": False,
                "error": f"Generated slug is invalid: {slug}",
            }

        # Check for duplicates
        self._info(f"Checking for existing brands named '{name}'...")
        existing = self.check_duplicate(name, slug)

        if existing:
            self._warning("Brand already exists!")
            return {
                "success": False,
                "error": "DUPLICATE",
                "existing_brand": {
                    "id": existing.get("id"),
                    "name": existing.get("name"),
                    "slug": existing.get("brandSlug"),
                    "description": existing.get("description"),
                },
                "message": f"Brand '{existing.get('name')}' (ID: {existing.get('id')}) already exists with slug '{existing.get('brandSlug')}'",
            }

        # Build request payload
        payload = {
            "name": name,
            "brand_slug": slug,
            "defaultFeePercentage": default_fee,
            "autoApproveGroups": auto_approve_groups,
        }

        if description:
            payload["description"] = description

        # Make API request
        self._info(f"Creating brand '{name}' with slug '{slug}'...")

        try:
            response = requests.post(
                f"{self.api_url}/v1/brands",
                headers={
                    "Authorization": f"Bearer {self.api_token}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=30,
            )

            if response.status_code in (200, 201):
                brand_data = response.json()
                self._success(f"Brand created successfully! ID: {brand_data.get('id')}")

                return {
                    "success": True,
                    "brand": {
                        "id": brand_data.get("id"),
                        "name": brand_data.get("name"),
                        "slug": brand_data.get("brandSlug"),
                        "description": brand_data.get("description"),
                        "defaultFeePercentage": brand_data.get("defaultFeePercentage"),
                        "autoApproveGroups": brand_data.get("autoApproveGroups"),
                        "logoUrl": brand_data.get("logoUrl"),
                        "createdAt": brand_data.get("createdAt"),
                    },
                    "message": f"Brand '{name}' created with ID {brand_data.get('id')}",
                }
            else:
                error_data = response.json() if response.text else {}
                error_msg = error_data.get("message", response.text)

                self._error(f"API request failed (HTTP {response.status_code})")

                return {
                    "success": False,
                    "error": "API_ERROR",
                    "http_code": response.status_code,
                    "message": error_msg,
                    "details": error_data,
                }

        except requests.exceptions.Timeout:
            self._error("Request timed out")
            return {"success": False, "error": "TIMEOUT", "message": "Request timed out after 30 seconds"}

        except requests.exceptions.ConnectionError as e:
            self._error(f"Connection error: {e}")
            return {"success": False, "error": "CONNECTION_ERROR", "message": str(e)}

        except Exception as e:
            self._error(f"Unexpected error: {e}")
            return {"success": False, "error": "UNEXPECTED_ERROR", "message": str(e)}


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: brand-creator-api.py <name> [description] [fee_percentage] [auto_approve_groups]", file=sys.stderr)
        print("", file=sys.stderr)
        print("Example:", file=sys.stderr)
        print('  python3 brand-creator-api.py "Nike" "Sportswear brand" 5 false', file=sys.stderr)
        sys.exit(1)

    # Parse arguments
    name = sys.argv[1]
    description = sys.argv[2] if len(sys.argv) > 2 else ""
    default_fee = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    auto_approve_groups = sys.argv[4].lower() == "true" if len(sys.argv) > 4 else False

    # Create brand
    creator = BrandCreatorAPI()
    result = creator.create_brand(name, description, default_fee, auto_approve_groups)

    # Output JSON for Billy to parse
    print(json.dumps(result, indent=2))

    # Exit code
    sys.exit(0 if result.get("success") else 1)


if __name__ == "__main__":
    main()
