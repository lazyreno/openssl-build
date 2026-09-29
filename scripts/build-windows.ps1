$ErrorActionPreference = 'Stop'
if (!$env:SDK_ARCH -or !$env:OPENSSL_SRC -or !$env:OPENSSL_PREFIX) {
    throw 'SDK_ARCH, OPENSSL_SRC and OPENSSL_PREFIX are required'
}

$target = switch ($env:SDK_ARCH) {
    'arm64' { 'VC-WIN64-ARM' }
    'x64' { 'VC-WIN64A' }
    default { throw "Unsupported Windows SDK architecture: $($env:SDK_ARCH)" }
}
if ($env:SDK_ARCH -eq 'x64' -and !(Get-Command nasm -ErrorAction SilentlyContinue)) {
    throw 'NASM is required to build the Windows x64 OpenSSL SDK'
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path -LiteralPath $vswhere)) { throw "vswhere was not found: $vswhere" }
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) { throw 'Visual Studio C++ build tools were not found' }
$devCmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
if (!(Test-Path -LiteralPath $devCmd)) { throw "VsDevCmd.bat was not found: $devCmd" }
$arch = if ($env:SDK_ARCH -eq 'arm64') { 'arm64' } else { 'x64' }
$hostArch = $arch
$command = @(
    "call `"$devCmd`" -arch=$arch -host_arch=$hostArch",
    "cd /d `"$($env:OPENSSL_SRC)`"",
    "perl Configure $target shared --prefix=`"$($env:OPENSSL_PREFIX)`" --openssldir=C:\\OpenSSL",
    'nmake'
)
if ($env:OPENSSL_RUN_UPSTREAM_TESTS -eq 'true') {
    $command += 'nmake test'
}
$command += 'nmake install_sw'
$command = $command -join ' && '
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "OpenSSL build failed: $target" }
