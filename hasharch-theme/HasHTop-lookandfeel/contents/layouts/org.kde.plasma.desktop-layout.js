var plasma = getApiVersion(1)

// Center Krunner on screen - requires relogin
const krunner = ConfigFile('krunnerrc')
krunner.group = 'General'
krunner.writeEntry('FreeFloating', true);

// Change keyboard repeat delay from default 600ms to 250ms
const kbd = ConfigFile('kcminputrc')
kbd.group = 'Keyboard'
kbd.writeEntry('RepeatDelay', 250);

// Create Top Panel
// HasH panel ships pre-built in the captured appletsrc layout (no external template)

// Create Bottom Panel (Dock)
// HasH dock ships pre-built in the captured appletsrc layout (no external template)


// Configure Contextual Menu Plugin
// Targets the global [ActionPlugins][0][RightButton;NoModifier] section
// \x1d is KConfig's internal nested group separator
const desktoprc = ConfigFile('plasma-org.kde.plasma.desktop-appletsrc')
desktoprc.group = "ActionPlugins\x1d0\x1dRightButton;NoModifier"

// System Actions
desktoprc.writeEntry('_run_command', true)          // KRunner (Run Command)
desktoprc.writeEntry('_lock_screen', true)          // Lock Screen
desktoprc.writeEntry('_logout', true)               // Show Logout Screen
desktoprc.writeEntry('_open_terminal', true)        // Open Terminal

// Desktop & Display
desktoprc.writeEntry('_context', true)              // Contextual Actions
desktoprc.writeEntry('_display_settings', true)     // Display Settings
desktoprc.writeEntry('_wallpaper', true)            // Wallpaper Settings

// Desktop Management
desktoprc.writeEntry('add widgets', true)           // Add Widgets
desktoprc.writeEntry('_add panel', true)            // Add Panel
desktoprc.writeEntry('configure', true)             // Configure Desktop
desktoprc.writeEntry('configure shortcuts', false)  // Configure Shortcuts (disabled)
desktoprc.writeEntry('desktop edit mode', true)     // Enter Edit Mode
desktoprc.writeEntry('manage activities', true)     // Manage Activities
desktoprc.writeEntry('remove', true)                // Remove

// Separators
desktoprc.writeEntry('_sep1', true)
desktoprc.writeEntry('_sep2', true)
desktoprc.writeEntry('_sep3', true)
desktoprc.writeEntry('_sep4', true)


// Apply Wallpaper Active Blur plugin to all Desktops of the current Activity
var allDesktops = desktops();
for (i=0;i<allDesktops.length;i++){
  d = allDesktops[i];
  d.wallpaperPlugin = "com.hash.matrixrain";
  d.currentConfigGroup = Array("Wallpaper", "com.hash.matrixrain", "General");
}
