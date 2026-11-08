$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output = Join-Path $root 'out/FAF-Lag-Test-Setup.exe'
New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$package = Join-Path $root 'out/lag-test-engine.zip'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [IO.File]::Open($package, [IO.FileMode]::Create)
$zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @('main_x64.exe', 'dxcompiler.dll', 'dxil.dll')) {
        $path = Join-Path $root "build/clang-x64-release/src/$name"
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $path, $name) | Out-Null
    }
    $hooks = Join-Path $root 'data/fafengine'
    foreach ($file in Get-ChildItem $hooks -Recurse -File) {
        $relative = $file.FullName.Substring($hooks.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, "fafengine/$relative") | Out-Null
    }
} finally { $zip.Dispose(); $stream.Dispose() }
$arguments = @('/nologo', '/target:winexe', '/optimize+', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.Web.Extensions.dll', '/reference:System.IO.Compression.dll', "/resource:$package,engine.zip", "/out:$output", "/win32manifest:$PSScriptRoot/app.manifest")
& $compiler @arguments (Join-Path $PSScriptRoot 'Installer.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$check = Start-Process -FilePath $output -ArgumentList '--verify' -Wait -PassThru -WindowStyle Hidden
if ($check.ExitCode -ne 0) { throw 'Installer payload verification failed.' }
$test = Start-Process -FilePath $output -ArgumentList '--selftest' -Wait -PassThru -WindowStyle Hidden
if ($test.ExitCode -ne 0) { throw "Installer installation test failed: $($test.ExitCode)" }
Get-FileHash -Algorithm SHA256 $output
