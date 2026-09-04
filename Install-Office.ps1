#requires -Version 5.1
[CmdletBinding()]
param([switch]$Preview, [switch]$TextMenu)

$ErrorActionPreference = 'Stop'

$uiStep = 0
$useKeys = -not $TextMenu -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected
$useAnsi = $Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected
$esc = [char]27
$tones = @{Muted='38;2;145;153;168'; Text='38;2;224;229;237'; Accent='38;2;151;182;203'; Focus='48;2;38;50;63;38;2;234;242;249'; Error='38;2;224;155;153'}

function Format-Ui([string]$Text, [string]$Tone = 'Text') {
    if ($useAnsi) { return "$esc[$($tones[$Tone])m$Text$esc[0m" }
    return $Text
}

function Show-Screen([string]$Title, [string]$Subtitle, [string[]]$Rows, [string]$Hint) {
    $width = 76
    try { $width = [Math]::Max(24, [Math]::Min(76, $Host.UI.RawUI.WindowSize.Width - 4)) } catch { }
    $rule = ([string][char]0x2500) * $width
    $stepLabel = if ($uiStep -ge 1 -and $uiStep -le 5) { "ШАГ $uiStep / 5" } else { 'УСТАНОВКА' }
    $lines = @('', (Format-Ui '  NEKO  /  OFFICE' 'Accent'), (Format-Ui "  $rule" 'Muted'),
        '', (Format-Ui "  $stepLabel" 'Muted'), (Format-Ui "  $Title"), (Format-Ui "  $Subtitle" 'Muted'), '')
    $lines += $Rows
    $lines += @('', (Format-Ui "  $rule" 'Muted'), (Format-Ui "  $Hint" 'Muted'), '')
    if ($useKeys) {
        if ($useAnsi) { Write-Host "$esc[H$esc[2J" -NoNewline }
        else { Clear-Host }
    }
    Write-Host ($lines -join "`n")
}

function Read-MenuKey {
    return $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Select-ItemFromMenu($Title, $Items, [string]$Subtitle = '', [switch]$Multiple) {
    $focus = 0
    $chosen = @{}
    if ($Multiple) { for ($i = 0; $i -lt [Math]::Min(3, $Items.Count); $i++) { $chosen[$i] = $true } }
    $notice = ''
    while ($true) {
        $rows = @()
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $marker = if ($Multiple) { if ($chosen.ContainsKey($i)) { '[x]' } else { '[ ]' } } else { '   ' }
            $pointer = if ($useKeys -and $focus -eq $i) { '>' } else { ' ' }
            $label = "  $pointer $marker $($i + 1)  $($Items[$i].Name)  "
            $tone = if ($useKeys -and $focus -eq $i) { 'Focus' } else { 'Text' }
            $rows += Format-Ui $label $tone
            if ($Items[$i].Note) { $rows += Format-Ui "           $($Items[$i].Note)" 'Muted' }
            $rows += ''
        }
        if ($notice) { $rows += Format-Ui "  $notice" 'Error' }
        $hint = if ($useKeys) {
            if ($Multiple) { '↑ ↓  навигация   Пробел  выбор   Enter  далее   Esc  выход' }
            else { '↑ ↓  навигация   Enter  выбрать   Esc  выход' }
        } else {
            if ($Multiple) { 'Номера через запятую · Enter: 1,2,3 · 0: выход' }
            else { 'Введите номер · 0: выход' }
        }
        Show-Screen $Title $Subtitle $rows $hint
        if (-not $useKeys) {
            $answer = Read-Host '  Выбор'
            if ($answer -eq '0') { throw [OperationCanceledException]::new() }
            if ($Multiple -and [string]::IsNullOrWhiteSpace($answer)) { $answer = '1,2,3' }
            $numbers = @($answer -split ',' | ForEach-Object { $_.Trim() })
            $valid = $true
            foreach ($part in $numbers) {
                $number = 0
                if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $Items.Count) { $valid = $false }
            }
            if ($valid -and ($Multiple -or $numbers.Count -eq 1)) {
                return @($numbers | Select-Object -Unique | ForEach-Object { $Items[[int]$_ - 1] })
            }
            $notice = 'Выберите номера из списка.'
            continue
        }
        try { $key = Read-MenuKey }
        catch { $useKeys = $false; continue }
        switch ($key.VirtualKeyCode) {
            27 { throw [OperationCanceledException]::new() }
            38 { $focus = ($focus + $Items.Count - 1) % $Items.Count }
            40 { $focus = ($focus + 1) % $Items.Count }
            36 { $focus = 0 }
            35 { $focus = $Items.Count - 1 }
            32 {
                if ($Multiple) {
                    if ($chosen.ContainsKey($focus)) { $chosen.Remove($focus) } else { $chosen[$focus] = $true }
                    $notice = ''
                }
            }
            13 {
                if (-not $Multiple) { return $Items[$focus] }
                if ($chosen.Count) { return @(0..($Items.Count - 1) | Where-Object { $chosen.ContainsKey($_) } | ForEach-Object { $Items[$_] }) }
                $notice = 'Выберите хотя бы одно приложение.'
            }
        }
    }
}

