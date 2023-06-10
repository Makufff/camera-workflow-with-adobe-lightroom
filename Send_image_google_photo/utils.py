import httplib2
from oauth2client.client import flow_from_clientsecrets
from oauth2client.file import Storage
from oauth2client.tools import run_flow
import requests
import os

# CLIENT_ID = '714770258367-o929tdpsr8o4i5flv5sbrv3eh3ao9ege.apps.googleusercontent.com'
# CLIENT_SECRET = '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'

# Start the OAuth flow to retrieve credentials
def authorize_credentials():
    CLIENT_SECRET = 'credentials.json'
    SCOPE = 'https://www.googleapis.com/auth/photoslibrary'
    STORAGE = Storage('credentials.storage')
    # Fetch credentials from storage
    credentials = STORAGE.get()
    # If the credentials don't exist in the storage location, then run the flow
    if credentials is None or credentials.invalid:
        flow = flow_from_clientsecrets(CLIENT_SECRET, scope=SCOPE)
        http = httplib2.Http()
        credentials = run_flow(flow, STORAGE, http=http)
    return credentials

def get_access_token():
    credentials = authorize_credentials()
    access_token = credentials.access_token
    print("get access token")
    return access_token

acc_token = get_access_token()

def get_album_id(album_title):
    access_token = acc_token
    # Set the headers for the request
    headers = {
        "Authorization": "Bearer " + access_token,
        "Content-type": "application/json"
    }

    # Set the URL for the request
    url = "https://photoslibrary.googleapis.com/v1/albums"

    # Send the GET request
    response = requests.get(url, headers=headers)

    # Parse the response as JSON
    response_json = response.json()
    # print(response_json)
    # Find the album with the specified title
    for album in response_json["albums"]:
        if album["title"] == album_title:
            return album["id"]

    # If the album is not found, create a new one
    album_id = create_album(album_title)
    return album_id

def create_album(album_title):
    access_token = acc_token
    # Set up the request headers
    headers = {
        'Authorization': 'Bearer %s' % access_token,
        'Content-type': 'application/json'
    }
    # Set up the request payload
    payload = {
        "album": {
            "title": album_title
        }
    }
    # Send the POST request to create the album
    response = requests.post('https://photoslibrary.googleapis.com/v1/albums',
                             headers=headers, json=payload)

    # Parse the response as JSON
    response_json = response.json()

    # Get the ID of the newly created album
    album_id = response_json["id"]
    return album_id

def add_photo_to_album(image_path, album_title):
    access_token = acc_token
    album_id = get_album_id(album_title)

    # Set up the request headers
    headers = {
        'Authorization': 'Bearer %s' % access_token,
        'Content-type': 'application/octet-stream',
        'X-Goog-Upload-Content-Type': 'image/jpeg',
        'X-Goog-Upload-Protocol': 'raw'
    }

    # Read the binary data from the file
    with open(image_path, 'rb') as f:
        image_data = f.read()

    # Send the POST request to get the upload token
    response = requests.post('https://photoslibrary.googleapis.com/v1/uploads',
                             headers=headers, data=image_data)

    # Check if the request was successful and get the upload token
    if response.status_code == requests.codes.ok:
        upload_token = response.text

        headers = {
            'Authorization': 'Bearer %s' % access_token,
            'Content-type': 'application/json'
        }

        payload = {
            "albumId": album_id,
            "newMediaItems": [
                {
                    "simpleMediaItem": {
                        "uploadToken": upload_token
                    }
                }
            ]
        }

        # Send the POST request to add the photo to the album
        response = requests.post('https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate',
                                 headers=headers, json=payload)

        # Parse the response as JSON
        response_json = response.json()

        # Check if the photo was successfully added to the album
        if 'newMediaItemResults' in response_json:
            print("Photo added to the album successfully!")
        else:
            print("Failed to add photo to the album.")

    else:
        response.raise_for_status()
