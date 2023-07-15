# Camera Workflow with Adobe Lightroom

This project is a script for automated photo editing using Adobe Lightroom plugins. The script allows for automatic photo editing and uploads the edited images to Google Photos using the Google API.

## Introduction

The "Camera Workflow with Adobe Lightroom" project aims to streamline the process of editing and uploading photos by automating the tasks using Adobe Lightroom and the Google Photos API.

## Tools

The following tools are used in this project:

- Adobe Lightroom: A powerful photo editing software.
- Adobe Lightroom Plugins: Specific plugins/add-ons for Adobe Lightroom that enhance its functionality.
- Google Photos API: An API provided by Google that allows for interaction with Google Photos platform.

## Programming Language

The scripting for this project is done using Lua and Python. Lua is used for scripting within Adobe Lightroom, while Python is used to interact with the Google Photos API.

## How to Use

To use the "Camera Workflow with Adobe Lightroom" script, follow these steps:

1. Install Adobe Lightroom: If you haven't already, download and install Adobe Lightroom on your computer.
2. Install Adobe Lightroom Plugins: Install the necessary plugins/add-ons required for automating the photo editing process within Adobe Lightroom. (add Lightroom_Extension_Auto_Workflow.lrdevplugin file in plugin)
3. Set up Google Photos API: Create a project on the Google Cloud Platform, enable the Google Photos API, and generate the required credentials (API key, OAuth client ID, etc.).
4. Clone the Repository: Clone the project repository to your local machine.
5. Configure the Script: Open the script files and provide the necessary configuration details such as API credentials, file paths, etc.
6. Run the Script: Execute the script, and it will automatically launch Adobe Lightroom, apply the desired edits, and upload the edited photos to Google Photos. (run $ python app.py in Send_image_google_photo folder)

Please note that detailed instructions for configuring the script and obtaining API credentials can be found in the project's documentation.

**Note:** Before running the script, ensure that you have a working internet connection and the required access permissions for accessing Adobe Lightroom and Google Photos API.

For any issues or further assistance, please refer to the project's documentation or contact the project maintainer.

## Conclusion

The "Camera Workflow with Adobe Lightroom" script simplifies the process of editing and uploading photos by leveraging Adobe Lightroom and Google Photos API. By automating these tasks, it allows users to save time and effort while ensuring a streamlined workflow for managing their photography projects.
