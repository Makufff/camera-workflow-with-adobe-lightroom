import os
import json
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow
import requests
from datetime import datetime, timedelta

# Define the scopes for Google Photos API
SCOPES = ['https://www.googleapis.com/auth/photoslibrary']
TOKEN_FILE = 'token.json'
CREDENTIALS_FILE = 'credentials.json'

# Global cache for albums to improve performance
album_cache = {}
# Global token with expiration tracking
token_info = {
    'access_token': None,
    'expiry': None
}

def get_credentials():
    """Get and refresh OAuth2 credentials."""
    creds = None
    
    # Check if token file exists
    if os.path.exists(TOKEN_FILE):
        try:
            creds = Credentials.from_authorized_user_info(
                json.load(open(TOKEN_FILE)), SCOPES)
        except Exception as e:
            print(f"Error loading saved credentials: {e}")
    
    # If credentials don't exist or are invalid
    if not creds or not creds.valid:
        # Refresh token if possible
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
                print("Credentials refreshed successfully")
            except Exception as e:
                print(f"Error refreshing credentials: {e}")
                creds = None
        
        # Get new credentials if refresh failed or no existing credentials
        if not creds:
            try:
                if not os.path.exists(CREDENTIALS_FILE):
                    raise FileNotFoundError(f"Credentials file '{CREDENTIALS_FILE}' not found")
                
                flow = InstalledAppFlow.from_client_secrets_file(
                    CREDENTIALS_FILE, SCOPES)
                creds = flow.run_local_server(port=0)
                print("New credentials obtained successfully")
            except Exception as e:
                print(f"Error getting new credentials: {e}")
                raise
        
        # Save credentials
        with open(TOKEN_FILE, 'w') as token:
            token.write(creds.to_json())
            print(f"Credentials saved to {TOKEN_FILE}")
    
    return creds

def get_access_token():
    """Get a valid access token, refresh if needed."""
    global token_info
    
    # Check if token is already available and not expired
    current_time = datetime.now()
    if (token_info['access_token'] and token_info['expiry'] 
            and token_info['expiry'] > current_time):
        return token_info['access_token']
    
    try:
        creds = get_credentials()
        token_info['access_token'] = creds.token
        # Set expiry with a small buffer (5 min before actual expiry)
        token_info['expiry'] = datetime.now() + timedelta(seconds=creds.expires_in - 300)
        print("Access token obtained successfully")
        return token_info['access_token']
    except Exception as e:
        print(f"Error getting access token: {e}")
        raise

def get_album_id(album_title):
    """Get album ID by title, create if not exists."""
    global album_cache
    
    # Check cache first
    if album_title in album_cache:
        print(f"Album '{album_title}' found in cache")
        return album_cache[album_title]
    
    access_token = get_access_token()
    
    # Set headers for the request
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-type": "application/json"
    }
    
    # Get all albums
    try:
        url = "https://photoslibrary.googleapis.com/v1/albums"
        response = requests.get(url, headers=headers)
        response.raise_for_status()  # Raise exception for HTTP errors
        
        response_json = response.json()
        
        # Check if 'albums' key exists in response
        if 'albums' in response_json:
            # Find album by title
            for album in response_json['albums']:
                if album['title'] == album_title:
                    album_cache[album_title] = album['id']
                    print(f"Found existing album: {album_title}")
                    return album['id']
        
        # Album not found, create a new one
        album_id = create_album(album_title)
        album_cache[album_title] = album_id
        return album_id
    
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error occurred: {e}")
        if e.response.status_code == 401:
            # Token expired, clear token and retry once
            token_info['access_token'] = None
            token_info['expiry'] = None
            print("Token expired, retrying with new token")
            return get_album_id(album_title)
        raise
    except Exception as e:
        print(f"Error getting album ID: {e}")
        raise

def create_album(album_title):
    """Create a new album and return its ID."""
    access_token = get_access_token()
    
    # Set up request headers
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-type': 'application/json'
    }
    
    # Set up request payload
    payload = {
        "album": {
            "title": album_title
        }
    }
    
    try:
        # Send POST request to create album
        response = requests.post(
            'https://photoslibrary.googleapis.com/v1/albums',
            headers=headers, 
            json=payload
        )
        response.raise_for_status()
        
        # Parse response as JSON
        response_json = response.json()
        
        if 'id' not in response_json:
            raise ValueError("Album creation response missing ID field")
            
        album_id = response_json['id']
        print(f"Created new album: {album_title} (ID: {album_id})")
        return album_id
    
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error occurred when creating album: {e}")
        if e.response.status_code == 401:
            # Token expired, clear and retry once
            token_info['access_token'] = None
            token_info['expiry'] = None
            print("Token expired, retrying album creation with new token")
            return create_album(album_title)
        raise
    except Exception as e:
        print(f"Error creating album: {e}")
        raise

def add_photo_to_album(image_path, album_title):
    """Upload a photo and add it to an album."""
    if not os.path.exists(image_path):
        print(f"Error: Image file not found at {image_path}")
        return False
    
    try:
        access_token = get_access_token()
        album_id = get_album_id(album_title)
        
        # Set headers for upload
        upload_headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-type': 'application/octet-stream',
            'X-Goog-Upload-Content-Type': 'image/jpeg',
            'X-Goog-Upload-Protocol': 'raw'
        }
        
        # Read image data
        with open(image_path, 'rb') as f:
            image_data = f.read()
        
        # Upload the image to get an upload token
        upload_response = requests.post(
            'https://photoslibrary.googleapis.com/v1/uploads',
            headers=upload_headers, 
            data=image_data
        )
        
        if upload_response.status_code != 200:
            print(f"Error uploading image: {upload_response.status_code} - {upload_response.text}")
            return False
            
        upload_token = upload_response.text
        
        # Set headers for creating media item
        create_headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-type': 'application/json'
        }
        
        # Set payload for creating media item
        create_payload = {
            "albumId": album_id,
            "newMediaItems": [
                {
                    "simpleMediaItem": {
                        "uploadToken": upload_token
                    }
                }
            ]
        }
        
        # Create the media item
        create_response = requests.post(
            'https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate',
            headers=create_headers, 
            json=create_payload
        )
        
        create_response.raise_for_status()
        create_json = create_response.json()
        
        # Check if creation was successful
        if ('newMediaItemResults' in create_json and
                len(create_json['newMediaItemResults']) > 0 and
                'status' in create_json['newMediaItemResults'][0]):
            status = create_json['newMediaItemResults'][0]['status']
            if 'code' in status and status['code'] == 'OK':
                print(f"Photo added to album '{album_title}' successfully!")
                return True
            else:
                print(f"Error adding photo to album: {status.get('message', 'Unknown error')}")
                return False
        else:
            print("Failed to add photo to album: Unexpected response format")
            return False
    
    except requests.exceptions.HTTPError as e:
        print(f"HTTP error occurred: {e}")
        if e.response.status_code == 401:
            # Token expired, clear and retry once
            token_info['access_token'] = None
            token_info['expiry'] = None
            print("Token expired, retrying photo upload with new token")
            return add_photo_to_album(image_path, album_title)
        return False
    except Exception as e:
        print(f"Error adding photo to album: {e}")
        return False
