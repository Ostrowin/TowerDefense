# Testy + raport pokrycia Core.
# Użycie:  ./coverage.ps1            (raport HTML: coverage/report/index.html)
#          ./coverage.ps1 -Open      (od razu otwiera raport)
param([switch]$Open)
$ErrorActionPreference = 'Stop'

$results = Join-Path $PSScriptRoot 'coverage/results'
$report  = Join-Path $PSScriptRoot 'coverage/report'
if (Test-Path $results) { Remove-Item $results -Recurse -Force }

dotnet tool restore | Out-Null
dotnet test "$PSScriptRoot/TowerDefense.Core.Tests" --collect:"XPlat Code Coverage" --results-directory $results
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet reportgenerator "-reports:$results/*/coverage.cobertura.xml" "-targetdir:$report" `
    "-assemblyfilters:+TowerDefense.Core" "-reporttypes:Html;TextSummary"
Get-Content (Join-Path $report 'Summary.txt') | Select-Object -First 12

if ($Open) { Start-Process (Join-Path $report 'index.html') }
