#Requires -Version 5.0
<#
.SYNOPSIS
    Simple HTTP File Server with GUI
.DESCRIPTION
    A native PowerShell 5 HTTP server with a Windows Forms GUI
    for selecting and hosting files from a chosen directory.
.NOTES
    Run as Administrator for ports below 1024
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables
$script:HttpListener = $null
$script:ServerJob = $null
$script:IsRunning = $false

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Simple HTTP File Server"
$form.Size = New-Object System.Drawing.Size(500, 320)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Folder path label
$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Location = New-Object System.Drawing.Point(10, 15)
$lblFolder.Size = New-Object System.Drawing.Size(80, 20)
$lblFolder.Text = "Folder Path:"
$form.Controls.Add($lblFolder)

# Folder path textbox
$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = New-Object System.Drawing.Point(90, 12)
$txtFolder.Size = New-Object System.Drawing.Size(300, 20)
$txtFolder.Text = [Environment]::GetFolderPath("MyDocuments")
$form.Controls.Add($txtFolder)

# Browse button
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(400, 10)
$btnBrowse.Size = New-Object System.Drawing.Size(75, 25)
$btnBrowse.Text = "Browse..."
$form.Controls.Add($btnBrowse)

# Port label
$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Location = New-Object System.Drawing.Point(10, 50)
$lblPort.Size = New-Object System.Drawing.Size(80, 20)
$lblPort.Text = "Port:"
$form.Controls.Add($lblPort)

# Port textbox
$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Location = New-Object System.Drawing.Point(90, 47)
$txtPort.Size = New-Object System.Drawing.Size(60, 20)
$txtPort.Text = "8080"
$form.Controls.Add($txtPort)

# Start button
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Location = New-Object System.Drawing.Point(90, 85)
$btnStart.Size = New-Object System.Drawing.Size(100, 30)
$btnStart.Text = "Start Server"
$btnStart.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($btnStart)

# Stop button
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = New-Object System.Drawing.Point(200, 85)
$btnStop.Size = New-Object System.Drawing.Size(100, 30)
$btnStop.Text = "Stop Server"
$btnStop.BackColor = [System.Drawing.Color]::LightCoral
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(10, 130)
$lblStatus.Size = New-Object System.Drawing.Size(470, 20)
$lblStatus.Text = "Status: Stopped"
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblStatus)

# URL label (clickable)
$lblUrl = New-Object System.Windows.Forms.LinkLabel
$lblUrl.Location = New-Object System.Drawing.Point(10, 155)
$lblUrl.Size = New-Object System.Drawing.Size(470, 20)
$lblUrl.Text = ""
$form.Controls.Add($lblUrl)

# Log listbox
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Location = New-Object System.Drawing.Point(10, 185)
$lblLog.Size = New-Object System.Drawing.Size(100, 20)
$lblLog.Text = "Request Log:"
$form.Controls.Add($lblLog)

$lstLog = New-Object System.Windows.Forms.ListBox
$lstLog.Location = New-Object System.Drawing.Point(10, 205)
$lstLog.Size = New-Object System.Drawing.Size(465, 70)
$lstLog.HorizontalScrollbar = $true
$form.Controls.Add($lstLog)

# Timer for updating log
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500

# Log queue for thread-safe logging
$script:LogQueue = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

# MIME types dictionary
$script:MimeTypes = @{
    ".html" = "text/html"
    ".htm"  = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".xml"  = "application/xml"
    ".txt"  = "text/plain"
    ".csv"  = "text/csv"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".webp" = "image/webp"
    ".pdf"  = "application/pdf"
    ".zip"  = "application/zip"
    ".mp3"  = "audio/mpeg"
    ".mp4"  = "video/mp4"
    ".webm" = "video/webm"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
    ".ttf"  = "font/ttf"
}

# Browse button click
$btnBrowse.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select folder to host"
    $folderBrowser.SelectedPath = $txtFolder.Text
    $folderBrowser.ShowNewFolderButton = $false
    
    if ($folderBrowser.ShowDialog() -eq "OK") {
        $txtFolder.Text = $folderBrowser.SelectedPath
    }
})

