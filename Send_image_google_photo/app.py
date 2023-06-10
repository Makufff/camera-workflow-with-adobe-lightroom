from utils import *
import os
import shutil
import time

path_to_send = "D:\workflow_camera\OUTPUT"
path_to_move = "D:\workflow_camera\MOVEFILE"
album_name = "123"

while True :
    if len(os.listdir(path_to_send)) != 0 :
        for photo_path in os.listdir(path_to_send):
            add_photo_to_album(path_to_send + "\\" + photo_path , album_name)
            shutil.move(path_to_send + "\\" + photo_path, path_to_move + "\\" + photo_path)
            print("upload and move successfully")
    else :
        print("emtry to photo file")
        time.sleep(5)
