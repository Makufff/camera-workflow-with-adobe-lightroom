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
	local exportSettings = {
		LR_export_destinationType = "specificFolder",
		LR_export_destinationPathPrefix = outputFolder,
		LR_format = "JPEG",
	}
	
	myLogger:info("Processing " .. #photos .. " photos to folder: " .. outputFolder)
	
	-- Create output directory if it doesn't exist
	if not LrFileUtils.exists(outputFolder) then
		myLogger:info("Creating output directory: " .. outputFolder)
		LrFileUtils.createDirectory(outputFolder)
	end
	
	local renderedPhotos = {}
	
	-- Export photos
	LrExportSession.exportPhotos({
		{ exportSettings = exportSettings, photos = photos, },
		onPhotoDataRendered = function(exportContext, photo)
			local filename = photo:getFormattedMetadata("fileName")
			myLogger:info("Photo rendered: " .. filename)
			table.insert(renderedPhotos, {
				photo = photo,
				filename = filename
			})
		end,
		onPhotosExported = function(exportContext)
			myLogger:info("Export completed")
			
			-- Check if files were actually created
			myLogger:info("Verifying " .. #renderedPhotos .. " exported files")
			local successCount = 0
			
			for _, photoInfo in ipairs(renderedPhotos) do
				local photo = photoInfo.photo
				local filename = photoInfo.filename
				local fileBasename = string.gsub(filename, "%.%w+$", "")
				local expectedPath = LrFileUtils.child(outputFolder, fileBasename .. ".jpg")
				
				myLogger:info("Checking file: " .. expectedPath)
				
				if LrFileUtils.exists(expectedPath) then
					myLogger:info("SUCCESS: File exists: " .. expectedPath)
					successCount = successCount + 1
				else
					myLogger:error("FAILED: File does not exist: " .. expectedPath)
				end
			end
			
			LrDialogs.showBezel("Export completed. Successfully exported " .. successCount .. " of " .. #renderedPhotos .. " photos.")
			myLogger:info("Export summary: " .. successCount .. " of " .. #renderedPhotos .. " photos were successfully exported")
		end,
	})
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
	local taskResults = {}
	
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
			
			-- Process photos
			processPhotos(export, outputFolder)
			
			taskResults.success = true
			taskResults.count = #export
		else
			myLogger:warn("No photos to export")
			if not silent then
				LrDialogs.showError("No photos to export")
			end
			taskResults.success = false
			taskResults.count = 0
		end
	end)
	
	-- Wait a bit for task to complete or at least start processing
	LrTasks.sleep(1)
	
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
				items = folderCombo
			}

			local watcherRunning = false

			-- Watcher, executes function and then sleeps using PowerShell
			local function watch()
				-- Keep track of empty exports
				local emptyExportCount = 0
				local lastBezelTime = 0
				
				LrTasks.startAsyncTask(function()
					while watcherRunning do
						-- Process folder in silent mode to prevent too many error dialogs
						local result = importFolder(LrCatalog, catalogFolders[folderIndex[folderField.value]], outputFolderField.value, true)
						
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
								
								-- Get photo count for debugging
								local folder = catalogFolders[folderIndex[folderField.value]]
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
								
								importFolder(LrCatalog, catalogFolders[folderIndex[folderField.value]], outputFolderField.value, false)
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
