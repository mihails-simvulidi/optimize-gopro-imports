# optimize-gopro-imports
PowerShell script which deletes unnecessary files having extensions .LRV and .THM from the GoPro imports directory and also deletes the oldest videos when there is low disk space.

Parameters:
1. **ImportPath** (required) — path of the directory containing imported files.
1. **MinimumFreeBytes** (default: 1GB) — delete the oldest videos if free disk space is below this.
1. **LogFilePath** (default: directory Logs in working directory)
