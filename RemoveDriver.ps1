#Requires -RunAsAdministrator

function Show-Menu {
    param (
        [string]$Title = 'Driver Removal Tool'
    )
    Clear-Host
    Write-Host "================ $Title ================"
    Write-Host ""
    Write-Host "1: Browse drivers (with filtering & pagination)"
    Write-Host "2: Search for drivers by name"
    Write-Host "3: Remove driver by name"
    Write-Host "4: Remove driver by path (INF file)"
    Write-Host "5: Clear driver store"
    Write-Host "6: Deep clean driver traces"
    Write-Host "7: Create driver report (text file)"
    Write-Host "Q: Quit"
    Write-Host ""
}

function Get-InstalledDrivers {
    # This function is now integrated into Browse-Drivers and no longer used directly
    Write-Host "This function has been replaced by Browse-Drivers" -ForegroundColor Yellow
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Search-Drivers {
    $searchTerm = Read-Host "Enter driver name to search for (partial name works)"
    
    if ([string]::IsNullOrWhiteSpace($searchTerm)) {
        Write-Host "Search term cannot be empty" -ForegroundColor Red
        return
    }
    
    Write-Host "Searching for drivers matching: $searchTerm..." -ForegroundColor Cyan
    $drivers = Get-WindowsDriver -Online -All | Where-Object { 
        $null -ne $_.ClassName -and (
            $_.OriginalFileName -like "*$searchTerm*" -or
            $_.ProviderName -like "*$searchTerm*" -or
            $_.ClassName -like "*$searchTerm*" -or
            $_.Driver -like "*$searchTerm*"
        )
    }
    
    if ($drivers.Count -eq 0) {
        Write-Host "No drivers found matching: $searchTerm" -ForegroundColor Yellow
    } else {
        # Group by class for better organization
        $grouped = $drivers | Group-Object -Property ClassName
        
        Write-Host "`nFound $($drivers.Count) drivers matching: $searchTerm" -ForegroundColor Green
        
        # Create a numbered list for selection
        $driverList = @()
        $index = 1
        
        foreach ($class in $grouped) {
            Write-Host "`n== $($class.Name) Drivers ==" -ForegroundColor Green
            foreach ($driver in $class.Group) {
                Write-Host "[$index] Driver Name: $($driver.OriginalFileName)" -ForegroundColor Yellow
                Write-Host "    Provider: $($driver.ProviderName)"
                Write-Host "    Version: $($driver.Version)"
                Write-Host "    Date: $($driver.Date)"
                Write-Host "    INF Path: $($driver.Driver)"
                Write-Host ""
                
                # Add to selection list
                $driverList += $driver
                $index++
            }
        }
        
        # Ask if user wants to remove a driver
        $removeOption = Read-Host "Enter number to remove a specific driver (or press Enter to return to menu)"
        
        if (![string]::IsNullOrWhiteSpace($removeOption) -and $removeOption -match '^\d+$') {
            $selectedIndex = [int]$removeOption - 1
            
            if ($selectedIndex -ge 0 -and $selectedIndex -lt $driverList.Count) {
                $selectedDriver = $driverList[$selectedIndex]
                Remove-SelectedDriver -Driver $selectedDriver
            } else {
                Write-Host "Invalid selection." -ForegroundColor Red
            }
        }
    }
    
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Remove-SelectedDriver {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Driver
    )
    
    Write-Host "`nSelected driver for removal:" -ForegroundColor Green
    Write-Host "Driver Name: $($Driver.OriginalFileName)" -ForegroundColor Yellow
    Write-Host "Provider: $($Driver.ProviderName)"
    Write-Host "Version: $($Driver.Version)"
    Write-Host "Date: $($Driver.Date)"
    Write-Host "INF Path: $($Driver.Driver)"
    
    $confirm = Read-Host "`nAre you sure you want to remove this driver? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "Removing driver..." -ForegroundColor Cyan
        
        # Extract the actual inf filename (oem##.inf) from the path
        $infFile = Split-Path $Driver.Driver -Leaf
        
        # Disable and stop related services
        Write-Host "Checking for related services..." -ForegroundColor Cyan
        $deviceInfo = pnputil /enum-devices /class * | Select-String -Pattern $infFile -Context 5
        
        if ($deviceInfo) {
            $deviceId = $deviceInfo | ForEach-Object { 
                if ($_ -match "Instance ID:\s+(.+)") { 
                    $Matches[1] 
                } 
            }
            
            if ($deviceId) {
                Write-Host "Disabling device..." -ForegroundColor Cyan
                $result = & pnputil /disable-device $deviceId 2>&1
                Write-Host $result
            }
        }
        
        # Remove the driver
        Write-Host "Uninstalling driver package: $infFile..." -ForegroundColor Cyan
        $result = pnputil /delete-driver $infFile /force
        Write-Host $result
        
        # Clean registry traces
        Write-Host "Cleaning registry traces..." -ForegroundColor Cyan
        $driverKeyword = ($Driver.ProviderName -split " ")[0]
        Write-Host "Searching for registry keys related to: $driverKeyword"
        
        # Common registry paths for driver entries
        $registryPaths = @(
            "HKLM:\SYSTEM\CurrentControlSet\Services\*$driverKeyword*",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*$driverKeyword*"
        )
        
        foreach ($path in $registryPaths) {
            $keys = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($keys) {
                Write-Host "Found the following registry keys:" -ForegroundColor Yellow
                $keys | ForEach-Object { Write-Host "  $($_.Name)" }
                
                $confirm = Read-Host "Delete these registry keys? (y/n)"
                if ($confirm -eq 'y') {
                    foreach ($key in $keys) {
                        try {
                            Remove-Item -Path $key.PSPath -Recurse -Force
                            Write-Host "Deleted: $($key.Name)" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Failed to delete: $($key.Name) - $_" -ForegroundColor Red
                        }
                    }
                }
            }
        }
        
        Write-Host "Driver removal complete!" -ForegroundColor Green
    }
    else {
        Write-Host "Driver removal cancelled." -ForegroundColor Yellow
    }
}

