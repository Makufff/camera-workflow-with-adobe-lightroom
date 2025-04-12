-- Original Scale Size
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
local myLogger = LrLogger('ExportMenuItemFullsizeLogger')
myLogger:enable('print')

-- Process pictures and save them as JPEG
local function processPhotos(photos, outputFolder)
	myLogger:info("Processing photos at original size to output folder: " .. outputFolder)
	
	-- Track rendered photos with their expected filenames
	local renderedPhotos = {}
	
	-- Check if outputFolder is relative path or doesn't have drive letter (Windows)
	if not string.match(outputFolder, "^%a:\\") and not string.match(outputFolder, "^/") then
		-- Add current directory path
		local currentFolder = LrPathUtils.getStandardFilePath("home")
		outputFolder = LrPathUtils.child(currentFolder, outputFolder)
		myLogger:info("Converting to absolute path: " .. outputFolder)
	end
	
	LrFunctionContext.callWithContext("export", function(exportContext)
		local progressScope = LrDialogs.showModalProgressDialog({
			title = "Auto applying presets",
			caption = "",
			cannotCancel = false,
			functionContext = exportContext
		})

		-- Make sure output folder exists
		LrTasks.execute("cmd.exe /c if not exist \"" .. outputFolder .. "\" mkdir \"" .. outputFolder .. "\"")
		
		myLogger:info("Created export session with " .. #photos .. " photos (original size)")
		myLogger:info("Exporting to: " .. outputFolder)
		
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
				LR_jpeg_quality = 1,
				LR_minimizeEmbeddedMetadata = true,
				LR_outputSharpeningOn = false,
				LR_reimportExportedPhoto = false,
				LR_renamingTokensOn = true,
				LR_size_doConstrain = false, -- No size constraint for original size
				LR_size_doNotEnlarge = true,
				LR_size_resolution = 72,
				LR_size_units = "pixels",
				LR_tokens = "{{image_name}}",
				LR_useWatermark = false,
			}
		})

		local numPhotos = exportSession:countRenditions()
		myLogger:info("Number of renditions (original size): " .. numPhotos)

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
			myLogger:info("Rendering original size photo: " .. filename)
			
			local success, err = rendition:waitForRender()
			
			if success then
				myLogger:info("Successfully rendered original size: " .. filename)
				
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
					local estimatedPath = LrPathUtils.child(outputFolder, filename .. ".jpg")
					myLogger:info("Estimated file location: " .. estimatedPath)
					table.insert(renderedPhotos, {
						filename = filename,
						path = estimatedPath
					})
				end
			else
				myLogger:error("Failed to render original size: " .. filename .. " - " .. tostring(err))
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
		local resultMessage = "Export completed (original size): " .. exportedCount .. " of " .. #renderedPhotos .. " to " .. outputFolder
		LrDialogs.showBezel(resultMessage)
		myLogger:info(resultMessage)
		
		-- If not all photos were exported successfully, show a warning
		if exportedCount < #renderedPhotos then
			LrDialogs.showError("Warning: Only " .. exportedCount .. " of " .. #renderedPhotos .. " photos were exported successfully. Check log for details.")
		end
	end)
end

-- Import pictures from folder where the rating is not 2 stars 
local function importFolder(LrCatalog, folder, outputFolder, silent)
	silent = silent or false -- Default to false if not provided
	myLogger:info("Importing from folder: " .. folder:getName() .. " to output: " .. outputFolder .. " (original size)")
	
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
	
	local success = false
	
	LrTasks.startAsyncTask(function()
		local photos = folder:getPhotos()
		myLogger:info("Found " .. #photos .. " photos in folder: " .. folder:getName())
		
		local export = {}

		for i, photo in pairs(photos) do
			-- Process photos that DON'T have a rating of 2 stars (original condition)
			if (photo:getRawMetadata("rating") ~= 2) then
				myLogger:info("Processing photo " .. i .. ": " .. photo:getFormattedMetadata("fileName") .. " (original size)")
				
				LrCatalog:withWriteAccessDo("Apply Preset", function(context)
					myLogger:info("Applying presets to photo: " .. photo:getFormattedMetadata("fileName"))
					
					for _, preset in pairs(presets) do
						myLogger:info("Applying preset: " .. preset:getName())
						photo:applyDevelopPreset(preset)
					end
					
					photo:setRawMetadata("rating", 2)
					table.insert(export, photo)
					myLogger:info("Added photo to export list: " .. photo:getFormattedMetadata("fileName"))
				end)
			else
				myLogger:info("Skipping photo with rating 2: " .. photo:getFormattedMetadata("fileName"))
			end
		end

		myLogger:info("Total photos for export (original size): " .. #export)
		
		if #export > 0 then
			processPhotos(export, outputFolder)
			success = true
		else
			myLogger:warn("No photos to export (original size)")
			if not silent then
				LrDialogs.showError("No photos to export (original size)")
			end
		end
	end)
	
	return success
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
								myLogger:info("Process once button clicked for folder: " .. folderField.value .. " (original size)")
								
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
								LrDialogs.message("Processing folder (original size): " .. folderField.value .. 
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
								props.myObservedString = "Watcher active"
								watch()
							else
								LrDialogs.message("Please select an input folder")
							end
						end
					},
					f:push_button {
						title = "Stop watching",

						action = function()
							watcherRunning = false
							props.myObservedString = "Watcher stopped"
						end
					}
				},
				f:row {
					f:push_button {
						title = "Close",
						action = function() LrDialogs.stopModalWithResult(LrView.osFactory(), "cancel") end
					}
				}
			}

			LrDialogs.presentModalDialog({
				title = "Auto Import - Export",
				contents = c,
				resizable = true,
				actionVerb = "Go",
			})
		end)
	end)
end

customPicker()
