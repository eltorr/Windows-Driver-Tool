# Windows Driver Removal Tool

This PowerShell script helps you completely remove device drivers and their traces from your Windows system.

## Features

- Browse all installed drivers with filtering and pagination
- Search for drivers by name or other properties
- Remove drivers by name (INF file)
- Remove drivers by path
- Clean the driver store of old and duplicate drivers
- Perform deep cleaning of driver traces (services, files, registry entries)
- Generate detailed driver reports
- Create cleanup batch files for locked driver files

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or higher
- Administrator privileges

## Usage

1. Right-click on the `RemoveDriver.ps1` file and select "Run with PowerShell" or open PowerShell as Administrator and run:
   ```powershell
   .\RemoveDriver.ps1
   ```

2. The script must run with Administrator privileges to function properly.

3. Use the interactive menu to perform various driver removal tasks:
   - Option 1: Browse drivers with filtering and pagination
   - Option 2: Search for drivers by name
   - Option 3: Remove a specific driver by name (e.g., oem1.inf)
   - Option 4: Remove a driver using its INF file path
   - Option 5: Clean the driver store of old and duplicate drivers
   - Option 6: Deep clean all traces of a driver by keyword (e.g., nvidia, realtek)
   - Option 7: Create a comprehensive driver report (text file)

## Warning

This tool performs low-level operations on your system. Always:
- Create a system restore point before use
- Backup important data
- Use with caution, especially the "Deep clean" option

## How It Works

1. **Browse Installed Drivers**: Browse through all drivers with advanced filtering by provider, pagination controls, and configurable display options.

2. **Search for Drivers**: Search for specific drivers by name, provider, or other properties.

3. **Remove Driver by Name**: Removes the driver package, disables the device, and cleans registry entries.

4. **Remove Driver by Path**: Uninstalls the driver using its INF file path.

5. **Clean Driver Store**: Removes old and duplicate drivers from the Windows driver store.

6. **Deep Clean**: Searches for and removes all traces of a driver, including:
   - Related services
   - Driver files in system directories
   - Registry entries
   - For locked files, offers to create a batch file for deletion after restart

7. **Create Driver Report**: Generates a comprehensive text report of all installed drivers, with options to exclude Microsoft drivers.

## Handling Locked Files

When removing driver files that are in use by the system:

1. The script will identify locked files that cannot be deleted immediately
2. It offers the option to create a cleanup batch file on your desktop
3. After restarting your computer, run this batch file to remove the locked files
4. Alternatively, boot into Safe Mode and run the script again for complete removal
