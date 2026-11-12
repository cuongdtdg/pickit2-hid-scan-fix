[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'dist\PICkit 2 HID Fix'
}

$sourceUrl = 'https://ww1.microchip.com/downloads/en/DeviceDoc/PICkit2_PCAppSource_V2_61.zip'
$sourceSha256 = '59278256EED4406A15C5AE0112D69297CCC17634A82BF6A2605B81B75A225C13'
$buildRoot = Join-Path $PSScriptRoot '.build'
$zipPath = Join-Path $buildRoot 'PICkit2_PCAppSource_V2_61.zip'
$extractRoot = Join-Path $buildRoot 'source'

function Replace-ExactlyOnce {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$Old,
        [Parameter(Mandatory)] [string]$New,
        [Parameter(Mandatory)] [string]$Label
    )

    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "Patch anchor not found: $Label"
    }
    if ($Text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Patch anchor is not unique: $Label"
    }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Invoke-WebRequest -Uri $sourceUrl -OutFile $zipPath

$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
if ($actualHash -ne $sourceSha256) {
    throw "Source ZIP hash mismatch. Expected $sourceSha256, got $actualHash."
}

if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}
Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot

$projectRoot = Join-Path $extractRoot 'PICkit2V2\PICkit2V2'
$usbPath = Join-Path $projectRoot 'USB.cs'
$usb = [IO.File]::ReadAllText($usbPath)
$usb = $usb.Replace("`r`n", "`n")

$oldLoop = '            for (int l_loop = 0; l_loop < 20; l_loop++)'
$newLoop = @'
            // Modern Windows systems commonly expose more than 20 HID interfaces.
            // Keep scanning so PICkit 2 is not skipped when it enumerates later.
            for (int l_loop = 0; l_loop < 256; l_loop++)
'@.TrimEnd("`r", "`n")
$usb = Replace-ExactlyOnce $usb $oldLoop $newLoop 'HID scan limit'

$oldPathRead = @'
                    SingledevicePathName = Marshal.PtrToStringAuto(pdevicePathName);
                    l_temp_handle = CreateFile(
'@.TrimEnd("`r", "`n")
$newPathRead = @'
                    SingledevicePathName = Marshal.PtrToStringAuto(pdevicePathName);
                    Marshal.FreeHGlobal(DetailDataBuffer);

                    // Avoid opening unrelated HID interfaces. Some modern HID
                    // devices can block legacy synchronous CreateFile calls.
                    string vidPid = string.Format("vid_{0:x4}&pid_{1:x4}", p_VendorID, p_PoductID);
                    if ((SingledevicePathName == null) ||
                        (SingledevicePathName.IndexOf(vidPid, StringComparison.OrdinalIgnoreCase) < 0))
                    {
                        continue;
                    }
                    l_temp_handle = CreateFile(
'@.TrimEnd("`r", "`n")
$usb = Replace-ExactlyOnce $usb $oldPathRead $newPathRead 'VID/PID path filter'

$oldLoopEnd = @'
                }  // if result == true
            }  // end for
'@.TrimEnd("`r", "`n")
$newLoopEnd = @'
                }  // if result == true
                else
                {
                    // SetupDiEnumDeviceInterfaces reports no more items.
                    // Avoid repeatedly probing empty indexes up to the scan cap.
                    break;
                }
            }  // end for
'@.TrimEnd("`r", "`n")
$usb = Replace-ExactlyOnce $usb $oldLoopEnd $newLoopEnd 'end-of-enumeration break'

[IO.File]::WriteAllText($usbPath, $usb, [Text.UTF8Encoding]::new($false))

$msbuild = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) {
    throw 'The .NET Framework v4 MSBuild executable was not found.'
}

& $msbuild (Join-Path $projectRoot 'PICkit2V2.csproj') /t:Rebuild /p:Configuration=Release /p:Platform=x86 /nologo /verbosity:minimal
if ($LASTEXITCODE -ne 0) {
    throw "MSBuild failed with exit code $LASTEXITCODE."
}

$releaseRoot = Join-Path $projectRoot 'bin\Release'
if (Test-Path -LiteralPath $OutputDirectory) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$files = @(
    'PICkit2V2.exe',
    'PK2DeviceFile.dat',
    'PK2V023200.hex',
    'PICkit 2 Readme.txt',
    'PICkit2 User Guide 51553E.pdf',
    'Logic Tool User Guide.pdf',
    'Programmer-To-Go User Guide.pdf'
)
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path $releaseRoot $file) -Destination (Join-Path $OutputDirectory $file)
}

Write-Host "Build complete: $OutputDirectory"
Get-FileHash -LiteralPath (Join-Path $OutputDirectory 'PICkit2V2.exe') -Algorithm SHA256
