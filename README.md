# Start-PktmonPathTrace
Creates an optimized pktmon trace for a VM's network data path. This is done by limiting the components traced and using a MAC address filter for each VM NIC of the target VM.

This is run on the Hyper-V or Azure Local host directly!

1. Download Start-PktmonPathTrace.ps1
2. Unblock the file: `Get-Item <path to>\Start-PktmonPathTrace.ps1 | Unblock-File`
3. Copy the file to the Hyper-V host.
4. Wait for a VM to go into a bad state.
5. Run the script to collect data. Replace the parts in <> with the appropriate details. PowerShell must by run as administrator!

```powershell
CD <path to script>
.\Start-PktmonPathTrace.ps1 -VmName "<vmName>" -SavePath "<put data here>"
```

6. Generate some failing traffic.
7. Go back to the PowerShell console and press 'q' to stop data collection.
8. Upload the data requested in the green text.
