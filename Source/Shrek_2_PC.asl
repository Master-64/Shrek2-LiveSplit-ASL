// *****************************************************
// *  Shrek 2 Autosplitter & Load Remover by Master_64 *
// *		  Copyrighted (c) Master_64, 2023		   *
// *   May be modified but not without proper credit!  *
// *****************************************************
// 
// Technical Help:
// - HuniePop (Memory pointer for map name)
// - Seifer (Code, Testing & Feedback)
// - Nikvel (Memory pointer for BossFGM's health)
// 
// General Help:
// - Janek (Testing & Feedback)
// - mrjor (Testing & Feedback)
// - Im_a_mirror (Testing)
// - Metallicafan212 (Technical Feedback)


state("game") // Grabs the process "game.exe" and tracks a few pointers for values
{
	float TimeSeconds : "Engine.dll", 0x4DFFF8, 0x68, 0x14C, 0x9C, 0x480;			// [Found by: Master_64] Returns LevelInfo.TimeSeconds
	float TimeAfterLoading : "Engine.dll", 0x4DFFF8, 0x30, 0x34, 0xA40;				// [Found by: Master_64] Returns SHHeroController.TimeAfterLoading (value is dynamically assigned, so the value can appear incorrect for a frame or so)
	uint Pauser : "Engine.dll", 0x4DFFF8, 0x68, 0x14C, 0x9C, 0x4F8;					// [Found by: Master_64] Returns a value not equal to 0 if LevelInfo.Pauser exists
	uint CurrentMapAddress : "Engine.dll", 0x4DFFF8, 0x68, 0x9C, 0xA8, 0x4E0;		// [Found by: HuniePop] Returns the current map address (requires additional work to get the value of the current map)
	float TimeDilation : "Engine.dll", 0x4DFFF8, 0x68, 0x14C, 0x9C, 0x47C;			// [Found by: Master_64] Returns LevelInfo.TimeDilation
	float BossFGM_Health : "Engine.dll", 0x4DFFF8, 0x68, 0xA0, 0x30, 0xE5C, 0x4E0;	// [Found by: Nikvel & Master_64] Returns 11_FGM_Battle.BossFGM.Health
}

startup // All code that is ran before running all logic
{
	// Adds settings
	settings.Add("Reset on Game Close", true, "Reset on Game Close");
	settings.SetToolTip("Reset on Game Close", "If true, the autosplitter will reset the run once the game closes, which is safe to automatically do,\n" + "as the autosplitter shouldn't be trying to run logic if the game's process isn't running.");
	settings.Add("Split On FGM Kill", true, "Split On FGM Kill");
	settings.SetToolTip("Split On FGM Kill", "If true, if playing the level 11_FGM_Battle.unr and FGM is killed, then a split will occur");
	settings.Add("Auto-Delete Save Files On Reset", false, "[Caution] Auto-Delete Save Files On Reset");
	settings.SetToolTip("Auto-Delete Save Files On Reset", "If true, when a run is reset, all 6 save files are deleted, so that a new run can be instantly started.\n" + "While this is enabled, do not try to delete any of the main 6 save files in-game; doing so will softlock your game");
	settings.Add("Split On Played Maps", false, "[Caution] Split On Played Maps");
	settings.SetToolTip("Split On Played Maps", "If true, if a map is loaded that has already been loaded before, a split will occur.");
	settings.Add("Any Map Splits", false, "[Caution] Any Map Splits");
	settings.SetToolTip("Any Map Splits", "If true, splits upon changing to any map. Don't use this unless you know what you're doing.");
	settings.Add("Account For Pausing", false, "[Not officially allowed] Account For Pausing");
	settings.SetToolTip("Account For Pausing", "If true, game time pauses upon pausing.");
	
	refreshRate = 60; // Makes the refresh rate of the script high enough to be 100% consistent on 60 FPS, and mostly consistent on uncapped runs
	
	if(timer.CurrentTimingMethod == TimingMethod.RealTime) // Displays a popup informing the user that they need to be aware about the LRT timing method
	{		
		var TimingMessage = MessageBox.Show(
			"This game uses a load-removed time (LRT) as its main timing method.\n"+
			"LiveSplit is currently set to show real time (RTA).\n"+
			"Would you like to set the timing method to Game Time?",
			"LiveSplit | Shrek 2 (PC)",
			MessageBoxButtons.YesNo,MessageBoxIcon.Question
		);
		
		if(TimingMessage == DialogResult.Yes)
		{
			timer.CurrentTimingMethod = TimingMethod.GameTime;
		}
	}
	
	vars.ExcludedSplitMaps = new List<string>() // All maps that should not be split on
	{
		"BOOK_FRONTEND",	// Don't split when going back to the main menu map
		"BOOK_STORY_1",		// Don't split here, since we have custom logic handling when the run should begin
		"BOOK_STORY_4",		// Don't split here, since the run has finished
		"BOOK_STORYBOOK",	// This map isn't actually used in the game, but we shouldn't split on this map as the map has custom logic that makes it not suitable for casual play
		"CREDITS",			// Don't split here, since the run has finished
		"ENTRY",			// Don't split when the game first opens
		"1_SHREKS_SWAMP",	// Don't split here, since we split when loading into the first storybook cutscene map
		"4_FGM_PIB",		// Don't split here, since we split when loading into the FGM's Factory cutscene map
		"3_THE_HUNT_PART1",	// Don't split here, since we split when loading into the second storybook cutscene map
		"7_PRISON_DONKEY"	// Don't split here, since we split when loading into the third storybook cutscene map
	};
	
	// Variable declarations
	vars.PlayedMaps = new List<string>();	// All maps that have been played on so far
	vars.ShouldSplit = false;				// If true, the split function/event should be fired to a single time to check if a split is now valid
	vars.CurrentMap = "";					// Contains the value of the current map the game is running
	vars.LastMap = "";						// Contains the last non-NULL value for <vars.CurrentMap>. Equals nothing while <vars.CurrentMap> is not NULL
	vars.OldMap = "";						// Contains the value of <vars.CurrentMap>, but 1 tick behind
	vars.TotalGameTime = 0.0;				// The amount of time that has elapsed in the current run, relative to the game time
	vars.LoadTime = 0.0;					// If this doesn't equal 0.0, how much time should be removed from <vars.TotalGameTime>
	vars.TimerModel = new TimerModel { CurrentState = timer };	// Used for if the game closes and we need to automatically reset the timer
	vars.RealTime = TimeSpan.Zero;			// Used for calculating the Real Time delta, which is used for when the game is paused so that the timer doesn't actually pause
	vars.RealTimeDelta = TimeSpan.Zero;		// Same as above variable
	vars.S2DocumentsFolderPath = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments) + "\\Shrek 2\\Save\\Save*.usa";	// Gets the folder path to the user's Shrek 2 Documents folder. This is needed for a particular option that, when enabled, deletes the player's main save files
}

