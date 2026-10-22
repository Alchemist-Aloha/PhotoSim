param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$InstallDirectory
)

$ErrorActionPreference = 'Stop'
$installer = (Resolve-Path -LiteralPath $InstallerPath).Path
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$destination = [IO.Path]::GetFullPath($InstallDirectory)
if (Test-Path -LiteralPath $destination) {
    throw "Installer test needs a new directory: $destination"
}
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D0404317-743A-46CE-9394-04B9B81BDDAB}_is1'
if (Test-Path -LiteralPath $uninstallKey) {
    throw 'PhotoSim is already installed for this user; use a clean account for the installer test.'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
$installLog = "$destination-install.log"
$uninstallLog = "$destination-uninstall.log"
$files = @(Get-ChildItem -LiteralPath $bundle -Recurse -File)
try {
    $arguments = @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/NOICONS',
        ('/DIR="{0}"' -f $destination), ('/LOG="{0}"' -f $installLog)
    )
    $setup = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($setup.ExitCode -ne 0) {
        throw "Installer failed with exit code $($setup.ExitCode); see $installLog"
    }
    foreach ($source in $files) {
        $relative = [IO.Path]::GetRelativePath($bundle, $source.FullName)
        $installed = Join-Path $destination $relative
        if (!(Test-Path -LiteralPath $installed -PathType Leaf)) {
            throw "Installed file is missing: $relative"
        }
        if ((Get-FileHash -LiteralPath $source.FullName).Hash -ne
            (Get-FileHash -LiteralPath $installed).Hash) {
            throw "Installed file differs from the release bundle: $relative"
        }
    }
    foreach ($relative in @('LICENSE', 'README.md', 'unins000.exe')) {
        if (!(Test-Path -LiteralPath (Join-Path $destination $relative) -PathType Leaf)) {
            throw "Installer support file is missing: $relative"
        }
    }
    if (!(Test-Path -LiteralPath $uninstallKey)) {
        throw 'The per-user uninstall entry is missing.'
    }
    Write-Output "Installed and verified all $($files.Count) release-bundle files."
} finally {
    $uninstaller = Join-Path $destination 'unins000.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        $arguments = @(
            '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
            ('/LOG="{0}"' -f $uninstallLog)
        )
        $uninstall = Start-Process -FilePath $uninstaller -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        if ($uninstall.ExitCode -ne 0) {
            throw "Uninstaller failed with exit code $($uninstall.ExitCode); see $uninstallLog"
        }
    }
}
if ((Test-Path -LiteralPath (Join-Path $destination 'photosim.exe')) -or
    (Test-Path -LiteralPath $uninstallKey)) {
    throw 'Uninstall did not remove the application and its registration.'
}
foreach ($source in $files) {
    $relative = [IO.Path]::GetRelativePath($bundle, $source.FullName)
    if (Test-Path -LiteralPath (Join-Path $destination $relative)) {
        throw "Uninstall left a release-bundle file behind: $relative"
    }
}
Write-Output 'Silent install/uninstall verification passed.'
