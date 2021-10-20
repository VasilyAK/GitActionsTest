[string] $BranchHead = $Env:GITHUB_REF
[string] $NuGetPackageId = $Env:NUGET_PACKAGE_ID

[string] $MainBranch = "main"
[string] $ReleaseBranch = "release"
[string] $NewReleasePostfix = "-new"

function Get-Git-BranchDir
{
    param ([string] $GitBranchHead)
    
    [string] $GitBranchFullName = $GitBranchHead.Replace("refs/heads/", "").Trim()
    [string[]] $GitBranchDirs = $GitBranchFullName.Split("/")
    if ($GitBranchDirs[0] -eq $MainBranch)
    {
        Return ""
    }

    Return $GitBranchDirs[0]
}


function Get-Git-BranchName
{
    param ([string] $GitBranchHead)
    
    [string] $GitBranchFullName = $GitBranchHead.Replace("refs/heads/", "").Trim()
    [string[]] $GitBranchDirs = $GitBranchFullName.Split("/")
    [string] $GitBranchName = $GitBranchDirs[($GitBranchDirs.Length - 1)]

    Return $GitBranchName
}

function Get-LatestNuGetPackageVersion
{
    param ([string] $PackageId, [string] $ReleaseVersion)

    [string] $LatestNuGetReleaseVersion = "0.0.0"
 
    try
    {
        [string] $URL = "https://api.nuget.org/v3-flatcontainer/$PackageId/index.json"
        [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls, Ssl3"
        $Response = Invoke-WebRequest -Uri $URL -TimeoutSec 15
    
        do{sleep 0.1} until($Response.StatusCode -ne "")

        if ($Response.StatusCode -eq 200)
        {
            Write-Host "A response was received from the 'nuget.org' site to request a package '$PackageId'"
            [PSCustomObject] $PesponseContent = $Response.Content | ConvertFrom-Json
            [string[]]$NuGetReleaseVersions = $PesponseContent.PSObject.Properties["versions"].Value
            $NuGetReleaseVersions = $NuGetReleaseVersions.Where({$_.StartsWith($ReleaseVersion)}) | Sort-Object -Descending
            if ($NuGetReleaseVersions.Length -gt 0) {
               $LatestNuGetReleaseVersion = $NuGetReleaseVersions[0]
            }
        } else {
            Write-Host "No response received the 'nuget.org' site to request a package '$PackageId'"
            Write-Host "Status code: ${Response.StatusCode}"
        }
    }
    catch [System.Net.WebException]
    {
        [string] $WebErrorMessage = $_.ToString()
        if ($WebErrorMessage.Contains("BlobNotFound"))
        {
            Write-Warning "A response 'BlobNotFound' was received from the 'nuget.org' site to request a package '$PackageId'"
            $LatestNuGetReleaseVersion = "$ReleaseVersion.0$NewReleasePostfix"
        }
        else
        {
            Write-Warning "Error while response receiving from the 'nuget.org' site to request a package '$PackageId'"
            Write-Warning $WebErrorMessage
        }
    }

    Return $LatestNuGetReleaseVersion
}

function Get-NewFixVersionWithError
{
    Write-Warning "Can not parse latest NuGet package version $LatestNuGetPackageVersion"
    Write-Warning "Latest NuGet package version must match the mask 'x.x.x'"
    Return -1
}

function Get-NewFixVersion
{
    param([string] $LatestNuGetPackageVersion)
    
    [int32] $FixVersionInt = $Null
    [string] $FixVersion = $LatestNuGetPackageVersion.Split(".")[2]
    
    if ($FixVersion -eq $Null)
    {        
        Return Get-NewFixVersionWithError
    }

    if ($FixVersion.EndsWith($NewReleasePostfix))
    {
        if ([int32]::TryParse($FixVersion.Replace($NewReleasePostfix, ""), [ref]$FixVersionInt))
        {
            Return $FixVersionInt
        }
        Return Get-NewFixVersionWithError
    }

    if ([int32]::TryParse($FixVersion, [ref]$FixVersionInt))
    {
        Return $FixVersionInt + 1
    }
    Return Get-NewFixVersionWithError
}

Write-Host "Start parse branch head: $BranchHead"
[string] $BranchDir = Get-Git-BranchDir -GitBranchHead $BranchHead
[string] $BranchName = Get-Git-BranchName -GitBranchHead $BranchHead

if ($BranchDir -eq "$ReleaseBranch") {
    [string] $ReleaseVersion = $BranchName
    [string] $LatestNuGetPackageVersion = Get-LatestNuGetPackageVersion -PackageId $NuGetPackageId -ReleaseVersion $ReleaseVersion
    [int] $NewFixVersion = Get-NewFixVersion -LatestNuGetPackageVersion $LatestNuGetPackageVersion
    [string] $NewReleaseVersion = "$ReleaseVersion.$NewFixVersion"

    Write-Host "Branch name: $ReleaseBranch"
    echo "BRANCH_NAME=$ReleaseBranch" >> $Env:GITHUB_ENV
    Write-Host "Update release version: $NewReleaseVersion"
    echo "RELEASE_VERSION=$NewReleaseVersion" >> $Env:GITHUB_ENV
} else {
    Write-Host "Branch name: $BranchName"
    echo "BRANCH_NAME=$BranchName" >> $Env:GITHUB_ENV
}
