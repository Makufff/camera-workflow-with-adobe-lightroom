-- FIXSIZE 2000px 2000px
-- Access the Lightroom SDK namespaces.
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrView = import 'LrView'
local LrPathUtils = import 'LrPathUtils'
local LrLogger = import 'LrLogger'
local LrFileUtils = import 'LrFileUtils'

local LrApplication = import 'LrApplication'
local LrExportSession = import 'LrExportSession'
local LrTasks = import 'LrTasks'

-- Set up logger
local myLogger = LrLogger('ExportMenuItemLogger')
myLogger:enable('print')

-- Process photos
local function processPhotos(photos, outputFolder)
	myLogger:info("Processing photos (resize to 2000px) to output folder: " .. outputFolder)
	
	-- Track rendered photos with their expected filenames
	local renderedPhotos = {}
	
	-- Check if outputFolder is relative path or doesn't have drive letter (Windows)
	if not string.match(outputFolder, "^%a:\\") and not string.match(outputFolder, "^/") then
		-- Add current directory path
		local currentFolder = LrPathUtils.getStandardFilePath("home")
		outputFolder = LrPathUtils.child(currentFolder, outputFolder)
		myLogger:info("Converting to absolute path: " .. outputFolder)
	end
	
	myLogger:info("Using full export settings for rendition, 2000px mode")
	
	-- Make sure output folder exists
	if not LrFileUtils.exists(outputFolder) then
		myLogger:info("Creating output directory: " .. outputFolder)
		LrFileUtils.createDirectory(outputFolder)
	end
	
	LrFunctionContext.callWithContext("export", function(exportContext)
		local progressScope = LrDialogs.showModalProgressDialog({
			title = "Auto applying presets",
			caption = "Preparing export...",
			cannotCancel = false,
			functionContext = exportContext
		})

		myLogger:info("Created export session with " .. #photos .. " photos")
		myLogger:info("Exporting to: " .. outputFolder)
		
		-- Create export session with full settings
		local exportSession = LrExportSession({
			photosToExport = photos,
			exportSettings = {
				LR_collisionHandling = "rename",
				LR_export_bitDepth = "8",
				LR_export_colorSpace = "sRGB",
				LR_export_destinationPathPrefix = outputFolder,
				LR_export_destinationType = "specificFolder",
				LR_export_useSubfolder = false,
				LR_format = "JPEG",
				LR_jpeg_quality = 1, -- Highest quality
				LR_minimizeEmbeddedMetadata = true,
				LR_outputSharpeningOn = false,
				LR_reimportExportedPhoto = false,
				LR_renamingTokensOn = true,
				LR_size_doConstrain = true,
				LR_size_doNotEnlarge = true,
				LR_size_maxHeight = 2000,
				LR_size_maxWidth = 2000,
				LR_size_resolution = 72,
				LR_size_units = "pixels",
				LR_tokens = "{{image_name}}",
				LR_useWatermark = false,
			}
		})

		local numPhotos = exportSession:countRenditions()
		myLogger:info("Number of renditions: " .. numPhotos)

		local renditionParams = {
			progressScope = progressScope,
			renderProgressPortion = 1,
			stopIfCanceled = true,
		}

		for i, rendition in exportSession:renditions(renditionParams) do
			-- Stop processing if the cancel button has been pressed
			if progressScope:isCanceled() then
				break
			end

			-- Common caption for progress bar
			local progressCaption = rendition.photo:getFormattedMetadata("fileName") .. " (" .. i .. "/" .. numPhotos .. ")"

			progressScope:setPortionComplete(i - 1, numPhotos)
			progressScope:setCaption("Processing " .. progressCaption)
			
			local filename = rendition.photo:getFormattedMetadata("fileName")
			myLogger:info("Rendering photo: " .. filename)
			
			local success, err = rendition:waitForRender()
			
			if success then
				myLogger:info("Successfully rendered: " .. filename)
				
				-- Get the exported file path - handle potential nil return safely
				local status, exportedFilePath = pcall(function() return rendition:getPath() end)
				if status and exportedFilePath then
					myLogger:info("File saved to: " .. exportedFilePath)
					table.insert(renderedPhotos, {
						filename = filename,
						path = exportedFilePath
					})
				else
					myLogger:info("File saved successfully, but path information not available")
					-- Alternative approach to get path
					local fileBasename = string.gsub(filename, "%.%w+$", "")
					local estimatedPath = LrPathUtils.child(outputFolder, fileBasename .. ".jpg")
					myLogger:info("Estimated file location: " .. estimatedPath)
					table.insert(renderedPhotos, {
						filename = filename,
						path = estimatedPath
					})
				end
			else
				myLogger:error("Failed to render: " .. filename .. " - " .. tostring(err))
			end
		end
		
		-- Verify exported files exist
		progressScope:setCaption("Verifying exported files...")
		local exportedCount = 0
		
		for _, photo in ipairs(renderedPhotos) do
			local path = photo.path
			-- Add .jpg extension if needed
			if not string.match(path:lower(), "%.jpe?g$") then
				path = path .. ".jpg"
			end
			
			-- Check if file exists
			local exists = LrFileUtils.exists(path)
			if exists then
				exportedCount = exportedCount + 1
				myLogger:info("Verified file exists: " .. path)
			else
				myLogger:error("MISSING FILE: " .. path)
			end
		end
		
		-- Show message with count of successful exports
		local resultMessage = "Export completed: " .. exportedCount .. " of " .. #renderedPhotos .. " to " .. outputFolder
		LrDialogs.showBezel(resultMessage)
		myLogger:info(resultMessage)
		
		-- If not all photos were exported successfully, show a warning
		if exportedCount < #renderedPhotos then
			LrDialogs.showError("Warning: Only " .. exportedCount .. " of " .. #renderedPhotos .. " photos were exported successfully. Check log for details.")
		end
	end)
	
	return #renderedPhotos > 0
end

-- Import pictures from folder where the rating is not 2 stars 
local function importFolder(LrCatalog, folder, outputFolder, silent)
	silent = silent or false -- Default to false if not provided
	myLogger:info("Importing from folder: " .. folder:getName() .. " to output: " .. outputFolder)
	
	local presetFolders = LrApplication.developPresetFolders()
	if #presetFolders == 0 then
		myLogger:error("No preset folders found")
		if not silent then
			LrDialogs.showError("No preset folders found")
		end
		return false
	end
	
	local presetFolder = presetFolders[1]
	local presets = presetFolder:getDevelopPresets()
	if #presets == 0 then
		myLogger:error("No presets found in folder: " .. presetFolder:getName())
		if not silent then
			LrDialogs.showError("No presets found in folder: " .. presetFolder:getName())
		end
		return false
	end
	
	myLogger:info("Found " .. #presets .. " presets in folder: " .. presetFolder:getName())
	myLogger:info("Presets: ")
	for i, preset in pairs(presets) do
		myLogger:info("  " .. i .. ": " .. preset:getName())
	end
	
	-- Use a synchronized call to wait for task completion
	local taskResults = {
		success = false,
		count = 0,
		processComplete = false
	}
	
	-- Create a function context to run our process
	LrFunctionContext.callWithContext("importFolder", function(context)
		LrDialogs.showBezel("Processing photos from " .. folder:getName() .. "...")
		
		-- Run in a synchronous task so we can get the results
		LrTasks.startAsyncTask(function()
			local photos = folder:getPhotos()
			myLogger:info("Found " .. #photos .. " photos in folder: " .. folder:getName())
			
			local export = {}

			for i, photo in pairs(photos) do
				-- Process photos that DON'T have a rating of 2 stars (original condition)
				if (photo:getRawMetadata("rating") ~= 2) then
					local filename = photo:getFormattedMetadata("fileName")
					myLogger:info("Processing photo " .. i .. ": " .. filename)
					
					LrCatalog:withWriteAccessDo("Apply Preset", function(context)
						myLogger:info("Applying presets to photo: " .. filename)
						
						for _, preset in pairs(presets) do
							myLogger:info("Applying preset: " .. preset:getName() .. " to " .. filename)
							photo:applyDevelopPreset(preset)
						end
						
						photo:setRawMetadata("rating", 2)
						table.insert(export, photo)
						myLogger:info("Added photo to export list: " .. filename)
					end)
				else
					myLogger:info("Skipping photo with rating 2: " .. photo:getFormattedMetadata("fileName"))
				end
			end

			myLogger:info("Total photos for export: " .. #export)
			
			if #export > 0 then
				-- Be explicit about what we're about to do
				myLogger:info("About to call processPhotos with " .. #export .. " photos")
				LrDialogs.showBezel("Processing " .. #export .. " photos...")
				
				-- Process photos - wait for result
				local exportSuccess = processPhotos(export, outputFolder)
				myLogger:info("processPhotos returned: " .. tostring(exportSuccess))
				
				taskResults.success = exportSuccess
				taskResults.count = #export
			else
				myLogger:warn("No photos to export")
				if not silent then
					LrDialogs.showError("No photos to export")
				end
				taskResults.success = false
				taskResults.count = 0
			end
			
			taskResults.processComplete = true
		end)
		
		-- Wait for the task to complete
		local timeout = 120 -- Maximum wait time in seconds
		local start = os.time()
		local waited = 0
		
		while (not taskResults.processComplete) and (waited < timeout) do
			LrTasks.sleep(1)
			waited = os.time() - start
			if waited > 5 and waited % 10 == 0 then
				myLogger:info("Still waiting for process to complete... " .. waited .. " seconds")
			end
		end
		
		if not taskResults.processComplete then
			myLogger:error("Process timed out after " .. timeout .. " seconds")
			if not silent then
				LrDialogs.showError("Process timed out")
			end
			taskResults.success = false
		end
		
		myLogger:info("importFolder completed with success=" .. tostring(taskResults.success) .. 
			", count=" .. taskResults.count .. ", complete=" .. tostring(taskResults.processComplete))
	end)
	
	return taskResults.success
end

-- GUI specification
local function customPicker()
	LrFunctionContext.callWithContext("showCustomDialogWithObserver", function(context)

		local props = LrBinding.makePropertyTable(context)
		local f = LrView.osFactory()

		-- Use current OUTPUT folder instead of hardcoded path
		local outputFolderField = f:edit_field {
			immediate = true,
			value = "D:\\" .. "work\\write_code\\camera-workflow-with-adobe-lightroom\\OUTPUT"
		}

		local staticTextValue = f:static_text {
			title = "Not started",
		}

		local function myCalledFunction()
			staticTextValue.title = props.myObservedString
		end

		LrTasks.startAsyncTask(function()

			local LrCatalog = LrApplication.activeCatalog()
			local catalogFolders = LrCatalog:getFolders()
			local folderCombo = {}
			local folderIndex = {}
			for i, folder in pairs(catalogFolders) do
				folderCombo[i] = folder:getName()
				folderIndex[folder:getName()] = i
			end

			local folderField = f:combo_box {
				items = folderCombo,
				value = folderCombo[1],  -- Select the first folder by default
				tooltip = "Select the folder to process"
			}

			local watcherRunning = false

			-- Watcher, executes function and then sleeps using PowerShell
			local function watch()
				-- Keep track of empty exports
				local emptyExportCount = 0
				local lastBezelTime = 0
				
				LrTasks.startAsyncTask(function()
					while watcherRunning do
						myLogger:info("Watcher checking folder: " .. folderField.value)
						
						-- Safety check
						if folderField.value == nil or folderField.value == "" then
							myLogger:error("No folder selected for watcher")
							LrDialogs.showError("No folder selected. Watcher stopped.")
							watcherRunning = false
							props.myObservedString = "Stopped - No folder selected"
							break
						end
						
						if folderIndex[folderField.value] == nil then
							myLogger:error("ERROR: folderIndex[" .. folderField.value .. "] is nil!")
							LrDialogs.showError("Cannot find the selected folder index. Watcher stopped.")
							watcherRunning = false
							props.myObservedString = "Stopped - Invalid folder"
							break
						end
						
						local folderIndexValue = folderIndex[folderField.value]
						if catalogFolders[folderIndexValue] == nil then
							myLogger:error("ERROR: catalogFolders[" .. folderIndexValue .. "] is nil!")
							LrDialogs.showError("Cannot find the selected folder. Watcher stopped.")
							watcherRunning = false
							props.myObservedString = "Stopped - Folder not found"
							break
						end
						
						local folder = catalogFolders[folderIndex[folderField.value]]
						myLogger:info("Found folder for watcher: " .. folder:getName())
						
						-- Process folder in silent mode to prevent too many error dialogs
						local result = importFolder(LrCatalog, folder, outputFolderField.value, true)
						
						-- Calculate time since last bezel message
						local currentTime = os.time()
						local timeSinceLastBezel = currentTime - lastBezelTime
						
						if result then
							-- Reset empty count when successful
							emptyExportCount = 0
							-- No need to update lastBezelTime as processPhotos already shows a bezel
						else
							-- Increment empty count
							emptyExportCount = emptyExportCount + 1
							
							-- Show status updates less frequently to avoid notification flood
							if emptyExportCount == 5 and timeSinceLastBezel > 60 then
								-- After 5 consecutive empty checks (~2.5 minutes), show a status message
								LrDialogs.showBezel("No new photos to process")
								lastBezelTime = currentTime
								myLogger:info("No photos to export for several checks")
							elseif emptyExportCount > 5 and emptyExportCount % 20 == 0 and timeSinceLastBezel > 300 then
								-- Show a status update every 20 checks (~10 minutes) after the 5th empty check
								LrDialogs.showBezel("Still watching for new photos...")
								lastBezelTime = currentTime
								myLogger:info("Still watching for new photos, no content yet")
							end
						end
						
						if LrTasks.canYield() then
							LrTasks.yield()
						end
						
						-- Wait 30 seconds before next check
						myLogger:info("Waiting 30 seconds before next check...")
						LrTasks.execute("powershell Start-Sleep -Seconds 30")
					end
				end)
			end

			props:addObserver("myObservedString", myCalledFunction)

			local c = f:column {
				spacing = f:dialog_spacing(),
				f:row {
					fill_horizontal = 1,
					f:static_text {
						alignment = "right",
						width = LrView.share "label_width",
						title = "Watcher running: "
					},
					staticTextValue,
				},
				f:row {
					f:static_text {
						alignment = "right",
						width = LrView.share "label_width",
						title = "Select folder: "
					},
					folderField
				},
				f:row {
					f:static_text {
						alignment = "right",
						width = LrView.share "label_width",
						title = "Output folder: "
					},
					outputFolderField
				},
				f:row {
					f:push_button {
						title = "Process once",

						action = function()
							if folderField.value ~= "" then
								props.myObservedString = "Processed once"
								myLogger:info("Process once button clicked for folder: " .. folderField.value)
								
								-- Debug logging
								myLogger:info("Folder value: " .. tostring(folderField.value))
								
								-- Verify folder index exists
								if folderIndex[folderField.value] == nil then
									myLogger:error("ERROR: folderIndex[" .. folderField.value .. "] is nil!")
									LrDialogs.showError("Cannot find the selected folder index. Please try selecting the folder again.")
									return
								end
								
								myLogger:info("Folder index: " .. tostring(folderIndex[folderField.value]))
								
								-- Verify folder exists at the index
								local folderIndexValue = folderIndex[folderField.value]
								if catalogFolders[folderIndexValue] == nil then
									myLogger:error("ERROR: catalogFolders[" .. folderIndexValue .. "] is nil!")
									LrDialogs.showError("Cannot find the selected folder. Please try selecting the folder again.")
									return
								end
								
								-- Get the folder safely
								local folder = catalogFolders[folderIndex[folderField.value]]
								myLogger:info("Found folder: " .. folder:getName())
								
								-- Get photo count for debugging
								local photos = folder:getPhotos()
								local nonRated2Count = 0
								
								for _, photo in pairs(photos) do
									if (photo:getRawMetadata("rating") ~= 2) then
										nonRated2Count = nonRated2Count + 1
									end
								end
								
								-- Display the selected folder and output folder for debugging with photo count
								LrDialogs.message("Processing folder: " .. folderField.value .. 
									"\nOutput to: " .. outputFolderField.value .. 
									"\nTotal photos: " .. #photos .. 
									"\nPhotos to process (not rated 2): " .. nonRated2Count)
								
								importFolder(LrCatalog, folder, outputFolderField.value, false)
							else
								LrDialogs.message("Please select an input folder")
							end
						end
					},
					f:push_button {
						title = "Watch every 30s",

						action = function()
							watcherRunning = true
							if folderField.value ~= "" then
								props.myObservedString = "Running"
								watch()
							else
								LrDialogs.message("Please select an input folder")
							end
						end
					},
					f:push_button {
						title = "Pause watcher",

						action = function()
							watcherRunning = false
							props.myObservedString = "Stopped after running"
						end
					}
				},
			}

			LrDialogs.presentModalDialog {
				title = "Auto Export resize2000px Watcher",
				contents = c,
				-- Preferrably cancel should stop the script 
				-- OK can be changed to run in background
				-- actionBinding = {
				-- 	enabled = {
				-- 		bind_to_object = props,
				-- 		key = 'actionDisabled'
				-- 	},
				-- }			   
			}

		end)

	end)
end

customPicker()
