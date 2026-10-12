on run {daemon_file, agent_file, user}

  set prefs_dir to "/Users/" & user & "/Library/Preferences/com.carriez.RustDesk/"
  set prefs_toml to quoted form of (prefs_dir & "RustDesk.toml")
  set prefs2_toml to quoted form of (prefs_dir & "RustDesk2.toml")
  set daemon_plist to "/Library/LaunchDaemons/com.carriez.RustDesk_service.plist"
  set agent_plist to "/Library/LaunchAgents/com.carriez.RustDesk_server.plist"
  set daemon_label to "com.carriez.RustDesk_service"
  set agent_label to "com.carriez.RustDesk_server"

  set sh1 to "echo " & quoted form of daemon_file & " > " & daemon_plist & " && chown root:wheel " & daemon_plist & ";"

  set sh2 to "echo " & quoted form of agent_file & " > " & agent_plist & " && chown root:wheel " & agent_plist & ";"

  set sh3 to "cp -rf " & prefs_toml & " /var/root/Library/Preferences/com.carriez.RustDesk/;"

  set sh4 to "cp -rf " & prefs2_toml & " /var/root/Library/Preferences/com.carriez.RustDesk/;"

  -- Unload any leftover service from a previous install, load the new plist,
  -- then kickstart -k so the old root `service` process is replaced.
  set sh5 to "launchctl bootout system/" & daemon_label & " 2>/dev/null || launchctl unload -w " & daemon_plist & " 2>/dev/null || true; launchctl bootstrap system " & daemon_plist & " 2>/dev/null || launchctl load -w " & daemon_plist & "; launchctl kickstart -k system/" & daemon_label & " 2>/dev/null || true;"

  -- Load the user LaunchAgent in the Aqua session so `--server` starts after login.
  set sh6 to "uid=$(id -u " & quoted form of user & " 2>/dev/null || true); if [ -n \"$uid\" ] && [ \"$uid\" != \"0\" ]; then launchctl bootout gui/$uid/" & agent_label & " 2>/dev/null || launchctl bootout user/$uid/" & agent_label & " 2>/dev/null || true; launchctl bootstrap gui/$uid " & agent_plist & " 2>/dev/null || launchctl bootstrap user/$uid " & agent_plist & " 2>/dev/null || launchctl load -w " & agent_plist & "; launchctl kickstart -k gui/$uid/" & agent_label & " 2>/dev/null || true; else launchctl load -w " & agent_plist & " 2>/dev/null || true; fi;"

  set sh to sh1 & sh2 & sh3 & sh4 & sh5 & sh6

  do shell script sh with prompt "RustDesk wants to install daemon and agent" with administrator privileges
end run
