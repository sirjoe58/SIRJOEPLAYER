/// Script PowerShell usato su Windows per gestire il Bluetooth:
///  -Action status   -> stato della radio (On/Off/NORADIO)
///  -Action on       -> accende la radio Bluetooth
///  -Action list     -> elenco dispositivi associati (indirizzo|collegato|classe|nome)
///  -Action connect  -> collega il dispositivo audio indicato da -Addr
const kWindowsBtScript = r'''
param([string]$Action = 'status', [string]$Addr = '')
$ErrorActionPreference = 'SilentlyContinue'

$cs = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class SJBT {
  [StructLayout(LayoutKind.Sequential)]
  public struct SYSTEMTIME { public ushort a, b, c, d, e, f, g, h; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct BLUETOOTH_DEVICE_INFO {
    public uint dwSize;
    public ulong Address;
    public uint ulClassofDevice;
    public bool fConnected;
    public bool fRemembered;
    public bool fAuthenticated;
    public SYSTEMTIME stLastSeen;
    public SYSTEMTIME stLastUsed;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)]
    public string szName;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct BLUETOOTH_DEVICE_SEARCH_PARAMS {
    public uint dwSize;
    public bool fReturnAuthenticated;
    public bool fReturnRemembered;
    public bool fReturnUnknown;
    public bool fReturnConnected;
    public bool fIssueInquiry;
    public byte cTimeoutMultiplier;
    public IntPtr hRadio;
  }

  [DllImport("bthprops.cpl", SetLastError = true)]
  static extern IntPtr BluetoothFindFirstDevice(ref BLUETOOTH_DEVICE_SEARCH_PARAMS p, ref BLUETOOTH_DEVICE_INFO info);
  [DllImport("bthprops.cpl", SetLastError = true)]
  static extern bool BluetoothFindNextDevice(IntPtr h, ref BLUETOOTH_DEVICE_INFO info);
  [DllImport("bthprops.cpl")]
  static extern bool BluetoothFindDeviceClose(IntPtr h);
  [DllImport("bthprops.cpl")]
  static extern uint BluetoothSetServiceState(IntPtr hRadio, ref BLUETOOTH_DEVICE_INFO info, ref Guid guid, uint flags);

  static BLUETOOTH_DEVICE_INFO NewInfo() {
    var i = new BLUETOOTH_DEVICE_INFO();
    i.dwSize = (uint)Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_INFO));
    return i;
  }

  public static List<BLUETOOTH_DEVICE_INFO> All() {
    var res = new List<BLUETOOTH_DEVICE_INFO>();
    var p = new BLUETOOTH_DEVICE_SEARCH_PARAMS();
    p.dwSize = (uint)Marshal.SizeOf(typeof(BLUETOOTH_DEVICE_SEARCH_PARAMS));
    p.fReturnAuthenticated = true;
    p.fReturnRemembered = true;
    p.fReturnConnected = true;
    p.fReturnUnknown = false;
    p.fIssueInquiry = false;
    p.cTimeoutMultiplier = 0;
    p.hRadio = IntPtr.Zero;
    var info = NewInfo();
    IntPtr h = BluetoothFindFirstDevice(ref p, ref info);
    if (h == IntPtr.Zero) return res;
    do {
      res.Add(info);
      info = NewInfo();
    } while (BluetoothFindNextDevice(h, ref info));
    BluetoothFindDeviceClose(h);
    return res;
  }

  public static string List() {
    var lines = new List<string>();
    foreach (var d in All()) {
      lines.Add(d.Address.ToString("X12") + "|" + (d.fConnected ? "1" : "0") + "|" + d.ulClassofDevice + "|" + d.szName);
    }
    return string.Join("\n", lines.ToArray());
  }

  static bool Find(ulong a, out BLUETOOTH_DEVICE_INFO found) {
    foreach (var d in All()) {
      if (d.Address == a) { found = d; return true; }
    }
    found = NewInfo();
    return false;
  }

  public static bool IsConnected(string addr) {
    BLUETOOTH_DEVICE_INFO d;
    return Find(Convert.ToUInt64(addr, 16), out d) && d.fConnected;
  }

  public static bool Connect(string addr) {
    ulong a = Convert.ToUInt64(addr, 16);
    BLUETOOTH_DEVICE_INFO d;
    if (!Find(a, out d)) return false;
    if (d.fConnected) return true;
    // Solo il profilo musicale A2DP: il profilo "vivavoce" peggiora l'audio e lo fa scattare.
    Guid[] services = {
      new Guid("0000110b-0000-1000-8000-00805f9b34fb") // AudioSink (A2DP)
    };
    // Disattiva e riattiva i servizi audio: Windows ricollega il dispositivo.
    foreach (var s in services) { var g = s; BluetoothSetServiceState(IntPtr.Zero, ref d, ref g, 0); }
    Thread.Sleep(1500);
    foreach (var s in services) { var g = s; BluetoothSetServiceState(IntPtr.Zero, ref d, ref g, 1); }
    for (int i = 0; i < 24; i++) {
      Thread.Sleep(500);
      if (IsConnected(addr)) return true;
    }
    return false;
  }
}
"@

function Get-BtRadio {
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $script:asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  })[0]
  [Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
  [Windows.Devices.Radios.RadioAccessStatus, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
  [Windows.Devices.Radios.RadioState, Windows.System.Devices, ContentType = WindowsRuntime] | Out-Null
  Await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null
  $radios = Await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
  return ($radios | Where-Object { $_.Kind -eq 'Bluetooth' } | Select-Object -First 1)
}

function Await($WinRtTask, $ResultType) {
  $asTask = $script:asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

switch ($Action) {
  'status' {
    $bt = Get-BtRadio
    if ($bt -eq $null) { 'NORADIO' } else { [string]$bt.State }
  }
  'on' {
    $bt = Get-BtRadio
    if ($bt -eq $null) { 'NORADIO' }
    else {
      if ([string]$bt.State -ne 'On') {
        Await ($bt.SetStateAsync([Windows.Devices.Radios.RadioState]::On)) ([Windows.Devices.Radios.RadioAccessStatus]) | Out-Null
        Start-Sleep -Milliseconds 1500
      }
      $bt = Get-BtRadio
      [string]$bt.State
    }
  }
  'list' {
    Add-Type -TypeDefinition $cs -Language CSharp
    [SJBT]::List()
  }
  'connect' {
    Add-Type -TypeDefinition $cs -Language CSharp
    if ([SJBT]::Connect($Addr)) { 'CONNECTED' } else { 'FAILED' }
  }
}
''';
