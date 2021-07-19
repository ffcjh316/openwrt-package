module("luci.controller.rebootschedule", package.seeall)
function index()
	if not nixio.fs.access("/etc/config/rebootschedule") then
		return
	
	entry({"admin", "system", "rebootschedule"}, template("rebootschedule/rebootschedule"), _("定时设置"), 10).leaf = true
end



