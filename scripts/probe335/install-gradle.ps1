$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Force C:\probe\dl, C:\probe\gradle, C:\probe\gp | Out-Null

if (-not (Test-Path C:\probe\gradle\gradle-8.9)) {
    $zip = 'C:\probe\dl\gradle-8.9-bin.zip'
    Invoke-WebRequest -Uri 'https://services.gradle.org/distributions/gradle-8.9-bin.zip' -OutFile $zip
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    $expected = 'd725d707bfabd4dfdc958c624003b3c80accc03f7037b5122c4b1d0ef15cecab'
    if ($actual -ne $expected) { throw "gradle checksum mismatch: $actual" }
    Expand-Archive $zip -DestinationPath C:\probe\gradle
}

New-Item -ItemType File -Force C:\probe\gp\settings.gradle | Out-Null
Set-Content -Path C:\probe\gp\build.gradle -Encoding ascii -Value @'
tasks.register('jv') {
    doLast {
        println "DAEMON_JVM java.version=${System.getProperty('java.version')} java.home=${System.getProperty('java.home')}"
    }
}
'@

Get-ChildItem C:\probe\gradle | Select-Object -ExpandProperty Name
