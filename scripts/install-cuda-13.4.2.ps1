param(
  [Parameter(Mandatory = $true)][string]$CudaDir,
  [Parameter(Mandatory = $true)][string]$Workspace
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'windows-install-helpers.ps1')

# Only populate an isolated SDK tree from NVIDIA's pinned, verified redistributions.
Assert-NoReparseAncestor $CudaDir 'CUDA SDK destination'
Assert-NoReparseAncestor $Workspace 'CUDA download workspace'
if (Test-Path $CudaDir) {
  if (Get-ChildItem $CudaDir -Force | Select-Object -First 1) {
    throw 'CUDA SDK destination must be empty before assembly.'
  }
}
New-Item -ItemType Directory -Force $CudaDir, $Workspace | Out-Null
$manifest = Get-Content (Join-Path $PSScriptRoot 'cuda-13.4.2-windows.json') -Raw | ConvertFrom-Json
foreach ($package in $manifest.packages) {
  $archive = Join-Path $Workspace "$($package.name)-13.4.2.zip"
  $extract = Join-Path $Workspace "$($package.name)-13.4.2-extracted"
  Invoke-WebRequest -UseBasicParsing -Uri (
    'https://developer.download.nvidia.com/compute/cuda/redist/' + $package.relative_path
  ) -OutFile $archive
  if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $package.sha256) {
    throw "CUDA component checksum mismatch: $($package.name)"
  }
  Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
  $roots = @(Get-ChildItem $extract -Directory)
  if ($roots.Count -ne 1) { throw "Unexpected CUDA archive layout: $($package.name)" }
  foreach ($entry in Get-ChildItem $roots[0].FullName -Force) {
    Copy-Item $entry.FullName $CudaDir -Recurse -Force
  }
}
# CUDA 13 moves runtime DLLs to bin/x64; existing build helpers search bin.
$runtimeDir = Join-Path $CudaDir 'bin\x64'
if (Test-Path $runtimeDir) {
  Get-ChildItem $runtimeDir -File | Copy-Item -Destination (Join-Path $CudaDir 'bin') -Force
}
if (-not (Test-MomCudaCompilerSdk $CudaDir)) { throw 'CUDA 13.4.2 SDK assembly is incomplete.' }
& (Join-Path $CudaDir 'bin\nvcc.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'CUDA 13.4.2 compiler failed to start.' }
