$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'import-vcvars.ps1')
Import-MomVcVars64

# Compile only: hosted runners cannot validate a CUDA kernel on NVIDIA hardware.
$probeDir = Join-Path $env:RUNNER_TEMP 'mom-cuda-sdk-probe'
New-Item -ItemType Directory -Force $probeDir | Out-Null
$source = Join-Path $probeDir 'probe.cpp'
@'
#include <sycl/sycl.hpp>
#include <cuda.h>
#include <cuda_runtime.h>
static_assert(CUDA_VERSION == 13040, "Expected CUDA 13.4 headers");
void probe(sycl::queue& q) { q.single_task([] {}); }
'@ | Set-Content $source
& 'C:\Tools\dpcpp\bin\clang++.exe' -std=c++20 -O1 -fsycl `
  '-fsycl-targets=nvidia_gpu_sm_80' "--cuda-path=$env:CUDA_PATH" `
  "-I$env:CUDA_PATH\include" "-I$env:CUDA_PATH\include\cccl" -c $source `
  -o (Join-Path $probeDir 'probe.obj')
if ($LASTEXITCODE -ne 0) { throw 'DPC++ failed to compile with CUDA 13.4.2.' }
