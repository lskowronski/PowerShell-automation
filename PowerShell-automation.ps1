Function IIS-Stop()
{
    Write-Host "Try to stop IIS"
    # get iis service
    $InternetInformationService = Get-Service -Name W3SVC
    # stop running or paused service
    switch -Regex ($InternetInformationService.Status)
    {
        'Running|Paused' 
        { 
            $InternetInformationService.Stop() 
        }
        default 
        {
            Write-Host "IIS is stopped - stop command is skipped"
        }
    }
    # wait with changes to stop 
    while($InternetInformationService.Status -ne 'Stopped')
    {
        # refresh object data
        $InternetInformationService = Get-Service -Name W3SVC
    }
    Write-Host "IIS is stopped"
}
Function IIS-Start()
{
    Write-Host "Try to start IIS"
    # get iis service
    $InternetInformationService = Get-Service -Name W3SVC
    # stop running or paused service
    switch -Regex ($InternetInformationService.Status)
    {
        'Stopped|Paused' 
        { 
            $InternetInformationService.Start() 
        }
        default 
        {
            Write-Host "IIS is already running"
        }
    }
    # wait to start
    while($InternetInformationService.Status -ne 'Running')
    {
        # refresh object data
        $InternetInformationService = Get-Service -Name W3SVC
    }
    Write-Host "IIS is started"
}
Function Windows-AddHost([string]$Ip, [string]$Name)
{
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    #$hosts = get-content $hostsPath
    "`n$Ip $Name" | Out-File -Encoding ascii -Append $hostsPath
    Write-Host "New host added: $Name"
}

Function IIS-AddSiteAndPool([string]$Name, [string]$PhysicalPath = "C:\\inetpub\wwwroot\")
{
    $path = "$($PhysicalPath)$($Name)";
    #check if website with specified name exist
    Write-Host "Try to add site with name '$($Name)'"
    $site = Get-IISSite -Name $Name|Measure-Object
    if($site.Count -eq 1)
    {
        # if site already exists we should display warning and stop whole process
        Write-Warning -Message "Site with name '$($Name)' already exists - process has stopped"
        return
    }
    else 
    {
        # site does not exist - it means that we should proceed

        # create directory for new site
        [void] (New-Item -ItemType Directory -Force -Path $path)

        # select version of Sitecore
        $directoryWithSitecoreZipFiles = "D:\\sitecore"
        $selectedZipFile = Sitecore-SelectFromDirectory($directoryWithSitecoreZipFiles)
        Write-Host "Started unpacking of $selectedZipFile"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$($directoryWithSitecoreZipFiles)\\$($selectedZipFile)", $path)
        $directoryWithSitecoreInside = $(Get-ChildItem -Path $path -Directory)[0]
        Move-Item -Force -Path "$($directoryWithSitecoreInside.FullName)\*" -Destination $path
        Remove-Item -Force -Path $directoryWithSitecoreInside.FullName
        Write-Host "Finished unpacking of $selectedZipFile"
        
        # create app pool
        [void] (New-WebAppPool -Name $Name) 
        $appPoolQuery = "IIS:\AppPools\$Name"
        Set-ItemProperty $appPoolQuery -Name "managedRuntimeVersion" -Value "v4.0"
        Set-ItemProperty $appPoolQuery -Name "autoStart" -Value true        

        # create iis site
        [void] (New-Website -Name $Name -PhysicalPath "$($path)\Website\" -ApplicationPool $Name)
        $siteQuery = "IIS:\Sites\$Name"   

        # set bindings
        Set-ItemProperty $siteQuery -Name "Bindings" -Value @{ protocol = "http"; bindingInformation = "127.0.0.1:80:$Name"} 
        Write-Host "Website with name $($Name) created in directory $($path)\"
        
        # add host definition 
        Windows-AddHost("127.0.0.1", $Name)

        # start IIS and new site
        IIS-Start
        $createdSite = Get-Website -Name $Name
        $createdSite.Start()
    }
}

Function Sitecore-SelectFromDirectory([string]$sitecoreZipFiles)
{
    $sitecoreFiles = Get-ChildItem -Path $sitecoreZipFiles -filter "*.zip" | Select-Object Name
    $sitecoreOptions = $()   
    $selectedValue = $null;
    # display available options and wait for user choice
    do {
        if($selectedValue -ne $null)
        {
            Write-Warning "Not existing value was chosen!"
        }
        $index = 0;
        foreach($sitecoreFile in $sitecoreFiles)
        {
            Write-Host "[$($index)] $($sitecoreFile.Name)" 
            $sitecoreOptions += , $sitecoreFile.Name
            $index++
        }
        $selectedValue = Read-Host -Prompt "Select Sitecore to install"
    } until (($selectedValue -ne $null) -and ($selectedValue -le $index))
    
    # version of Sitecore is selected
    $selectedVersion = $($sitecoreOptions[$selectedValue])
    Write-Host "Selected version: $selectedVersion"
    return $selectedVersion
}

$nameProvidedByUser = Read-Host -Prompt "Input your site name"
IIS-Stop
IIS-AddSiteAndPool -Name $nameProvidedByUser


