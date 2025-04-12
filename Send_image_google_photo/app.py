from utils import add_photo_to_album
import os
import shutil
import time
import sys
import signal
import logging
from pathlib import Path

# Configure logging with UTF-8 encoding
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("photo_upload.log", encoding='utf-8'),
        # Use only file handler by default to avoid console encoding issues
    ]
)

# Add console handler only if terminal supports UTF-8 (not on Windows by default)
if sys.platform != 'win32':
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
    logging.getLogger().addHandler(console_handler)

logger = logging.getLogger('photo_uploader')

# Use Path for correct file path handling
path_to_send = Path("..\OUTPUT").resolve()
path_to_move = Path("..\MOVEFILE").resolve()
album_name = "123"

# Check if folders exist, create if not
if not path_to_send.exists():
    logger.info(f"Creating folder {path_to_send}")
    path_to_send.mkdir(parents=True, exist_ok=True)

if not path_to_move.exists():
    logger.info(f"Creating folder {path_to_move}")
    path_to_move.mkdir(parents=True, exist_ok=True)

logger.info(f"Starting: Monitoring images in {path_to_send} and uploading to Google Photos album '{album_name}'")

# Control variable
running = True

# Signal handler function to stop execution
def signal_handler(sig, frame):
    global running
    logger.info("Received signal to stop. Shutting down...")
    running = False

# Register signal handlers
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

try:
    while running:
        try:
            # Check for files in the folder
            files = list(path_to_send.glob('*'))
            if files:
                for photo_path in files:
                    try:
                        if photo_path.is_file():  # Check that it's a file
                            logger.info(f"Uploading image: {photo_path.name}")
                            
                            # Upload the photo to Google Photos
                            success = add_photo_to_album(str(photo_path), album_name)
                            
                            if success:
                                # Move file to MOVEFILE folder
                                dest_path = path_to_move / photo_path.name
                                shutil.move(str(photo_path), str(dest_path))
                                logger.info(f"Successfully uploaded and moved: {photo_path.name}")
                            else:
                                logger.error(f"Upload failed: {photo_path.name}")
                    except Exception as e:
                        logger.error(f"Error processing file {photo_path.name}: {e}")
            else:
                logger.info("No images found in folder, waiting for next check...")
            time.sleep(5)
                
        except Exception as e:
            logger.error(f"Error occurred: {e}")
            time.sleep(5)

except KeyboardInterrupt:
    logger.info("User stopped the program")
finally:
    logger.info("Program terminated")
