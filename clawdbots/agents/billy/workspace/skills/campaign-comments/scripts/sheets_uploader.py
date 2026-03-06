#!/usr/bin/env python3
"""
Upload campaign comments to Google Sheets using Google Sheets API
"""

import json
import os
import sys
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

# Scopes required for creating and sharing sheets
SCOPES = [
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/drive.file'
]

# OAuth client config (from gog)
CLIENT_CONFIG = {
    "installed": {
        "client_id": "" + os.environ.get("GOOGLE_CLIENT_ID", "") + "",
        "client_secret": "" + os.environ.get("GOOGLE_CLIENT_SECRET", "") + "",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "redirect_uris": ["http://localhost"]
    }
}

TOKEN_FILE = Path.home() / '.openclaw' / 'workspace' / 'clawdbots' / 'agents' / 'billy' / 'workspace' / 'skills' / 'campaign-comments' / '.google_sheets_token.json'


def get_credentials():
    """Get or create OAuth credentials for Google Sheets API"""
    creds = None
    
    # Load existing token if available
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    
    # Refresh or create new token
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception as e:
                print(f"⚠️  Token refresh failed: {e}")
                creds = None
        
        if not creds:
            # Need manual OAuth flow (console mode)
            flow = InstalledAppFlow.from_client_config(
                CLIENT_CONFIG, SCOPES,
                redirect_uri='urn:ietf:wg:oauth:2.0:oob'
            )
            
            auth_url, _ = flow.authorization_url(prompt='consent')
            
            print("\n" + "=" * 70)
            print("⚠️  GOOGLE OAUTH AUTHORIZATION REQUIRED")
            print("=" * 70)
            print("\n1. Open this URL in your browser:")
            print(f"\n{auth_url}\n")
            print("2. Approve access to Google Sheets and Drive")
            print("3. Copy the authorization code")
            print("4. Paste it below")
            print("=" * 70)
            
            code = input("\nEnter authorization code: ").strip()
            flow.fetch_token(code=code)
            creds = flow.credentials
            
        # Save the credentials
        TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(TOKEN_FILE, 'w') as token:
            token.write(creds.to_json())
    
    return creds


def create_spreadsheet(title, data):
    """
    Create a new Google Spreadsheet with the given data
    
    Args:
        title: Spreadsheet title
        data: List of lists (rows of data)
    
    Returns:
        Spreadsheet ID and URL
    """
    try:
        creds = get_credentials()
        
        # Create Sheets service
        sheets_service = build('sheets', 'v4', credentials=creds)
        drive_service = build('drive', 'v3', credentials=creds)
        
        # Create new spreadsheet
        spreadsheet = {
            'properties': {
                'title': title
            }
        }
        
        spreadsheet = sheets_service.spreadsheets().create(
            body=spreadsheet,
            fields='spreadsheetId,spreadsheetUrl'
        ).execute()
        
        spreadsheet_id = spreadsheet.get('spreadsheetId')
        spreadsheet_url = spreadsheet.get('spreadsheetUrl')
        
        print(f"✅ Created spreadsheet: {spreadsheet_id}")
        
        # Add data to the sheet
        body = {
            'values': data
        }
        
        result = sheets_service.spreadsheets().values().update(
            spreadsheetId=spreadsheet_id,
            range='A1',
            valueInputOption='RAW',
            body=body
        ).execute()
        
        print(f"✅ Updated {result.get('updatedCells')} cells")
        
        # Share with anyone (view only)
        permission = {
            'type': 'anyone',
            'role': 'reader'
        }
        
        drive_service.permissions().create(
            fileId=spreadsheet_id,
            body=permission
        ).execute()
        
        print(f"✅ Shared publicly (view only)")
        
        return spreadsheet_id, spreadsheet_url
        
    except HttpError as error:
        print(f"❌ An error occurred: {error}")
        sys.exit(1)


def main():
    if len(sys.argv) != 3:
        print("Usage: sheets_uploader.py <title> <data.json>")
        sys.exit(1)
    
    title = sys.argv[1]
    data_file = sys.argv[2]
    
    # Load data from JSON file
    with open(data_file, 'r') as f:
        data = json.load(f)
    
    # Create spreadsheet
    spreadsheet_id, url = create_spreadsheet(title, data)
    
    print(f"\n🔗 {url}")


if __name__ == '__main__':
    main()