# Start server button click
$btnStart.Add_Click({
    $folder = $txtFolder.Text
    $port = $txtPort.Text
    
    # Validate folder
    if (-not (Test-Path $folder -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Invalid folder path!", "Error", "OK", "Error")
        return
    }
    
    # Validate port
    if (-not ($port -match '^\d+$') -or [int]$port -lt 1 -or [int]$port -gt 65535) {
        [System.Windows.Forms.MessageBox]::Show("Invalid port number (1-65535)!", "Error", "OK", "Error")
        return
    }
    
    try {
        $script:HttpListener = New-Object System.Net.HttpListener
        $script:HttpListener.Prefixes.Add("http://+:$port/")
        $script:HttpListener.Start()
        
        $script:IsRunning = $true
        $btnStart.Enabled = $false
        $btnStop.Enabled = $true
        $txtFolder.Enabled = $false
        $txtPort.Enabled = $false
        $btnBrowse.Enabled = $false
        
        $lblStatus.Text = "Status: Running"
        $lblStatus.ForeColor = [System.Drawing.Color]::Green
        $lblUrl.Text = "http://localhost:$port/"
        
        $script:LogQueue.Add("$(Get-Date -Format 'HH:mm:ss') - Server started on port $port") | Out-Null
        
        # Start the timer
        $timer.Start()
        
        # Create runspace for async request handling
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = "STA"
        $runspace.ThreadOptions = "ReuseThread"
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable("Listener", $script:HttpListener)
        $runspace.SessionStateProxy.SetVariable("RootPath", $folder)
        $runspace.SessionStateProxy.SetVariable("LogQueue", $script:LogQueue)
        $runspace.SessionStateProxy.SetVariable("MimeTypes", $script:MimeTypes)
        
        $script:PowerShell = [powershell]::Create()
        $script:PowerShell.Runspace = $runspace
        
        $serverScript = {
            param($Listener, $RootPath, $LogQueue, $MimeTypes)
            
            function Get-MimeType {
                param([string]$Extension)
                if ($MimeTypes.ContainsKey($Extension.ToLower())) {
                    return $MimeTypes[$Extension.ToLower()]
                }
                return "application/octet-stream"
            }
            
            function Get-DirectoryListingHtml {
                param([string]$PhysicalPath, [string]$RequestPath, [string]$Root)
                
                $relativePath = $PhysicalPath.Substring($Root.Length).Replace("\", "/")
                if (-not $relativePath) { $relativePath = "/" }
                
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine('<!DOCTYPE html>')
                [void]$sb.AppendLine('<html>')
                [void]$sb.AppendLine('<head>')
                [void]$sb.AppendLine('    <meta charset="UTF-8">')
                [void]$sb.AppendLine("    <title>Index of $relativePath</title>")
                [void]$sb.AppendLine('    <style>')
                [void]$sb.AppendLine('        body { font-family: Consolas, monospace; margin: 20px; background: #1e1e1e; color: #d4d4d4; }')
                [void]$sb.AppendLine('        h1 { color: #569cd6; border-bottom: 1px solid #444; padding-bottom: 10px; }')
                [void]$sb.AppendLine('        table { border-collapse: collapse; width: 100%; }')
                [void]$sb.AppendLine('        th, td { text-align: left; padding: 8px 12px; }')
                [void]$sb.AppendLine('        th { background: #2d2d2d; color: #9cdcfe; }')
                [void]$sb.AppendLine('        tr:hover { background: #2a2a2a; }')
                [void]$sb.AppendLine('        a { color: #4ec9b0; text-decoration: none; }')
                [void]$sb.AppendLine('        a:hover { text-decoration: underline; }')
                [void]$sb.AppendLine('        .folder { color: #dcdcaa; }')
                [void]$sb.AppendLine('        .size { color: #b5cea8; }')
                [void]$sb.AppendLine('        .date { color: #808080; }')
                [void]$sb.AppendLine('    </style>')
                [void]$sb.AppendLine('</head>')
                [void]$sb.AppendLine('<body>')
                [void]$sb.AppendLine("    <h1>Index of $relativePath</h1>")
                [void]$sb.AppendLine('    <table>')
                [void]$sb.AppendLine('        <tr><th>Name</th><th>Size</th><th>Last Modified</th></tr>')
                
                # Parent directory link
                if ($relativePath -ne "/") {
                    $parentPath = Split-Path $RequestPath -Parent
                    if (-not $parentPath -or $parentPath -eq "") { $parentPath = "/" }
                    $parentPath = $parentPath.Replace("\", "/")
                    [void]$sb.AppendLine("        <tr><td><a href=`"$parentPath`" class=`"folder`">[DIR] ..</a></td><td></td><td></td></tr>")
                }
                
                # Directories
                Get-ChildItem -Path $PhysicalPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
                    $name = $_.Name
                    $linkPath = ($RequestPath.TrimEnd("/") + "/" + $name).Replace("//", "/")
                    $date = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    [void]$sb.AppendLine("        <tr><td><a href=`"$linkPath`" class=`"folder`">[DIR] $name/</a></td><td></td><td class=`"date`">$date</td></tr>")
                }
                
                # Files
                Get-ChildItem -Path $PhysicalPath -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
                    $name = $_.Name
                    $linkPath = ($RequestPath.TrimEnd("/") + "/" + $name).Replace("//", "/")
                    $size = if ($_.Length -ge 1MB) { "{0:N2} MB" -f ($_.Length / 1MB) }
                            elseif ($_.Length -ge 1KB) { "{0:N2} KB" -f ($_.Length / 1KB) }
                            else { "$($_.Length) B" }
                    $date = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    [void]$sb.AppendLine("        <tr><td><a href=`"$linkPath`">$name</a></td><td class=`"size`">$size</td><td class=`"date`">$date</td></tr>")
                }
                
                [void]$sb.AppendLine('    </table>')
                [void]$sb.AppendLine('    <hr style="border-color: #444; margin-top: 20px;">')
                [void]$sb.AppendLine('    <p style="color: #666; font-size: 12px;">PowerShell HTTP File Server</p>')
                [void]$sb.AppendLine('</body>')
                [void]$sb.AppendLine('</html>')
                
                return $sb.ToString()
            }
            
            while ($Listener.IsListening) {
                try {
                    $context = $Listener.GetContext()
                    $request = $context.Request
                    $response = $context.Response
                    
                    $requestPath = [System.Uri]::UnescapeDataString($request.Url.LocalPath)
                    
                    # Get client info for logging
                    $clientIP = $request.RemoteEndPoint.Address.ToString()
                    $userAgent = $request.UserAgent
                    # Sanitize user agent: remove control chars, limit length
                    if ($userAgent) {
                        $userAgent = $userAgent -replace '[\x00-\x1F\x7F]', ''
                        if ($userAgent.Length -gt 100) { $userAgent = $userAgent.Substring(0, 100) + '...' }
                    } else {
                        $userAgent = '-'
                    }
                    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $clientIP | $userAgent | $requestPath"
                    $LogQueue.Add($logEntry) | Out-Null
                    
                    # Prevent directory traversal
                    $safePath = $requestPath -replace '\.\.', ''
                    $physicalPath = Join-Path $RootPath $safePath.TrimStart("/")
                    $physicalPath = [System.IO.Path]::GetFullPath($physicalPath)
                    
                    if (-not $physicalPath.StartsWith($RootPath, [StringComparison]::OrdinalIgnoreCase)) {
                        $response.StatusCode = 403
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden")
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        $response.Close()
                        continue
                    }
                    
                    if (Test-Path $physicalPath -PathType Container) {
                        # Check for index.html
                        $indexPath = Join-Path $physicalPath "index.html"
                        if (Test-Path $indexPath) {
                            $content = [System.IO.File]::ReadAllBytes($indexPath)
                            $response.ContentType = "text/html; charset=utf-8"
                            $response.ContentLength64 = $content.Length
                            $response.OutputStream.Write($content, 0, $content.Length)
                        } else {
                            # Directory listing
                            $html = Get-DirectoryListingHtml -PhysicalPath $physicalPath -RequestPath $requestPath -Root $RootPath
                            $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                            $response.ContentType = "text/html; charset=utf-8"
                            $response.ContentLength64 = $buffer.Length
                            $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        }
                    }
                    elseif (Test-Path $physicalPath -PathType Leaf) {
                        $extension = [System.IO.Path]::GetExtension($physicalPath)
                        $mimeType = Get-MimeType -Extension $extension
                        
                        $content = [System.IO.File]::ReadAllBytes($physicalPath)
                        $response.ContentType = $mimeType
                        $response.ContentLength64 = $content.Length
                        $response.OutputStream.Write($content, 0, $content.Length)
                    }
                    else {
                        $response.StatusCode = 404
                        $html = "<html><body><h1>404 - Not Found</h1><p>The requested resource was not found.</p></body></html>"
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                        $response.ContentType = "text/html"
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    
                    $response.Close()
                }
                catch [System.Net.HttpListenerException] {
                    break
                }
                catch {
                    $LogQueue.Add("$(Get-Date -Format 'HH:mm:ss') - Error: $($_.Exception.Message)") | Out-Null
                }
            }
        }
        
        $script:PowerShell.AddScript($serverScript).AddArgument($script:HttpListener).AddArgument($folder).AddArgument($script:LogQueue).AddArgument($script:MimeTypes) | Out-Null
        
        $script:AsyncResult = $script:PowerShell.BeginInvoke()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to start server: $($_.Exception.Message)`n`nTry running as Administrator for ports below 1024.", "Error", "OK", "Error")
        $script:IsRunning = $false
    }
})

# Stop server button click
$btnStop.Add_Click({
    try {
        $timer.Stop()
        
        if ($script:HttpListener) {
            $script:HttpListener.Stop()
            $script:HttpListener.Close()
        }
        
        if ($script:PowerShell) {
            $script:PowerShell.Stop()
            $script:PowerShell.Dispose()
        }
        
        $script:IsRunning = $false
        $btnStart.Enabled = $true
        $btnStop.Enabled = $false
        $txtFolder.Enabled = $true
        $txtPort.Enabled = $true
        $btnBrowse.Enabled = $true
        
        $lblStatus.Text = "Status: Stopped"
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        $lblUrl.Text = ""
        
        $script:LogQueue.Add("$(Get-Date -Format 'HH:mm:ss') - Server stopped") | Out-Null
        
        # Update log one more time
        while ($script:LogQueue.Count -gt 0) {
            $msg = $script:LogQueue[0]
            $script:LogQueue.RemoveAt(0)
            $lstLog.Items.Add($msg)
            if ($lstLog.Items.Count -gt 100) { $lstLog.Items.RemoveAt(0) }
        }
        $lstLog.TopIndex = $lstLog.Items.Count - 1
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Error stopping server: $($_.Exception.Message)", "Error", "OK", "Error")
    }
})

# Timer tick for updating log
$timer.Add_Tick({
    while ($script:LogQueue.Count -gt 0) {
        $msg = $script:LogQueue[0]
        $script:LogQueue.RemoveAt(0)
        $lstLog.Items.Add($msg)
        if ($lstLog.Items.Count -gt 100) { $lstLog.Items.RemoveAt(0) }
    }
    if ($lstLog.Items.Count -gt 0) {
        $lstLog.TopIndex = $lstLog.Items.Count - 1
    }
})

# URL click handler
$lblUrl.Add_LinkClicked({
    Start-Process $lblUrl.Text
})

# Form closing handler
$form.Add_FormClosing({
    if ($script:IsRunning) {
        $btnStop.PerformClick()
    }
})

# Show the form
[void]$form.ShowDialog()
