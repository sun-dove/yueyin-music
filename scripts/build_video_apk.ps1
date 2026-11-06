param(
    [string]$FlutterSdk,
    [string]$AndroidSdk,
    [string]$Jdk = 'D:/Applications/Java/jdk-17',
    [string]$SigningProperties
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$taskRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
$toolchainsRoot = Join-Path $taskRoot 'work/toolchains'
if (-not $FlutterSdk) { $FlutterSdk = Join-Path $toolchainsRoot 'flutter' }
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $toolchainsRoot 'android-sdk' }
if (-not $SigningProperties) { $SigningProperties = Join-Path $taskRoot 'work/signing/video-music-signing.properties' }
if (-not (Test-Path -LiteralPath $SigningProperties)) { throw '缺少视频同款应用的稳定签名配置' }

$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_USER_HOME = Join-Path $toolchainsRoot 'android-user'
$env:ANDROID_AVD_HOME = Join-Path $toolchainsRoot 'avd'
$env:GRADLE_USER_HOME = Join-Path $toolchainsRoot 'gradle-home'
$env:PUB_CACHE = Join-Path $toolchainsRoot 'pub-cache'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:FLUTTER_ROOT = $FlutterSdk
$env:VIDEO_MUSIC_BUILD = '1'
$env:VIDEO_MUSIC_SIGNING_PROPERTIES = $SigningProperties
$env:PATH = (Join-Path $Jdk 'bin') + ';' + (Join-Path $FlutterSdk 'bin') + ';' + $env:PATH
$gradleInitDirectory = Join-Path $env:GRADLE_USER_HOME 'init.d'
New-Item -ItemType Directory -Path $gradleInitDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'video-mirrors.gradle') -Destination (Join-Path $gradleInitDirectory 'video-mirrors.gradle') -Force
$gradlePropertiesPath = Join-Path $env:GRADLE_USER_HOME 'gradle.properties'
$gradleProperties = if (Test-Path -LiteralPath $gradlePropertiesPath) { @(Get-Content -LiteralPath $gradlePropertiesPath) } else { @() }
if (-not ($gradleProperties -match '^org\.gradle\.jvmargs=')) {
    $gradleProperties += 'org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError'
    $gradleProperties += 'org.gradle.workers.max=2'
}
$distributionUri = [uri]'https://services.gradle.org'
$proxy = [Net.WebRequest]::DefaultWebProxy
if ($proxy -and -not $proxy.IsBypassed($distributionUri)) {
    $proxyUri = $proxy.GetProxy($distributionUri)
    if (-not $proxyUri.UserInfo) {
        foreach ($protocol in @('http', 'https')) {
            $hostKey = 'systemProp.' + $protocol + '.proxyHost='
            $portKey = 'systemProp.' + $protocol + '.proxyPort='
            if (-not ($gradleProperties -match ('^' + [regex]::Escape($hostKey)))) { $gradleProperties += $hostKey + $proxyUri.DnsSafeHost }
            if (-not ($gradleProperties -match ('^' + [regex]::Escape($portKey)))) { $gradleProperties += $portKey + $proxyUri.Port }
        }
    }
}
[IO.File]::WriteAllLines($gradlePropertiesPath, $gradleProperties, [Text.Encoding]::ASCII)

Push-Location $projectRoot
try {
    $dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
    $toolPackages = Join-Path $FlutterSdk 'packages/flutter_tools/.dart_tool/package_config.json'
    & $dart "--packages=$toolPackages" (Join-Path $PSScriptRoot 'generate_android_plugins.dart') $projectRoot
    if ($LASTEXITCODE -ne 0) { throw 'Android 插件注册器生成失败' }
    & (Join-Path $FlutterSdk 'bin/flutter.bat') build apk --release --split-per-abi --no-pub --target lib/main_video.dart
    if ($LASTEXITCODE -ne 0) { throw "视频同款 APK 构建失败，退出码 $LASTEXITCODE" }
} finally {
    Pop-Location
}
