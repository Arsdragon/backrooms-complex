# Синтез реплик голосами Windows. Аргумент: путь к JSON [{key, lang, text, voice, out}]
param([string]$Json)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null
$all = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices
$items = Get-Content -Raw -Encoding UTF8 $Json | ConvertFrom-Json
$s = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
Add-Type -AssemblyName System.Speech
$sapi = New-Object System.Speech.Synthesis.SpeechSynthesizer
foreach ($it in $items) {
  if ($it.voice -eq 'Zira') {
    $sapi.SelectVoice('Microsoft Zira Desktop')
    $sapi.Rate = [int](($it.rate - 1.0) * 10)
    $sapi.SetOutputToWaveFile($it.out)
    $sapi.Speak($it.text)
    $sapi.SetOutputToNull()
    Write-Output ("ok " + $it.key + " Zira")
    continue
  }
  $v = $all | Where-Object { $_.DisplayName -like ('*' + $it.voice + '*') } | Select-Object -First 1
  if ($v -eq $null) { $v = $all | Where-Object { $_.Language -like ($it.lang + '*') } | Select-Object -First 1 }
  if ($v -ne $null) { $s.Voice = $v }
  $s.Options.SpeakingRate = [double]$it.rate
  $st = Await ($s.SynthesizeTextToStreamAsync($it.text)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
  $r = New-Object Windows.Storage.Streams.DataReader($st.GetInputStreamAt(0))
  $n = Await ($r.LoadAsync([uint32]$st.Size)) ([uint32])
  $b = New-Object byte[] $n
  $r.ReadBytes($b)
  [IO.File]::WriteAllBytes($it.out, $b)
  Write-Output ("ok " + $it.key + " " + $v.DisplayName)
}