init // Initializes the script, and assigns a version number to it
{
	version = "ASL v4.0.1 [Release]";
}

update // Runs everytime the script is ticked
{
	if(current.CurrentMapAddress != 0) // NULL check
	{
		try // Although a try-catch block is not preferred, due to how the DeepPointer() function works, it's necessary in order to prevent the entire timer from breaking when it very rarely returns NULL
		{
			vars.CurrentMap = new DeepPointer(new IntPtr(current.CurrentMapAddress)).DerefString(game, 1024).ToUpper().Replace(".UNR", "");
			
			if(vars.CurrentMap.Contains("?")) // The map pointer can rarely return weird values containing question marks, so if that happens, we need to make sure that variable <vars.CurrentMap> doesn't update
			{
				vars.CurrentMap = vars.LastMap;
			}
		}
		catch
		{
			print("Shrek 2 (PC) ASL: <vars.CurrentMap> failed to return a value, when it was expected to return one");
		}
		
		if(vars.LastMap != "" && vars.CurrentMap != vars.OldMap) // (Hacky code because ASL Part 1) Attempts to split if the map pointer just started returning a value after being NULL. This check is also done in a way where loading a save doesn't split if it's on the same map we were previously on
		{
			print("Split Logs");
			print("CurrentMap:" + vars.CurrentMap.ToString());
			print("OldMap:" + vars.OldMap.ToString());
			print("LastMap:" + vars.LastMap.ToString());
			
			vars.PlayedMaps.Add(vars.LastMap);
			
			vars.LastMap = "";
			
			vars.ShouldSplit = true;
		}
		
		if(vars.CurrentMap != vars.OldMap) // Only updates <vars.OldMap> if the map has changed. This is a necessary check, because otherwise there will be instances of a split not occuring when it should (the map pointer can point to the previous map for 1 frame under rare circumstances)
		{
			vars.OldMap = (string)vars.CurrentMap;
			
			print("Updating <vars.OldMap>");
			print("Updated OldMap:" + vars.OldMap.ToString());
		}
	}
	else
	{
		vars.LastMap = (string)vars.CurrentMap;
	}
	
	if(current.TimeDilation != 0 && old.TimeDilation != 0) // NULL check
	{
		if(current.TimeDilation != 1.0) // If LevelInfo.TimeDilation isn't equal to 1.0, the game timer will be misrepresented
		{
			vars.TimerModel.Reset();
		}
	}
	
	// Gets the RTA delta, which is used for when the game is paused so that the game time can continue. How this code works, I have no idea, but it does work LOL
	var PrevRealTime = vars.RealTime;
	vars.RealTime = timer.CurrentTime.RealTime;
	vars.RealTimeDelta = vars.RealTime - PrevRealTime;
}

isLoading // I'm telling LiveSplit that the game is always loading, so that it fully relies on the gameTime() function below, which is handled via the LevelInfo.TimeSeconds value
{
	return true;
}

