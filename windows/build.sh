#!/usr/bin/env bash
# Build SmartumSwitch for Windows (win-x64, self-contained single exe) on Linux or Windows with .NET 8 SDK.
set -euo pipefail
cd "$(dirname "$0")"
dotnet run -c Release --project SmartumSwitch.Tests            # core tests must pass
dotnet publish SmartumSwitch/SmartumSwitch.csproj -c Release -o publish
rm -f publish/*.pdb
mkdir -p ../dist && cp publish/SmartumSwitch.exe ../dist/SmartumSwitch-win-x64.exe
(cd ../dist && sha256sum SmartumSwitch-win-x64.exe > SmartumSwitch-win-x64.exe.sha256)
