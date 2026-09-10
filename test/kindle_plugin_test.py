"""Behavioral regression tests with a minimal KOReader API simulator (requires lupa)."""
from pathlib import Path
from lupa import LuaRuntime
lua = LuaRuntime()
lua.execute('''
local base = {}
function base:new(o) return setmetatable(o or {}, {__index=self}) end
local queue = {}
UI = {queue=queue}
function UI:scheduleIn(delay, fn) queue[fn] = delay end
function UI:unschedule(fn) queue[fn] = nil end
function UI:show() end
function UI:close() end
PS = {}
POWER = {resets=0}
function POWER:resetT1Timeout() self.resets=self.resets+1 end
function POWER:isCharging() return false end
function POWER:isCharged() return false end
local device = {screen={}}
function device:isKindle() return true end
function device:getPowerDevice() return POWER end
HTTP = {}
function HTTP.request(req)
    assert(type(req)=='table' and req.sink)
    req.sink('\\137PNGrest')
    return 1, 200
end
package.preload['device'] = function() return device end
package.preload['ui/uimanager'] = function() return UI end
package.preload['pluginshare'] = function() return PS end
package.preload['socket.http'] = function() return HTTP end
package.preload['ltn12'] = function() return {sink={table=function(t)
    return function(chunk) if chunk then table.insert(t,chunk) end return 1 end
end}} end
package.preload['datastorage'] = function() return {getDataDir=function() return '/tmp' end} end
package.preload['logger'] = function() return {info=function() end,warn=function() end,err=function() end} end
for _, name in ipairs({'ui/widget/container/widgetcontainer','ui/widget/infomessage',
'ui/widget/inputdialog','ui/widget/container/inputcontainer','ui/widget/imagewidget',
'ui/geometry','ui/gesturerange','luasettings','libs/libkoreader-lfs'}) do
    package.preload[name]=function() return base end
end
''')
lua.globals().Plugin = lua.execute((Path(__file__).parents[1]/'KindleDash.koplugin/main.lua').read_text())
lua.execute('''
local d = Plugin:new{auto_on=true}
d.fileExists=function() return true end
assert(d:tryFetch('https://example.test/screen.png') == '\\137PNGrest')
HTTP.request=function() return nil, 'timeout' end
assert(d:tryFetch('https://example.test/screen.png') == nil)
d:armAutoRefresh()
local old = d._auto_timer
d:toggleAutoRefresh()
assert(UI.queue[old] == nil)
d:toggleAutoRefresh()
assert(UI.queue[old] == nil and UI.queue[d._auto_timer])
d:holdAwake(true)
assert(POWER.resets==1 and PS.pause_auto_suspend==true)
local awake = d._awake_tick
assert(UI.queue[awake]==240)
d:onSuspend()
assert(UI.queue[awake]==nil)
d.dash_widget={}
local fetches=0
d.refreshDashboard=function(self) assert(self==d); fetches=fetches+1; return fetches>=2 end
d:onResume()
assert(UI.queue[d._resume_tick]==5)
local retry=d._resume_tick
UI.queue[retry]=nil; retry()
assert(UI.queue[retry]==15)
UI.queue[retry]=nil; retry()
assert(UI.queue[retry]==nil and fetches==2)
d:onCloseWidget()
assert(PS.pause_auto_suspend==nil and UI.queue[d._auto_timer]==nil)
assert(UI.queue[awake]==nil)
print('PASS: HTTPS bytes, network failure, timer cancellation, idle reset, suspend, resume retry, cleanup')
''')

lua.execute('''
local saved = {}
local settings = {}
function settings:readSetting(key) return saved[key] end
function settings:has(key) return saved[key] ~= nil end
function settings:saveSetting(key, value) saved[key] = value end
function settings:flush() end
require('luasettings').open = function() return settings end
G_reader_settings = {readSetting=function() return 'C' end}
local d = Plugin:new{}
d.settingsPath=function() return '/tmp/settings' end
d.cacheDir=function() return '/tmp' end
assert(d:loadLanguage() == 'en' and saved.language == 'en')
d.language='en'
assert(d:loadCloud():match('screen%-en.png$'))
assert(d:tr('刷新看板') == 'Refresh dashboard')
local menus={}; d:addToMainMenu(menus)
assert(menus['0kindledash'].sub_item_table_func()[2].text == 'Refresh dashboard')
d.host='example.test:8787'; d.cloud=d:loadCloud()
assert(d:endpoints()[1].url:match('lang=en$'))
local en_cache=d:cacheImg()
d:setLanguage('zh')
assert(saved.language=='zh' and d.cloud:match('/screen.png$'))
assert(d:cacheImg() ~= en_cache)
assert(menus['0kindledash'].sub_item_table_func()[2].text == '刷新看板')
d.cloud='https://example.test/custom.png'; d:setLanguage('en')
assert(d.cloud=='https://example.test/custom.png')
saved={host='old-device'}
assert(d:loadLanguage()=='zh' and saved.language=='zh')
saved={}; G_reader_settings.readSetting=function() return 'zh_CN' end
assert(d:loadLanguage()=='zh')
print('PASS: English first install, persisted locale, Chinese migration, dynamic menus, custom URLs, separate caches')
''')
