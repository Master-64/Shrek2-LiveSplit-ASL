// *****************************************************
// *  Shrek 2 Autosplitter & Load Remover by Master_64 *
// *		  Copyrighted (c) Master_64, 2023		   *
// *   May be modified but not without proper credit!  *
// *****************************************************
// 
// Technical Help:
// - HuniePop
// - Seifer
// 
// General Help:
// - Janek
// - mrjor
// - Im_a_mirror
// - Metallicafan212
// 
// 
// Features of this script:
// - Automatic splitting across all main levels, with support for modded levels (Note: manual split required for FGM!)
// - Automatic starting and resetting of splits
// - Proper load remover that will remove the load times from the game in real time for the game time shown in LiveSplit
// - Game time in LiveSplit represents the exact in-game timer, meaning timing is incredibly accurate
// 
// Important notice in regards to this script's consistency:
// - Since this is a .asl script, the frequency rate this script runs at is entirely dependent on LiveSplit! LiveSplit's default refresh rate is 20 HZ, so you need to increase this!
//  - If you're playing on 60 FPS, make sure that the refresh rate of LiveSplit is also at 60 HZ
//  - If you're playing on an uncapped framerate, I recommend setting the refresh rate of LiveSplit to your average framerate you experience in-game. See below for how to get that
//   - An easy metric is to load into Prison Shrek and get your average framerate through a third-party software, then double that value, and that should be a high enough refresh rate. If you have no idea, set it to 100 HZ


state("game") // Grabs the process "game.exe" and tracks a few pointers for values
{
	float TimeSeconds : "Engine.dll", 0x4DFFF8, 0x68, 0x14C, 0x9C, 0x480;		// Returns LevelInfo.TimeSeconds
	float TimeAfterLoading : "Engine.dll", 0x4DFFF8, 0x30, 0x34, 0xA40;			// Returns SHHeroController.TimeAfterLoading (value is dynamically assigned, so the value can appear incorrect for a frame or so)
	byte IsPaused : "Engine.dll", 0x44315C;										// Returns 1 if LevelInfo.Pauser exists
	uint CurrentMapAddress : "Engine.dll", 0x4DFFF8, 0x68, 0x9C, 0xA8, 0x4E0;	// Returns the current map address. Requires additional work to get the value of the current map
	float TimeDilation : "Engine.dll", 0x4DFFF8, 0x68, 0x14C, 0x9C, 0x47C;		// Returns LevelInfo.TimeDilation
}

startup // All code that is ran before running all logic
{
	// Adds settings
	settings.Add("Reset on Game Close", true, "If true, resets when the game process is closed.");
	settings.Add("Split On Played Maps", false, "[Caution] If true, will split even if the map has been finished before.");
	settings.Add("Any Map Splits", false, "[Caution] If true, splits upon changing to any map.");
	settings.Add("Account For Pausing", false, "[Not officially allowed] If true, game time pauses upon pausing.");
	
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
		"BOOK_FRONTEND",
		"BOOK_STORY_1",
		"BOOK_STORY_4",
		"BOOK_STORYBOOK",
		"CREDITS",
		"ENTRY",
		"1_SHREKS_SWAMP",
		"4_FGM_PIB",
		"3_THE_HUNT_PART1",
		"7_PRISON_DONKEY"
	};
	
	vars.PlayedMaps = new List<string>(); // All maps that have been played on so far
	vars.ShouldSplit = false;
	vars.CurrentMap = "";
	vars.OldMap = "";
	vars.TotalGameTime = 0.0;
	vars.LoadTime = 0.0;
	vars.TimerModel = new TimerModel { CurrentState = timer }; // Used for if the game closes and we need to automatically reset the timer
	vars.RealTime = TimeSpan.Zero;
	vars.RealTimeDelta = TimeSpan.Zero;
}

init // Initializes the script, and assigns a version number to it
{
	version = "v3.0 [Release]";
}

update // Runs everytime the script is ticked
{
	if(current.CurrentMapAddress != 0) // NULL check
	{
		vars.CurrentMap = new DeepPointer(new IntPtr(current.CurrentMapAddress)).DerefString(game, 1024).ToUpper().Replace(".UNR", "");
		
		if(vars.OldMap != "") // Hacky code because ASL Part 1
		{
			vars.PlayedMaps.Add(vars.OldMap);
			
			vars.ShouldSplit = true;
		}
	}
	else
	{
		vars.OldMap = (string)vars.CurrentMap;
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
}

split // Waits until a map has changed, then runs logic to see if the map is different or not. If the map is different, and it's not an excluded splitting map, then we return true (to split)
{
	if(vars.ShouldSplit) // Hacky code because ASL Part 2
	{
		vars.ShouldSplit = false;
		
		if(vars.OldMap == vars.CurrentMap) // Doesn't split if a player loaded a save
		{
			vars.OldMap = "";
			
			return false;
		}
		else
		{
			vars.OldMap = "";
		}
		
		if(!settings["Any Map Splits"]) // Doesn't split if the map is manually excluded from the autosplitter
		{
			foreach(string item in vars.ExcludedSplitMaps)
			{
				if(item.Contains(vars.CurrentMap))
				{
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
					return false;
				}
			}
		}
		
		return true;
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
				if(vars.TotalGameTime - vars.LoadTime >= 0.0) // Makes sure that the change we're about to make to the total game time is not going to result in the timer going negative (clamping)
				{
					vars.TotalGameTime -= vars.LoadTime;
					
					vars.LoadTime = 0.0; // Sets the value of <LoadTime> back to 0.0, since we need to clear this value for future usage
				}
			}
		}
	}
	
	if(settings["Account For Pausing"]) // If we're accounting for pausing, then we need to skip the pause check, since that's normally how the in-game timer responds to pausing
	{
		return TimeSpan.FromSeconds(vars.TotalGameTime);
	}
	
	if(current.IsPaused == 0) // Updates the game time with the relative in-game timer
	{
		return TimeSpan.FromSeconds(vars.TotalGameTime);
	}
	else // Updates the game time with the relative real time
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