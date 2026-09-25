<#
Eksport APK na Androida i (opcjonalnie) wgranie na telefon przez adb (debugowanie USB).

  .\tools\android.ps1              # eksport release + instalacja + start gry
  .\tools\android.ps1 -DebugBuild  # szablon debug zamiast release
  .\tools\android.ps1 -NoInstall   # tylko eksport do export\TowerDefense.apk
  .\tools\android.ps1 -SkipExport  # wgraj i uruchom istniejący APK bez eksportu
  .\tools\android.ps1 -Log         # po starcie pokazuje log gry (Ctrl+C kończy)
  .\tools\android.ps1 -Bench       # zamiast gry benchmark tests/perf_test.gd na telefonie (wynik w logu)
  .\tools\android.ps1 -Bench -BenchArgs '--map','0','--minutes','5'
  .\tools\android.ps1 -Bench -BenchScript res://tests/render_probe.gd   # koszt warstw renderu

APK jest podpisany kluczem debug (%APPDATA%\Godot\keystores\debug.keystore, tworzonym przy
pierwszym uruchomieniu) — wystarczy do wgrywania na własny telefon, nie do Google Play.
Ścieżki do Godota, Android SDK i JDK można nadpisać zmiennymi GODOT, ANDROID_HOME, JAVA_HOME.
#>
param(
    [switch]$DebugBuild,
    [switch]$NoInstall,
    [switch]$Log,
    [switch]$Bench,
    [string[]]$BenchArgs = @('--map', '2', '--minutes', '10'),
    [string]$BenchScript = 'res://tests/perf_test.gd',
    [switch]$SkipExport
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$package = 'pl.towerdefense.game'

$godot = if ($env:GODOT) { $env:GODOT } else {
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
}
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'C:\Program Files (x86)\Android\android-sdk' }
$jdk = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'C:\Program Files\Android\openjdk\jdk-21.0.8' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
foreach ($p in @($godot, $sdk, $jdk)) {
    if (-not (Test-Path $p)) { throw "Nie znaleziono: $p" }
}

# Klucz debug (standardowe androiddebugkey / android). Godot tworzy go sam w edytorze,
# ale eksport z wiersza poleceń na świeżej maszynie może go jeszcze nie mieć.
$keystore = "$env:APPDATA\Godot\keystores\debug.keystore"
if (-not (Test-Path $keystore)) {
    New-Item -ItemType Directory -Force (Split-Path $keystore) | Out-Null
    & "$jdk\bin\keytool.exe" -genkeypair -keyalg RSA -keysize 2048 -validity 10000 -alias androiddebugkey `
        -keypass android -storepass android -keystore $keystore -deststoretype pkcs12 `
        -dname 'CN=Android Debug,O=Android,C=US' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'keytool nie utworzył klucza debug' }
}

# Godot czyta ścieżki SDK/JDK i klucze ze zmiennych środowiskowych (bez grzebania w ustawieniach edytora).
$env:ANDROID_HOME = $sdk
$env:JAVA_HOME = $jdk
foreach ($kind in @('DEBUG', 'RELEASE')) {
    Set-Item "env:GODOT_ANDROID_KEYSTORE_${kind}_PATH" $keystore
    Set-Item "env:GODOT_ANDROID_KEYSTORE_${kind}_USER" 'androiddebugkey'
    Set-Item "env:GODOT_ANDROID_KEYSTORE_${kind}_PASSWORD" 'android'
}

$apk = Join-Path $root 'export\TowerDefense.apk'
New-Item -ItemType Directory -Force (Split-Path $apk) | Out-Null

# Eksport. $ExtraArgs trafiają na stałe do APK (command_line/extra_args) — Android ignoruje
# parametry podane przy starcie przez `am start`, więc benchmark musi mieć je wbudowane.
function Export-Apk([string]$ExtraArgs = '') {
    $presets = Join-Path $root 'export_presets.cfg'
    $original = [IO.File]::ReadAllText($presets)
    try {
        if ($ExtraArgs) {
            $patched = $original -replace 'command_line/extra_args=".*"', "command_line/extra_args=`"$ExtraArgs`""
            [IO.File]::WriteAllText($presets, $patched)
        }
        $mode = if ($DebugBuild) { '--export-debug' } else { '--export-release' }
        Write-Host "Eksport ($mode$(if ($ExtraArgs) { ", $ExtraArgs" }))..."
        Remove-Item $apk -ErrorAction SilentlyContinue
        $out = & $godot --headless --path $root $mode 'Android' $apk 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $apk)) {
            $out | Where-Object { "$_".Trim() -and "$_" -notmatch '^\[' } | Write-Host
            throw "Eksport nie powiódł się (kod $LASTEXITCODE)"
        }
        Write-Host ("APK: {0} ({1:N1} MB)" -f $apk, ((Get-Item $apk).Length / 1MB))
    } finally {
        if ($ExtraArgs) { [IO.File]::WriteAllText($presets, $original) }
    }
}

function Install-Apk {
    $devices = & $adb devices | Select-String '\tdevice$'
    if (-not $devices) { throw 'Brak telefonu: podłącz kabel, włącz debugowanie USB i zaakceptuj pytanie na ekranie telefonu.' }
    Write-Host 'Instalacja...'
    # bez instalacji przyrostowej — ta trzyma APK otwarty i blokuje następny eksport
    & $adb install --no-incremental -r $apk | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'adb install nie powiódł się' }
}

# Zablokowany telefon zamraża grę, a eksport i instalacja trwają dość długo, żeby ekran zgasł.
function Wait-Unlocked {
    & $adb shell input keyevent KEYCODE_WAKEUP | Out-Null
    $warned = $false
    while ($true) {
        $state = (& $adb shell 'dumpsys power | grep mWakefulness=; dumpsys window | grep isKeyguardShowing') -join ' '
        if ($state -match 'Awake' -and $state -match 'isKeyguardShowing=false') { return }
        if (-not $warned) { Write-Host 'Odblokuj telefon — benchmark ruszy sam.'; $warned = $true }
        Start-Sleep -Seconds 2
    }
}

function Start-Game {
    $activity = (& $adb shell cmd package resolve-activity --brief $package | Select-Object -Last 1).Trim()
    & $adb logcat -c
    & $adb shell am start -S -n $activity | Out-Null
}

if ($Bench) {
    Export-Apk ((@('--', '--bench', $BenchScript) + $BenchArgs) -join ' ')
    Install-Apk
    Wait-Unlocked
    Start-Game
    Write-Host "Benchmark $BenchScript trwa — nie dotykaj telefonu (ekran musi być włączony)."
    # skrypt sam kończy grę; czekamy na koniec i wypisujemy jego log
    # (skrypty wypisują na końcu „[bench] koniec"; limit 30 min na wypadek zawieszenia)
    $deadline = (Get-Date).AddMinutes(30)
    do {
        Start-Sleep -Seconds 3
        $done = & $adb logcat -d -s godot:I | Select-String '\[bench\] koniec' -Quiet
    } while (-not $done -and (& $adb shell pidof $package) -and (Get-Date) -lt $deadline)
    & $adb logcat -d -s godot:I | Where-Object { $_ -notmatch 'Godot Engine v|OpenGL API|godot\s+:\s*$' }
    Write-Host 'Przywracam zwykłą grę na telefonie...'
    Export-Apk
    Install-Apk
    return
}

if (-not $SkipExport) { Export-Apk }
if ($NoInstall) { return }
Install-Apk
Start-Game
if ($Log) { & $adb logcat -s godot:I }
