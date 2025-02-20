local fs = require "luci.fs"
local http = require "luci.http"
local DISP = require "luci.dispatcher"
local b, form

--Clear the version check log
luci.sys.exec("echo '' > /tmp/amlogic/amlogic_check_plugin.log && sync >/dev/null 2>&1")
luci.sys.exec("echo '' > /tmp/amlogic/amlogic_check_kernel.log && sync >/dev/null 2>&1")

--SimpleForm for Update OpenWrt firmware/kernel
b = SimpleForm("upload", translate("Upload"), nil)
b.description = translate("After uploading [Firmware], [Kernel], [IPK] or [Backup Config], the operation buttons will be displayed.")
b.reset = false
b.submit = false
s = b:section(SimpleSection, "", "")
o = s:option(FileUpload, "")
o.template = "amlogic/other_upload"
um = s:option(DummyValue, "", nil)
um.template = "amlogic/other_dvalue"

local dir, fd
dir = "/tmp/upload/"
nixio.fs.mkdir(dir)
http.setfilehandler(
	function(meta, chunk, eof)
		if not fd then
			if not meta then return end
			if meta and chunk then fd = nixio.open(dir .. meta.file, "w") end
			if not fd then
				um.value = translate("Create upload file error.")
				return
			end
		end
		if chunk and fd then
			fd:write(chunk)
		end
		if eof and fd then
			fd:close()
			fd = nil
			um.value = translate("File saved to") .. ' "/tmp/upload/' .. meta.file .. '"'
		end
	end
)

if luci.http.formvalue("upload") then
	local f = luci.http.formvalue("ulfile")
	if #f <= 0 then
		um.value = translate("No specify upload file.")
	end
end

local function getSizeStr(size)
	local i = 0
	local byteUnits = {' kB', ' MB', ' GB', ' TB'}
	repeat
		size = size / 1024
		i = i + 1
	until(size <= 1024)
    return string.format("%.1f", size) .. byteUnits[i]
end

local inits, attr = {}
for i, f in ipairs(fs.glob("/tmp/upload/*")) do
    attr = fs.stat(f)
    if attr then
        inits[i] = {}
        inits[i].name = fs.basename(f)
        inits[i].mtime = os.date("%Y-%m-%d %H:%M:%S", attr.mtime)
        inits[i].modestr = attr.modestr
        inits[i].size = getSizeStr(attr.size)
        inits[i].remove = 0
        inits[i].ipk = false

        --Check whether the openwrt firmware file
        -- openwrt_s905d_v5.10.16_2021.05.31.1958.img.gz
        if (string.lower(string.sub(fs.basename(f), -7, -1)) == ".img.gz") then
            openwrt_firmware_file = true
        end
        -- openwrt_s905d_n1_R21.7.15_k5.4.134-flippy-62+o.img.xz
        if (string.lower(string.sub(fs.basename(f), -7, -1)) == ".img.xz") then
            openwrt_firmware_file = true
        end
        -- openwrt_s905d_n1_R21.7.15_k5.13.2-flippy-62+.7z
        if (string.lower(string.sub(fs.basename(f), -3, -1)) == ".7z") then
            openwrt_firmware_file = true
        end

        --Check whether the three kernel files
        -- boot-5.10.16-flippy-53+.tar.gz
        if (string.lower(string.sub(fs.basename(f), 1, 5)) == "boot-") then
            boot_file = true
        end
        -- dtb-amlogic-5.10.16-flippy-53+.tar.gz
        if (string.lower(string.sub(fs.basename(f), 1, 12)) == "dtb-amlogic-") then
            dtb_file = true
        end
        -- modules-5.10.16-flippy-53+.tar.gz
        if (string.lower(string.sub(fs.basename(f), 1, 8)) == "modules-") then
            modules_file = true
        end

        --Check whether the backup file
        -- openwrt_config.tar.gz
        if (string.lower(string.sub(fs.basename(f), 1, -1)) == "openwrt_config.tar.gz") then
            backup_config_file = true
        end
    end
end

--SimpleForm for Upload file list
form = SimpleForm("filelist", translate("Upload file list"), nil)
form.reset = false
form.submit = false

description_info = ""
luci.sys.exec("echo '' > /tmp/amlogic/amlogic_check_upfiles.log && sync >/dev/null 2>&1")

if backup_config_file then
    description_info = description_info .. translate("There are config file in the upload directory, and you can restore the config. ")
end

if boot_file and dtb_file and modules_file then
    description_info = description_info .. translate("There are kernel files in the upload directory, and you can replace the kernel.")
    luci.sys.exec("echo 'kernel' > /tmp/amlogic/amlogic_check_upfiles.log && sync >/dev/null 2>&1")
end

if openwrt_firmware_file then
    description_info = description_info .. translate("There are openwrt firmware file in the upload directory, and you can update the openwrt.")
    luci.sys.exec("echo 'firmware' > /tmp/amlogic/amlogic_check_upfiles.log && sync >/dev/null 2>&1")
end

if description_info ~= "" then
    form.description =  ' <span style="color: green"><b> Tip: ' .. description_info .. ' </b></span> '
end

tb = form:section(Table, inits)
nm = tb:option(DummyValue, "name", translate("File name"))
mt = tb:option(DummyValue, "mtime", translate("Modify time"))
ms = tb:option(DummyValue, "modestr", translate("Attributes"))
sz = tb:option(DummyValue, "size", translate("Size"))
btnrm = tb:option(Button, "remove", translate("Remove"))
btnrm.render = function(self, section, scope)
	self.inputstyle = "remove"
	Button.render(self, section, scope)
end
btnrm.write = function(self, section)
	local v = luci.fs.unlink("/tmp/upload/" .. luci.fs.basename(inits[section].name))
	if v then table.remove(inits, section) end
	return v
end

function IsConfigFile(name)
	name = name or ""
	local config_file = string.lower(string.sub(name, 1, -1))
	return config_file == "openwrt_config.tar.gz"
end

function IsIpkFile(name)
	name = name or ""
	local ext = string.lower(string.sub(name, -4, -1))
	return ext == ".ipk"
end

--Add Button for *.ipk
btnis = tb:option(Button, "ipk", translate("Install"))
btnis.template = "amlogic/other_button"
btnis.render = function(self, section, scope)
	if not inits[section] then return false end
	if IsIpkFile(inits[section].name) then
		scope.display = ""
		self.inputtitle = translate("Install")
	elseif IsConfigFile(inits[section].name) then
		scope.display = ""
		self.inputtitle = translate("Restore")
	else
		scope.display = "none"
	end

	self.inputstyle = "apply"
	Button.render(self, section, scope)
end
btnis.write = function(self, section)
    if IsIpkFile(inits[section].name) then
        local r = luci.sys.exec(string.format('opkg --force-reinstall install "/tmp/upload/%s"', inits[section].name))
	local x = luci.sys.exec("rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null")
        form.description = string.format('<span style="color: red">%s</span>', r)
    elseif IsConfigFile(inits[section].name) then
        form.description =  ' <span style="color: green"><b> ' .. translate("Tip: The config is being restored, and it will automatically restart after completion.") .. ' </b></span> '
        local x = luci.sys.exec("chmod +x /usr/bin/openwrt-backup 2>/dev/null")
        local r = luci.sys.exec("/usr/bin/openwrt-backup -r > /tmp/amlogic/amlogic.log && sync 2>/dev/null")
    end
end

--SimpleForm for Check upload files
form:section(SimpleSection).template  = "amlogic/other_upfiles"

return b, form