function Remove-DriverByName {
    $driverName = Read-Host "Enter driver name to remove (e.g., oem1.inf)"
    
    try {
        Write-Host "Searching for driver: $driverName..." -ForegroundColor Cyan
        $driver = Get-WindowsDriver -Online -All | Where-Object { $_.OriginalFileName -eq $driverName }
        
        if ($driver) {
            # Get confirmation from user
            Write-Host "`nFound driver:" -ForegroundColor Green
            Write-Host "Driver Name: $($driver.OriginalFileName)" -ForegroundColor Yellow
            Write-Host "Provider: $($driver.ProviderName)"
            Write-Host "Version: $($driver.Version)"
            Write-Host "Date: $($driver.Date)"
            Write-Host "INF Path: $($driver.Driver)"
            
            $confirm = Read-Host "`nAre you sure you want to remove this driver? (y/n)"
            if ($confirm -eq 'y') {
                Write-Host "Removing driver..." -ForegroundColor Cyan
                
                # Disable and stop related services
                Write-Host "Checking for related services..." -ForegroundColor Cyan
                $deviceInfo = pnputil /enum-devices /class * | Select-String -Pattern $driverName -Context 5
                
                if ($deviceInfo) {
                    $deviceId = $deviceInfo | ForEach-Object { 
                        if ($_ -match "Instance ID:\s+(.+)") { 
                            $Matches[1] 
                        } 
                    }
                    
                    if ($deviceId) {
                        Write-Host "Disabling device..." -ForegroundColor Cyan
                        $result = & pnputil /disable-device $deviceId 2>&1
                        Write-Host $result
                    }
                }
                
                # Remove the driver
                $result = pnputil /delete-driver $driverName /force
                Write-Host $result
                
                # Clean registry traces
                Write-Host "Cleaning registry traces..." -ForegroundColor Cyan
                # Add registry cleaning logic here
                
                Write-Host "Driver removal complete!" -ForegroundColor Green
            }
            else {
                Write-Host "Driver removal cancelled." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Driver not found. Make sure the name is correct (e.g., oem1.inf)." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
    
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Remove-DriverByPath {
    $driverPath = Read-Host "Enter full path to the INF file"
    
    try {
        if (Test-Path $driverPath) {
            $driverName = Split-Path $driverPath -Leaf
            Write-Host "Found driver file: $driverName" -ForegroundColor Cyan
            
            $confirm = Read-Host "Are you sure you want to remove this driver? (y/n)"
            if ($confirm -eq 'y') {
                Write-Host "Removing driver..." -ForegroundColor Cyan
                
                # Uninstall driver package
                $result = pnputil /delete-driver $driverName /force
                Write-Host $result
                
                # Also remove the file if it still exists
                if (Test-Path $driverPath) {
                    Remove-Item -Path $driverPath -Force
                    Write-Host "INF file deleted" -ForegroundColor Green
                }
                
                Write-Host "Driver removal complete!" -ForegroundColor Green
            }
            else {
                Write-Host "Driver removal cancelled." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "INF file not found. Please check the path and try again." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
    
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Clear-DriverStore {
    Write-Host "Cleaning driver store. This might take some time..." -ForegroundColor Cyan
    
    try {
        # List and prompt for old driver packages to remove
        Write-Host "Checking for old driver packages..." -ForegroundColor Cyan
        $oldDrivers = pnputil /enum-drivers | Out-String
        
        if ($oldDrivers -match "Published Name") {
            Write-Host $oldDrivers
            $confirm = Read-Host "Would you like to remove old and duplicate drivers? (y/n)"
            
            if ($confirm -eq 'y') {
                Write-Host "Cleaning old driver packages..." -ForegroundColor Cyan
                
                # Find duplicate drivers (keeping the most recent)
                $drivers = pnputil /enum-drivers 2>&1 | Out-String
                $driverLines = $drivers -split "`r`n"
                $driverPackages = @()
                $currentPackage = $null
                
                foreach ($line in $driverLines) {
                    if ($line -match "Published Name\s+:\s+(.+\.inf)") {
                        if ($currentPackage) {
                            $driverPackages += $currentPackage
                        }
                        $currentPackage = @{
                            Name = $Matches[1]
                            DriverDate = $null
                            OriginalName = $null
                        }
                    } elseif ($line -match "Original Name\s+:\s+(.+)") {
                        if ($currentPackage) {
                            $currentPackage.OriginalName = $Matches[1]
                        }
                    } elseif ($line -match "Driver Date\s+:\s+(.+)") {
                        if ($currentPackage) {
                            $currentPackage.DriverDate = $Matches[1]
                        }
                    }
                }
                
                # Add the last package if exists
                if ($currentPackage) {
                    $driverPackages += $currentPackage
                }
                
                # Group by original name to find duplicates
                $driverGroups = $driverPackages | Group-Object -Property OriginalName
                $duplicatesToRemove = @()
                
                foreach ($group in $driverGroups) {
                    if ($group.Count -gt 1) {
                        # Sort by date (descending) and skip the first (most recent)
                        $oldDrivers = $group.Group | Sort-Object -Property DriverDate -Descending | Select-Object -Skip 1
                        $duplicatesToRemove += $oldDrivers
                    }
                }
                
                if ($duplicatesToRemove.Count -gt 0) {
                    Write-Host "Found $($duplicatesToRemove.Count) duplicate driver packages to remove:" -ForegroundColor Yellow
                    foreach ($driver in $duplicatesToRemove) {
                        Write-Host "  $($driver.Name) - $($driver.OriginalName)" -ForegroundColor Yellow
                    }
                    
                    $confirmRemove = Read-Host "Remove these duplicate drivers? (y/n)"
                    if ($confirmRemove -eq 'y') {
                        foreach ($driver in $duplicatesToRemove) {
                            Write-Host "Removing $($driver.Name)..." -ForegroundColor Cyan
                            $removeResult = pnputil /delete-driver $driver.Name /force 2>&1 | Out-String
                            Write-Host $removeResult
                        }
                        Write-Host "Driver store cleanup completed" -ForegroundColor Green
                    }
                } else {
                    Write-Host "No duplicate drivers found in the driver store" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "No driver packages found" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
    
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Remove-DriverTraces {
    $driverName = Read-Host "Enter driver name to deep clean (e.g., nvidia, realtek)"
    
    if ([string]::IsNullOrWhiteSpace($driverName)) {
        Write-Host "Driver name cannot be empty" -ForegroundColor Red
        return
    }
    
    Write-Host "Performing deep cleaning for driver traces: $driverName" -ForegroundColor Cyan
    Write-Host "WARNING: This is a dangerous operation. Backup your system before proceeding." -ForegroundColor Red
    $confirm = Read-Host "Are you sure you want to continue? (y/n)"
    
    if ($confirm -ne 'y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }
    
    try {
        # Check for driver services
        Write-Host "Checking for related services..." -ForegroundColor Cyan
        $services = Get-Service | Where-Object { $_.DisplayName -like "*$driverName*" -or $_.Name -like "*$driverName*" }
        
        if ($services) {
            Write-Host "Found the following services:" -ForegroundColor Yellow
            $services | ForEach-Object { Write-Host "  $($_.DisplayName) [$($_.Name)]" }
            
            $confirm = Read-Host "Stop and disable these services? (y/n)"
            if ($confirm -eq 'y') {
                foreach ($service in $services) {
                    if ($service.Status -eq "Running") {
                        Write-Host "Stopping service: $($service.Name)..." -ForegroundColor Cyan
                        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
                        # Verify if service was stopped
                        $svcStatus = Get-Service -Name $service.Name -ErrorAction SilentlyContinue
                        if ($svcStatus -and $svcStatus.Status -eq "Running") {
                            Write-Host "  Warning: Service could not be stopped. Some files may remain locked." -ForegroundColor Yellow
                        }
                    }
                    Write-Host "Disabling service: $($service.Name)..." -ForegroundColor Cyan
                    Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
                }
            }
        }
        
        # Remove related driver files
        Write-Host "Searching for driver files..." -ForegroundColor Cyan
        $driverFiles = @(
            "$env:SystemRoot\System32\drivers\*$driverName*.sys",
            "$env:SystemRoot\System32\*$driverName*.dll",
            "$env:SystemRoot\SysWOW64\*$driverName*.dll"
        )
        
        foreach ($path in $driverFiles) {
            $files = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($files) {
                Write-Host "Found the following files:" -ForegroundColor Yellow
                $files | ForEach-Object { Write-Host "  $($_.FullName)" }
                
                $confirm = Read-Host "Delete these files? (y/n)"
                if ($confirm -eq 'y') {
                    $lockedFiles = @()
                    foreach ($file in $files) {
                        try {
                            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                            Write-Host "Deleted: $($file.FullName)" -ForegroundColor Green
                        }
                        catch {
                            $lockedFiles += $file.FullName
                            Write-Host "Failed to delete (file in use): $($file.FullName)" -ForegroundColor Red
                        }
                    }
                    
                    # If some files couldn't be deleted, offer solutions
                    if ($lockedFiles.Count -gt 0) {
                        Write-Host "`nSome files could not be deleted because they are in use." -ForegroundColor Yellow
                        Write-Host "To remove these files, you can:" -ForegroundColor Yellow
                        Write-Host "1. Boot into Safe Mode and run this script again." -ForegroundColor Yellow
                        Write-Host "2. Create a batch file to delete them on next boot:" -ForegroundColor Yellow
                        
                        $createBatch = Read-Host "Create a cleanup batch file to delete on next boot? (y/n)"
                        if ($createBatch -eq 'y') {
                            $batchPath = "$env:USERPROFILE\Desktop\DeleteDriverFiles.bat"
                            
                            # Create batch file content
                            $batchContent = "@echo off`r`necho Deleting driver files...`r`n"
                            foreach ($lockedFile in $lockedFiles) {
                                $batchContent += "del /f /q `"$lockedFile`"`r`n"
                            }
                            $batchContent += "echo Cleanup completed`r`npause"
                            
                            # Write to file
                            Set-Content -Path $batchPath -Value $batchContent
                            Write-Host "Batch file created at: $batchPath" -ForegroundColor Green
                            Write-Host "Run this file after restarting your computer" -ForegroundColor Green
                        }
                    }
                }
            }
        }
        
        # Clean registry
        Write-Host "Searching for registry traces..." -ForegroundColor Cyan
        $registryPaths = @(
            "HKLM:\SYSTEM\CurrentControlSet\Services\*$driverName*",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*$driverName*"
        )
        
        foreach ($path in $registryPaths) {
            $keys = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($keys) {
                Write-Host "Found the following registry keys:" -ForegroundColor Yellow
                $keys | ForEach-Object { Write-Host "  $($_.Name)" }
                
                $confirm = Read-Host "Delete these registry keys? (y/n)"
                if ($confirm -eq 'y') {
                    foreach ($key in $keys) {
                        try {
                            # Check if the key exists before trying to delete it
                            if (Test-Path -Path $key.PSPath) {
                                Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction Stop
                                Write-Host "Deleted: $($key.Name)" -ForegroundColor Green
                            } else {
                                Write-Host "Key not found: $($key.Name) (may have been already deleted)" -ForegroundColor Yellow
                            }
                        }
                        catch {
                            Write-Host "Failed to delete: $($key.Name) - $_" -ForegroundColor Red
                        }
                    }
                }
            }
        }
        
        Write-Host "Deep cleaning complete!" -ForegroundColor Green
        Write-Host "`nNote: If some files could not be deleted, reboot your computer and try again," -ForegroundColor Yellow
        Write-Host "or try running this script in Safe Mode for complete removal." -ForegroundColor Yellow
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
    
    Write-Host "`nPress any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Create-DriverReport {
    $reportPath = "$env:USERPROFILE\Desktop\DriverReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $customPath = Read-Host "Enter path to save report or press Enter for default [$reportPath]"
    
    if (-not [string]::IsNullOrWhiteSpace($customPath)) {
        $reportPath = $customPath
    }
    
    # Ask if Microsoft drivers should be excluded
    $excludeMicrosoft = Read-Host "Exclude Microsoft drivers? (y/n)"
    $excludeMicrosoft = $excludeMicrosoft -eq 'y'
    
    try {
        Write-Host "Generating driver report. Please wait..." -ForegroundColor Cyan
        
        # Create the report file with a header
        $computerInfo = Get-ComputerInfo
        $header = @"
=====================================================
Driver Report for $env:COMPUTERNAME
Generated on $(Get-Date)
OS: $($computerInfo.WindowsProductName) $($computerInfo.OsArchitecture) (Build $($computerInfo.WindowsVersion))
=====================================================

"@
        Set-Content -Path $reportPath -Value $header
        
        # Get all drivers
        $drivers = Get-WindowsDriver -Online -All | Where-Object { $null -ne $_.ClassName }
        
        # Apply Microsoft filter if requested
        if ($excludeMicrosoft) {
            $drivers = $drivers | Where-Object { $_.ProviderName -ne "Microsoft" }
            Add-Content -Path $reportPath -Value "Microsoft drivers have been excluded from this report.`n"
        }
        
        # Group by class for better organization
        $grouped = $drivers | Group-Object -Property ClassName
        
        # Add total count to the report
        Add-Content -Path $reportPath -Value "Total drivers installed: $($drivers.Count)`n"
        
        foreach ($class in $grouped) {
            Add-Content -Path $reportPath -Value "== $($class.Name) Drivers =="
            foreach ($driver in $class.Group) {
                $driverInfo = @"
Driver Name: $($driver.OriginalFileName)
  Provider: $($driver.ProviderName)
  Version: $($driver.Version)
  Date: $($driver.Date)
  INF Path: $($driver.Driver)

"@
                Add-Content -Path $reportPath -Value $driverInfo
            }
            Add-Content -Path $reportPath -Value ""
        }
        
        Write-Host "Driver report created successfully at:" -ForegroundColor Green
        Write-Host $reportPath -ForegroundColor Yellow
    }
    catch {
        Write-Host "Error generating report: $_" -ForegroundColor Red
    }
    
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function List-DriversByProvider {
    # Rename to make it clearer
    Browse-Drivers
}

function Browse-Drivers {
    Write-Host "Retrieving installed drivers. Please wait..." -ForegroundColor Cyan
    
    # Get all drivers
    $drivers = Get-WindowsDriver -Online -All | Where-Object { $null -ne $_.ClassName }
    
    # Group by provider for filtering options
    $providerGroups = $drivers | Group-Object -Property ProviderName | Sort-Object -Property Count -Descending
    
    # Get non-Microsoft drivers count
    $nonMsDrivers = $drivers | Where-Object { $_.ProviderName -ne "Microsoft" }
    $nonMsCount = $nonMsDrivers.Count
    
    # Display provider options with counts - add the Microsoft exclusion option directly
    Clear-Host
    Write-Host "======== Driver Filter Options ========" -ForegroundColor Green
    Write-Host "0: All Providers ($($drivers.Count) drivers)" -ForegroundColor Yellow
    Write-Host "1: All Providers excluding Microsoft ($nonMsCount drivers)" -ForegroundColor Yellow
    
    # Adjust the index to account for the new option
    $index = 2
    foreach ($provider in $providerGroups) {
        Write-Host "${index}: $($provider.Name) ($($provider.Count) drivers)" -ForegroundColor Yellow
        $index++
    }
    
    # Set default values to reduce questions
    $pageSize = 15
    $groupByProvider = $false
    
    Write-Host "`nPage size: $pageSize drivers per page (Can be changed in config)" -ForegroundColor Cyan
    Write-Host "Grouping: By Class (Can be changed in config)" -ForegroundColor Cyan
    Write-Host "Use 'C' during navigation to access config options" -ForegroundColor Cyan
    Write-Host ""
    
    $selectedIndex = Read-Host "Select filter option or 'q' to return to menu"
    
    if ($selectedIndex -eq 'q') {
        return
    }
    
    if ($selectedIndex -match '^\d+$') {
        $selectedIndex = [int]$selectedIndex
        
        # Handle the filter selection
        if ($selectedIndex -eq 0) {
            # All drivers
            $selectedDrivers = $drivers
            $providerName = "All Providers"
        }
        elseif ($selectedIndex -eq 1) {
            # All non-Microsoft drivers
            $selectedDrivers = $nonMsDrivers
            $providerName = "All Providers excluding Microsoft"
        }
        elseif ($selectedIndex -ge 2 -and $selectedIndex -lt ($providerGroups.Count + 2)) {
            # Specific provider (adjust index to account for the added option)
            $selectedProvider = $providerGroups[$selectedIndex - 2]
            $selectedDrivers = $drivers | Where-Object { $_.ProviderName -eq $selectedProvider.Name }
            $providerName = $selectedProvider.Name
        }
        else {
            Write-Host "Invalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 2
            return
        }
        
        # Display the drivers with pagination
        $totalDrivers = $selectedDrivers.Count
        $totalPages = [math]::Ceiling($totalDrivers / $pageSize)
        $currentPage = 1
        
        do {
            Clear-Host
            Write-Host "======== $providerName Drivers (Page $currentPage of $totalPages) ========" -ForegroundColor Green
            
            $startIndex = ($currentPage - 1) * $pageSize
            $endIndex = [Math]::Min($startIndex + $pageSize - 1, $totalDrivers - 1)
            
            # Use Select-Object instead of array slicing to avoid the range operator error
            $pageDrivers = $selectedDrivers | Select-Object -Skip $startIndex -First ($endIndex - $startIndex + 1)
            
            if ($groupByProvider) {
                # Group by provider for display
                $pageDriversByGroup = $pageDrivers | Group-Object -Property ProviderName
            } else {
                # Group by class for better organization on each page (default)
                $pageDriversByGroup = $pageDrivers | Group-Object -Property ClassName
            }
            
            foreach ($group in $pageDriversByGroup) {
                Write-Host "`n== $($group.Name) ==" -ForegroundColor Green
                $itemIndex = $startIndex + 1
                
                foreach ($driver in $group.Group) {
                    Write-Host "[$itemIndex] Driver Name: $($driver.OriginalFileName)" -ForegroundColor Yellow
                    Write-Host "    Provider: $($driver.ProviderName)"
                    Write-Host "    Class: $($driver.ClassName)"
                    Write-Host "    Version: $($driver.Version)"
                    Write-Host "    Date: $($driver.Date)"
                    Write-Host "    INF Path: $($driver.Driver)"
                    Write-Host ""
                    $itemIndex++
                }
            }
            
            Write-Host "`nPage $currentPage of $totalPages (Showing items $($startIndex + 1)-$($endIndex + 1) of $totalDrivers)" -ForegroundColor Cyan
            Write-Host "Navigation: [P]revious page, [N]ext page, [S]elect driver to remove, [C]onfig, [R]eturn to menu" -ForegroundColor Cyan
            
            $navOption = Read-Host "Enter option"
            
            switch ($navOption.ToLower()) {
                'p' {
                    if ($currentPage -gt 1) {
                        $currentPage--
                    }
                }
                'n' {
                    if ($currentPage -lt $totalPages) {
                        $currentPage++
                    }
                }
                's' {
                    $driverNumber = Read-Host "Enter the number of the driver to remove"
                    if ($driverNumber -match '^\d+$') {
                        $driverIndex = [int]$driverNumber - 1
                        if ($driverIndex -ge 0 -and $driverIndex -lt $totalDrivers) {
                            Remove-SelectedDriver -Driver $selectedDrivers[$driverIndex]
                        }
                        else {
                            Write-Host "Invalid driver number." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                        }
                    }
                }
                'c' {
                    # Configuration submenu
                    Clear-Host
                    Write-Host "======== Display Configuration ========" -ForegroundColor Green
                    Write-Host "1: Change page size (currently $pageSize)" -ForegroundColor Yellow
                    Write-Host "2: Change grouping (currently $(if ($groupByProvider) {"by Provider"} else {"by Class"}))" -ForegroundColor Yellow
                    Write-Host "R: Return to driver listing" -ForegroundColor Yellow
                    
                    $configOption = Read-Host "Enter option"
                    
                    switch ($configOption.ToLower()) {
                        '1' {
                            $newPageSize = Read-Host "Enter new page size (5-50)"
                            if ($newPageSize -match '^\d+$' -and [int]$newPageSize -ge 5 -and [int]$newPageSize -le 50) {
                                $pageSize = [int]$newPageSize
                                $totalPages = [math]::Ceiling($totalDrivers / $pageSize)
                                $currentPage = 1  # Reset to first page when changing page size
                                Write-Host "Page size changed to $pageSize" -ForegroundColor Green
                            } else {
                                Write-Host "Invalid page size. Using current value." -ForegroundColor Red
                            }
                            Start-Sleep -Seconds 1
                        }
                        '2' {
                            $groupByProvider = !$groupByProvider
                            Write-Host "Grouping changed to $(if ($groupByProvider) {"by Provider"} else {"by Class"})" -ForegroundColor Green
                            Start-Sleep -Seconds 1
                        }
                    }
                }
                'r' {
                    return
                }
            }
            
        } while ($navOption.ToLower() -ne 'r')
    }
}

# Main program
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Please restart with elevated privileges." -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

do {
    Show-Menu
    $input = Read-Host "Please make a selection"
    
    switch ($input) {
        '1' {
            Browse-Drivers
        }
        '2' {
            Search-Drivers
        }
        '3' {
            Remove-DriverByName
        }
        '4' {
            Remove-DriverByPath
        }
        '5' {
            Clear-DriverStore
        }
        '6' {
            Remove-DriverTraces
        }
        '7' {
            Create-DriverReport
        }
        'q' {
            return
        }
        default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} until ($input -eq 'q') 
