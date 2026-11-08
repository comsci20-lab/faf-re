$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output = Join-Path $root 'out/FAF-Lag-Test-Setup.exe'
New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$arguments = @('/nologo', '/target:winexe', '/optimize+', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', "/out:$output", "/win32manifest:$PSScriptRoot/app.manifest")
foreach ($name in @('lobby.lua', 'connectiontest.lua', 'connectionscore.lua')) {
    $arguments += "/resource:$root/data/fafengine/lua/ui/lobby/$name,$name"
}
& $compiler @arguments (Join-Path $PSScriptRoot 'Installer.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$check = Start-Process -FilePath $output -ArgumentList '--verify' -Wait -PassThru -WindowStyle Hidden
if ($check.ExitCode -ne 0) { throw 'Installer payload verification failed.' }
Get-FileHash -Algorithm SHA256 $output