function Assert-MicrosoftSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Не удалось подтвердить цифровую подпись Microsoft: $Path"
    }
}

try {
    $uiStep = 1
    $product = Select-ItemFromMenu 'Какой Office установим?' @(
        @{Name='Microsoft 365 · Корпоративный'; Note='Подписка Apps for enterprise'; Id='O365ProPlusRetail'; Channel='Current'},
        @{Name='Microsoft 365 · Для бизнеса'; Note='Подписка Apps for business'; Id='O365BusinessRetail'; Channel='Current'},
        @{Name='Office LTSC 2024 · Professional Plus'; Note='Корпоративная лицензия'; Id='ProPlus2024Volume'; Channel='PerpetualVL2024'},
        @{Name='Office LTSC 2024 · Standard'; Note='Корпоративная лицензия'; Id='Standard2024Volume'; Channel='PerpetualVL2024'}
    ) 'Выберите редакцию, соответствующую вашей лицензии.'
    $apps = @('Word', 'Excel', 'PowerPoint', 'Outlook', 'OneNote')
    if ($product.Id -ne 'Standard2024Volume') { $apps += 'Access' }
    $uiStep = 2
    $appItems = @($apps | ForEach-Object { @{Name=$_} })
    $selected = @(Select-ItemFromMenu 'Только нужные приложения' $appItems 'Word, Excel и PowerPoint уже отмечены.' -Multiple | ForEach-Object { $_.Name })
    $uiStep = 3
    $language = Select-ItemFromMenu 'Язык приложений' @(
        @{Name='Русский'; Id='ru-ru'}, @{Name='English'; Id='en-us'}
    ) 'Язык меню и инструментов внутри Office.'
    $architectures = @(@{Name='64 бита'; Note='Рекомендуется для большинства компьютеров'; Id='64'}, @{Name='32 бита'; Note='Для совместимости со старыми надстройками'; Id='32'})
    if (-not [Environment]::Is64BitOperatingSystem) { $architectures = @(@{Name='32 бита'; Id='32'}) }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        $architectures = @(@{Name='64 бита'; Id='64'})
    }
    $uiStep = 4
    $architecture = Select-ItemFromMenu 'Разрядность Office' $architectures 'Выберите подходящий вариант для этого компьютера.'
    $excluded = @('Word','Excel','PowerPoint','Outlook','OneNote','Access','Publisher','Lync','Groove','OneDrive','Teams','OutlookForWindows') |
        Where-Object { $_ -notin $selected }
    $excludeXml = ($excluded | ForEach-Object { '      <ExcludeApp ID="{0}" />' -f $_ }) -join "`r`n"
    $xml = @"
<Configuration>
  <Add OfficeClientEdition="$($architecture.Id)" Channel="$($product.Channel)">
    <Product ID="$($product.Id)">
      <Language ID="$($language.Id)" />
$excludeXml
    </Product>
  </Add>
  <Display Level="Full" AcceptEULA="FALSE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="FALSE" />
  <Updates Enabled="TRUE" />