start // Returns true if the autosplitter should begin
{
	return vars.CurrentMap == "BOOK_STORY_1";
}

reset // Returns true if the game should be reset
{
	return vars.CurrentMap == "BOOK_FRONTEND";
}

onReset // Fires when a reset happens
{
	vars.TotalGameTime = 0.0;
	vars.PlayedMaps = new List<string>();
	
	if(settings["Auto-Delete Save Files On Reset"])
	{
		for(int i = 0; i < 6; i++)
		{
			if(File.Exists(@vars.S2DocumentsFolderPath.Replace("*", i.ToString())))
			{
				File.Delete(@vars.S2DocumentsFolderPath.Replace("*", i.ToString()));
			}
		}
	}
}

split // Waits until a map has changed, then runs logic to see if the map is different or not. If the map is different, and it's not an excluded splitting map, then we return true (to split)
{
	if(vars.ShouldSplit) // (Hacky code because ASL Part 2) Once <vars.ShouldSplit> equals true, we do a single check to see if a split is actually valid or not
	{
		vars.ShouldSplit = false;
		
		if(!settings["Any Map Splits"]) // Doesn't split if the map is manually excluded from the autosplitter
		{
			foreach(string item in vars.ExcludedSplitMaps)
			{
				if(item.Contains(vars.CurrentMap))
				{
					print("Map is excluded");
					
					return false;
				}
			}
		}
		
		if(!settings["Split On Played Maps"]) // Doesn't split if the map has already been played
		{
			foreach(string item in vars.PlayedMaps)
			{
				if(item.Contains(vars.CurrentMap))
				{
					print("Map has been played before");
					
					return false;
				}
			}
		}
		
		return true;
	}
	else if(settings["Split On FGM Kill"] && vars.CurrentMap == "11_FGM_BATTLE") // Are we planning on splitting when FGM is killed, and is the game on level 11_FGM_Battle.unr?
	{
		if(current.BossFGM_Health == 0.0 && old.BossFGM_Health > 0.0) // (NULL check isn't possible here, so exceptions may be raised) Did FGM just die? If so, split
		{
			return true;
		}
	}
	
	return false;
}

gameTime // Takes the value of LevelInfo.TimeSeconds from the game, and makes that the game time (relatively)
{
	if(current.TimeSeconds != 0 && old.TimeSeconds != 0) // NULL check
	{
		if(current.TimeAfterLoading != 0 && old.TimeAfterLoading != 0) // NULL check
		{
			if(current.TimeAfterLoading != old.TimeAfterLoading) // Calculates whether a load has happened or not. If a load has happened, then we save the load time for future use
			{
				vars.LoadTime = current.TimeAfterLoading;
			}
		}
		
		if(current.TimeSeconds >= 0.0) // Makes sure that the level time is actually changing
		{
			if(current.TimeSeconds > old.TimeSeconds) // Is the game currently playing? If it is, then we need to take the in-game timer and get the relative time that has passed in a frame
			{
				vars.TotalGameTime += current.TimeSeconds - old.TimeSeconds;
			}
			
			if(vars.LoadTime != 0.0) // If a load time has been updated, then we need to take that load time, and remove it from the current timer
			{
				if(vars.TotalGameTime - vars.LoadTime >= 0.0 && vars.CurrentMap != "BOOK_STORY_1") // Makes sure that the change we're about to make to the total game time is not going to result in the timer going negative (clamping). Also makes sure that a load time is not removed from the first level of the run, since doing so will not result in an accurate time, due to the custom logic we're using for how the run begins
				{
					vars.TotalGameTime -= vars.LoadTime;
				}
				
				vars.LoadTime = 0.0; // Sets the value of <LoadTime> back to 0.0, since we need to clear this value for future usage
			}
		}
	}
	
	if(settings["Account For Pausing"] || current.TimeSeconds == 0) // If we're accounting for pausing, then we need to skip the pause check, since that's normally how the in-game timer responds to pausing (this is technically a NULL check as well). If the other check is true, that means that the player is loading a save while the game is paused, and we should pause the game time (pausing game time like this is mostly accurate)
	{
		return TimeSpan.FromSeconds(vars.TotalGameTime);
	}
	else if(current.Pauser == 0) // Updates the game time with the relative in-game timer, as long as the game isn't paused (this is technically a NULL check as well)
	{
		return TimeSpan.FromSeconds(vars.TotalGameTime);
	}
	else // Updates the game time with the relative real time, if none of the previous checks were true
	{
		vars.TotalGameTime += vars.RealTimeDelta.TotalSeconds;
		
		return TimeSpan.FromSeconds(vars.TotalGameTime);
	}
}

exit // Fires when the game's process is closed. This can be used to stop the run by resetting, if the setting 'Reset on Game Close' is enabled
{
	if(settings["Reset on Game Close"])
	{
		vars.TimerModel.Reset();
	}
}