-- SUBTITLE
return {
	
	LrSdkVersion = 3.0,
	LrSdkMinimumVersion = 1.3, -- minimum SDK version required by this plug-in

	LrToolkitIdentifier = 'nl.olafhaalstra.lightroom.autoimportexport',

	LrPluginName = LOC "$$$/Makufff/PluginName=Auto IMPORT - EXPORT :3 ",

	LrExportMenuItems = {{
		title = "FIX SIZE 2000px",
		file = "ExportMenuItem.lua",		
	},{
		title = "Original Scales",
		file = "ExportMenuItemFullsize.lua",		
	},},
	VERSION = { major=1, minor=0, revision=0, build="20220724", },

}


	