</Configuration>
"@
    # Parse before writing or invoking the installer.
    $null = [xml]$xml
    $uiStep = 5
    $summary = @((Format-Ui "  $($product.Name)"), '',
        (Format-Ui "  Язык         $($language.Name)"), (Format-Ui "  Разрядность  $($architecture.Name)"), '',
        (Format-Ui '  ПРИЛОЖЕНИЯ' 'Muted'))
    $summary += @($selected | ForEach-Object { Format-Ui "  + $_" 'Accent' })
    Show-Screen 'Всё готово к установке' 'Проверьте выбранные параметры.' $summary 'Источник: Microsoft · Активация по вашей лицензии'
    if ($Preview) {
        Write-Output $xml
        return
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Откройте PowerShell от имени администратора и запустите команду ещё раз.'
    }
    # This version targets clean OS installations. Avoid modifying an existing Office suite.
    $c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $uninstall = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $existing = @(Get-ItemProperty -Path $uninstall -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Microsoft (Office|365|Visio|Project)' })
    if ((Test-Path $c2r) -or $existing.Count -gt 0) {
        throw 'На компьютере уже есть Office, Visio или Project. Эта версия предназначена для чистой установки. Сначала настройте или удалите существующий пакет.'
    }
    Write-Host (Format-Ui '  Введите INSTALL для установки. Enter — отмена.' 'Muted')
    if ((Read-Host '  Подтверждение') -cne 'INSTALL') { Write-Host '  Установка отменена.'; return }
    $uiStep = 6
    Show-Screen 'Устанавливаем Office' 'Это может занять несколько минут.' @() 'Дождитесь завершения установщика Microsoft.'
    $runDir = Join-Path $env:LOCALAPPDATA ('OfficeInstaller\' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $runDir -Force
    $configPath = Join-Path $runDir 'configuration.xml'
    [IO.File]::WriteAllText($configPath, $xml, (New-Object Text.UTF8Encoding($false)))
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Host (Format-Ui '  1 / 3  Получаем установщик Microsoft' 'Accent')
    $page = Invoke-WebRequest 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -UseBasicParsing -TimeoutSec 60
    $links = [regex]::Matches($page.Content, 'https://download\.microsoft\.com/[^"\s<>]+?\.exe')
    $downloadUrl = @($links | ForEach-Object { $_.Value } | Where-Object { $_ -match '/officedeploymenttool_[^/]+\.exe$' } | Select-Object -Unique)
    if ($downloadUrl.Count -ne 1) {
        throw 'Не удалось найти ссылку на установщик. Возможно, Microsoft изменила страницу загрузки: https://www.microsoft.com/en-us/download/details.aspx?id=49117'
    }
    $package = Join-Path $runDir 'odt.exe'
    Invoke-WebRequest $downloadUrl[0] -OutFile $package -UseBasicParsing -TimeoutSec 300
    Assert-MicrosoftSignature $package
    $process = Start-Process -FilePath $package -ArgumentList "/quiet /extract:`"$runDir`"" -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Не удалось распаковать установщик Microsoft. Код: $($process.ExitCode)" }
    $setup = Join-Path $runDir 'setup.exe'
    Assert-MicrosoftSignature $setup
    Write-Host (Format-Ui '  2 / 3  Подписи Microsoft проверены' 'Muted')
    Write-Host (Format-Ui '  3 / 3  Скачиваем и устанавливаем приложения' 'Accent')
    Write-Host (Format-Ui "  Конфигурация: $configPath" 'Muted')
    $process = Start-Process -FilePath $setup -ArgumentList "/configure `"$configPath`"" -Wait -PassThru
    if ($process.ExitCode -eq 3010) { Write-Host (Format-Ui "`n  Готово. Перезагрузите Windows." 'Accent') }
    elseif ($process.ExitCode -eq 0) { Write-Host (Format-Ui "`n  Office установлен." 'Accent') }
    else { throw "Установщик Office вернул код $($process.ExitCode). Подробности — в окне установщика и журналах %TEMP%." }
    Write-Host (Format-Ui '  Откройте приложение и активируйте Office своей лицензией.' 'Muted')
} catch [OperationCanceledException] {
    Write-Host (Format-Ui "`n  Установка отменена." 'Muted')
} catch {
    Write-Host (Format-Ui "`n  Не удалось продолжить" 'Error')
    Write-Host (Format-Ui "  $($_.Exception.Message)" 'Muted')
    # Do not terminate the user's PowerShell session when launched through iex.
}
