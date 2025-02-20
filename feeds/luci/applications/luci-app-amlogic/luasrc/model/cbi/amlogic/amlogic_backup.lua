local fs = require "luci.fs"
local http = require "luci.http"
local DISP = require "luci.dispatcher"
local b, c

--SimpleForm for Backup Config
b = SimpleForm("backup", translate("Backup Firmware Config"), nil)
b.description = translate("Backup firmware config (openwrt_config.tar.gz). Use this file to restore the config in [Manually Upload Update].")
b.reset = false
b.submit = false
s = b:section(SimpleSection, "", "")
o = s:option(Button, "", translate("Backup Config:"))
o.template = "amlogic/other_button"
um = s:option(DummyValue, "", nil)
um.template = "amlogic/other_dvalue"
o.render = function(self, section, scope)
	self.section = true
	scope.display = ""
	self.inputtitle = translate("Download Backup")
	self.inputstyle = "save"
	Button.render(self, section, scope)
end
o.write = function(self, section, scope)

	local x = luci.sys.exec("chmod +x /usr/bin/openwrt-backup 2>/dev/null")
	local r = luci.sys.exec("/usr/bin/openwrt-backup -b > /tmp/amlogic/amlogic.log && sync 2>/dev/null")

	local sPath, sFile, fd, block
	sPath = "/.reserved/openwrt_config.tar.gz"
	sFile = nixio.fs.basename(sPath)
	if luci.fs.isdirectory(sPath) then
		fd = io.popen('tar -C "%s" -cz .' % {sPath}, "r")
		sFile = sFile .. ".tar.gz"
	else
		fd = nixio.open(sPath, "r")
	end
	if not fd then
		um.value = translate("Couldn't open file:") .. sPath
		return
	else
        um.value = translate("The file Will download automatically.") .. sPath
	end

	http.header('Content-Disposition', 'attachment; filename="%s"' % {sFile})
	http.prepare_content("application/octet-stream")
	while true do
		block = fd:read(nixio.const.buffersize)
		if (not block) or (#block ==0) then
			break
		else
			http.write(block)
		end
	end
	fd:close()
	http.close()
end

-- SimpleForm for Create Snapshot
c = SimpleForm("snapshot", translate("Snapshot Management"), nil)
c.description = translate("Create a snapshot of the current system configuration, or restore to a snapshot.")
c.reset = false
c.submit = false
d = c:section(SimpleSection, "", nil)
w = d:option(Button, "", "")
w.template = "amlogic/other_button"
w.render = function(self, section, scope)
	self.section = true
	scope.display = ""
	self.inputtitle = translate("Create Snapshot")
	self.inputstyle = "save"
	Button.render(self, section, scope)
end
w.write = function(self, section, scope)
    local x = luci.sys.exec("btrfs subvolume snapshot -r /etc /.snapshots/etc-" .. os.date("%m.%d.%H%M%S") .. " 2>/dev/null && sync")
    http.redirect(DISP.build_url("admin", "system", "amlogic", "backup"))
end
w = d:option(TextValue, "snapshot_list", nil)
w.template = "amlogic/other_snapshot"

return b, c

