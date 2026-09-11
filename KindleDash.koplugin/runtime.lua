-- Reliability, diagnostics and opt-in power controls. All state stays on device.
return function(Dash, plugin_dir)
local UI = require('ui/uimanager')
local Device = require('device')
local Info = require('ui/widget/infomessage')
local InputDialog = require('ui/widget/inputdialog')
local Settings = require('luasettings')
local JSON = require('json')
local Network = require('ui/network/manager')
local RenderImage = require('ui/renderimage')
local sha256 = dofile(plugin_dir .. 'sha256.lua')
local http = require('socket.http')
local VERSION = '0.2.0'
local MAX_IMAGE = 4 * 1024 * 1024
local function resolve(base, value)
    if type(value) ~= 'string' then return nil end
    if value:match('^https?://') then
        if base:match('^https://') and not value:match('^https://') then return nil end
        return value
    end
    if value:sub(1,2)=='//' or value:find('..',1,true) then return nil end
    if value:sub(1,1)=='/' then return base:match('^(https?://[^/]+)') .. value end
    return base:match('^(.*)/') .. '/' .. value
end
function Dash:label(en, zh) return self.language == 'en' and en or zh end
function Dash:preferences()
    return Settings:open(self:settingsPath())
end
function Dash:option(key, default)
    local v = self:preferences():readSetting(key)
    if v == nil then return default end
    return v
end
function Dash:setOption(key, value)
    local s=self:preferences(); s:saveSetting(key,value); s:flush()
end
function Dash:record(event, detail)
    self:ensureCacheDir()
    local path=self:cacheDir() .. '/kindledash-health.json'
    local history=self._health_history or {}
    local power=Device:getPowerDevice()
    local ok,battery=pcall(function() return power:getCapacity() end)
    history[#history+1]={at=os.time(),event=event,detail=tostring(detail or ''):sub(1,240),battery=ok and battery or nil}
    while #history>192 do table.remove(history,1) end
    self._health_history=history
    local f=io.open(path..'.tmp','wb')
    if f then f:write(JSON.encode(history)); f:close(); os.rename(path..'.tmp',path) end
end
function Dash:request(url, limit)
    if not url:match('^https?://') then return nil,'Unsupported URL' end
    local chunks,bytes={},0
    local req={url=url,method='GET',redirect=false,headers={['User-Agent']='ShawnKanban/'..VERSION},
        sink=function(chunk)
            if chunk then
                bytes=bytes+#chunk
                if bytes>limit then return nil,'Response exceeds size limit' end
                chunks[#chunks+1]=chunk
            end
            return 1
        end}
    if url:match('^https://') then
        local ca=require('datastorage'):getDataDir()..'/ca-bundle.crt'
        if not self:fileExists(ca) then return nil,'CA bundle missing' end
        req.cafile,req.verify,req.protocol=ca,'peer','tlsv1_2'
    end
    local ok,result,status=pcall(http.request,req)
    if not ok or not result or tonumber(status)~=200 then return nil,'HTTP/network: '..tostring(status or result) end
    if bytes>limit then return nil,'Response exceeds size limit' end
    return table.concat(chunks)
end
function Dash:manifestUrl(image)
    if image:match('%.json$') then return image end
    if image:match('/api/screen') then return image:gsub('/api/screen','/api/display') end
    if image:match('^https://shenliucn%-prog%.github%.io/shawn%-kanban/') then
        if image:match('/screen%-en%.png$') then return image:gsub('screen%-en.png$','en/manifest.json') end
        return image:gsub('screen.png$','manifest.json')
    end
end
function Dash:readMetadata()
    local f=io.open(self:cacheImg()..'.json','rb')
    if not f then return {} end
    local text=f:read('*a');f:close()
    local ok,value=pcall(JSON.decode,text)
    return ok and type(value)=='table' and value or {}
end
function Dash:fetchScreen()
    local failures={}
    for _,ep in ipairs(self:endpoints()) do
        local manifest_url=self:manifestUrl(ep.url)
        local meta,url={},ep.url
        local error_message
        if manifest_url then
            local raw,err=self:request(manifest_url,128*1024)
            local ok,value=pcall(JSON.decode,raw or '')
            if not ok or type(value)~='table' or value.schemaVersion~=1
                or type(value.sha256)~='string' or not value.sha256:match('^%x+$') or #value.sha256~=64
                or type(value.generatedAt)~='number' or value.generatedAt<=0
                or value.generatedAt>os.time()*1000+300000 then
                error_message=err or 'Invalid manifest'
            else
                meta=value; url=resolve(manifest_url,value.image_url)
                if not url then error_message='Invalid image URL' end
            end
        end
        if not error_message then
            local old=self:readMetadata()
            if meta.sha256 and old.sha256==meta.sha256 and self:fileExists(self:cacheImg()) then
                local f=io.open(self:cacheImg(),'rb'); local bytes=f and f:read(MAX_IMAGE+1);if f then f:close() end
                if bytes and #bytes<=MAX_IMAGE and sha256(bytes)==meta.sha256 then
                    self._candidate_meta=meta
                    return bytes,nil,ep.name,true
                end
            end
            local body,err=self:request(url,MAX_IMAGE)
            if body and body:sub(1,8)=='\137PNG\13\10\26\10' then
                if not meta.sha256 or sha256(body)==meta.sha256:lower() then
                    meta.sha256=sha256(body)
                    meta.source=ep.name
                    self._candidate_meta=meta
                    return body,nil,ep.name,false
                end
                error_message='Image checksum mismatch'
            else error_message=err or 'Invalid PNG' end
        end
        failures[#failures+1]=ep.name..': '..tostring(error_message)
    end
    return nil,table.concat(failures,'; ')
end
function Dash:writePng(path, bytes)
    if #bytes>MAX_IMAGE or #bytes<33 then return nil,'Image size invalid' end
    local function uint(offset)
        local a,b,c,d=bytes:byte(offset,offset+3)
        return ((a*256+b)*256+c)*256+d
    end
    if bytes:sub(1,8)~='\137PNG\13\10\26\10' or bytes:sub(13,16)~='IHDR'
        or uint(17)>4096 or uint(21)>4096 then return nil,'Invalid PNG header' end
    self:ensureCacheDir()
    local tmp=path..'.pending'
    local f,err=io.open(tmp,'wb');if not f then return nil,err end
    local written=f:write(bytes);local closed=f:close()
    if not written or not closed then os.remove(tmp);return nil,'Cache write failed' end
    local ok,buffer=pcall(RenderImage.renderImageFile,RenderImage,tmp,false)
    if not ok or not buffer then os.remove(tmp);return nil,'Image decode failed' end
    local w,h=buffer:getWidth(),buffer:getHeight();buffer:free()
    if w<100 or h<100 or w>4096 or h>4096 then os.remove(tmp);return nil,'Invalid dimensions' end
    local meta=self._candidate_meta or {}
    if (meta.width and meta.width~=w) or (meta.height and meta.height~=h) then
        os.remove(tmp);return nil,'Manifest dimensions mismatch'
    end
    local renamed,rename_error=os.rename(tmp,path)
    if not renamed then os.remove(tmp);return nil,rename_error end
    meta.downloadedAt=os.time()*1000
    local mf=io.open(path..'.json.tmp','wb')
    if mf then mf:write(JSON.encode(meta));mf:close();os.rename(path..'.json.tmp',path..'.json') end
    return true
end
function Dash:showDashboard(path, offline)
    local previous=self.dash_widget
    local ok,err=pcall(self.buildScreen,self,path,Device.screen:getWidth(),Device.screen:getHeight())
    if not ok then
        self.dash_widget=previous
        self._last_error='Display failed: '..tostring(err)
        self:record('display_failed',self._last_error)
        return false
    end
    if previous then UI:close(previous) end
    return true
end
local function fmt(t) return t and os.date('%Y-%m-%d %H:%M:%S',t) or '—' end
function Dash:showStatus()
    local m=self:readMetadata()
    local age=m.generatedAt and math.max(0,math.floor((os.time()*1000-m.generatedAt)/60000))
    local text=self:label('Device status','设备状态')..' · '..VERSION..'\n'
        ..self:label('Screen: ','屏幕：')..Device.screen:getWidth()..' × '..Device.screen:getHeight()..'\n'
        ..self:label('Source: ','图源：')..tostring(self._source or m.source or '—')..'\n'
        ..self:label('Content generated: ','内容生成：')..fmt(m.generatedAt and m.generatedAt/1000)..'\n'
        ..self:label('Cloud state: ','云端状态：')..tostring(m.state or 'Unknown / 未知')..'\n'
        ..self:label('Freshness: ','新鲜度：')..(not age and self:label('Unknown','未知') or age>45 and self:label('Stale','已过期') or self:label('Within 45 minutes','45分钟内'))..'\n'
        ..self:label('Age (min): ','内容年龄（分钟）：')..tostring(age or 'Unknown / 未知')..'\n'
        ..self:label('Downloaded: ','下载时间：')..fmt(m.downloadedAt and m.downloadedAt/1000)..'\n'
        ..self:label('Last attempt: ','最近尝试：')..fmt(self._last_attempt)..'\n'
        ..self:label('Next attempt: ','下次尝试：')..fmt(self._next_attempt)..'\n'
        ..self:label('Last error: ','最近错误：')..tostring(self._last_error or '—')..'\n'
        ..self:label('Health log: settings/kindledash-health.json','诊断记录：settings/kindledash-health.json')
    UI:show(Info:new{text=text})
end
function Dash:retryDelay()
    return math.min(1800,60*2^math.min((self._failures or 1)-1,5))
end
function Dash:nextDelay()
    local interval=tonumber(self:option('interval',1800)) or 1800
    interval=math.max(300,math.min(86400,interval))
    if self:option('night_mode',false) then
        local hour=os.date('*t').hour
        if hour>=23 or hour<7 then interval=math.max(interval,7200) end
    end
    return interval-os.time()%interval
end
function Dash:armAutoRefresh(delay)
    if self._auto_timer then UI:unschedule(self._auto_timer) end
    if not self.auto_on then self._next_attempt=nil;return end
    delay=delay or self:nextDelay()
    self._next_attempt=os.time()+delay
    self._auto_timer=function()
        self._next_attempt=nil
        if self.dash_widget and not self._suspended then self:requestRefresh(true,false)
        else self:armAutoRefresh() end
    end
    UI:scheduleIn(delay,self._auto_timer)
end
function Dash:requestRefresh(silent,manual)
    if self._busy or self._suspended then return end
    self._busy=true
    self._last_attempt=os.time()
    local generation=(self._generation or 0)+1;self._generation=generation
    local started_wifi=false
    local released=false
    local function release()
        if released then return end
        released=true
        if started_wifi and self:option('wifi_off',false) then pcall(Network.disableWifi,Network) end
    end
    self._release_wifi=release
    local function finish(ok,err)
        if generation~=self._generation then release();return end
        self._busy=false
        if self._network_deadline then UI:unschedule(self._network_deadline) end
        if ok then self._last_error=nil else self._last_error=tostring(err or 'Refresh failed') end
        self._failures=ok and 0 or (self._failures or 0)+1
        self:record(ok and 'download_verified' or 'refresh_failed',self._last_error)
        release()
        if ok then self:armAutoRefresh() else self:armAutoRefresh(self:retryDelay()) end
    end
    local function run()
        if generation~=self._generation or self._suspended or (not manual and not self.dash_widget) then release();return end
        local ok,result=pcall(self.refreshDashboard,self,silent,manual)
        finish(ok and result,ok and self._fetch_error or result)
    end
    if self:option('managed_wifi',false) and not Network:isConnected() then
        if Network.pending_connection then finish(false,'Wi-Fi connection already pending');return end
        started_wifi=not Network:isWifiOn()
        self._network_deadline=function()
            if generation==self._generation then
                finish(false,'Wi-Fi connection timeout')
                self._generation=generation+1
            end
        end
        UI:scheduleIn(60,self._network_deadline)
        local ok,err=pcall(Network.turnOnWifiAndWaitForConnection,Network,run)
        if not ok or err==false then finish(false,'Wi-Fi unavailable') end
    else run() end
end
function Dash:safeRefresh() self:requestRefresh(false,true) end
function Dash:onResume()
    self._suspended=false
    if self._awake_tick then UI:unschedule(self._awake_tick);self._awake_tick() end
    if self._resume_tick then UI:unschedule(self._resume_tick) end
    self._resume_tick=function() if self.dash_widget then self:requestRefresh(true,false) end end
    UI:scheduleIn(5,self._resume_tick)
    self:record('resume')
end
local old_suspend=Dash.onSuspend
function Dash:onSuspend()
    old_suspend(self)
    if self._release_wifi then self._release_wifi();self._release_wifi=nil end
    self._generation=(self._generation or 0)+1;self._busy=false
    if self._auto_timer then UI:unschedule(self._auto_timer) end
    if self._network_deadline then UI:unschedule(self._network_deadline) end
    self:record('suspend')
end
local original_hold=Dash.holdAwake
function Dash:holdAwake(on)
    original_hold(self,on)
    if not on and not self.dash_widget then
        if self._release_wifi then self._release_wifi();self._release_wifi=nil end
        self._generation=(self._generation or 0)+1;self._busy=false
        if self._network_deadline then UI:unschedule(self._network_deadline) end
        if self._auto_timer then UI:unschedule(self._auto_timer) end
        self._next_attempt=nil
    end
end
local original_init=Dash.init
function Dash:init()
    original_init(self)
    local f=io.open(self:cacheDir()..'/kindledash-health.json','rb')
    if f then
        local raw=f:read('*a');f:close();local ok,value=pcall(JSON.decode,raw)
        if ok and type(value)=='table' then self._health_history=value end
    end
    self.auto_on=self:option('auto_refresh',true)
    self:armAutoRefresh()
    if not self:option('setup_complete',false) and self.host=='' then
        UI:show(Info:new{text=self:label('Shawn Kanban: use Setup / test image to configure your display.','Shawn Kanban：请在设置／测试图片中配置图源。'),timeout=6})
    end
end
local original_toggle=Dash.toggleAutoRefresh
function Dash:toggleAutoRefresh()
    original_toggle(self)
    self:setOption('auto_refresh',self.auto_on)
    if not self.auto_on then self._next_attempt=nil end
end
local old_close=Dash.onCloseWidget
function Dash:onCloseWidget()
    if self._release_wifi then self._release_wifi();self._release_wifi=nil end
    self._generation=(self._generation or 0)+1;self._busy=false
    if self._network_deadline then UI:unschedule(self._network_deadline) end
    if self._rtc_test and Device.wakeup_mgr then Device.wakeup_mgr:removeTasks(nil,self._rtc_test) end
    old_close(self)
end
function Dash:editInterval()
    local dialog
    dialog=InputDialog:new{title=self:label('Refresh interval (minutes, 5–1440)','刷新间隔（分钟，5–1440）'),
        input=tostring(self:option('interval',1800)/60),buttons={{
        {text=self:label('Cancel','取消'),callback=function() UI:close(dialog) end},
        {text=self:label('Save','保存'),callback=function()
            local n=tonumber(dialog:getInputValue())
            if n and n>=5 and n<=1440 then self:setOption('interval',math.floor(n)*60);UI:close(dialog);self:armAutoRefresh() end
        end}}}}
    UI:show(dialog)
end
function Dash:setupWizard()
    local dialog
    dialog=InputDialog:new{title=self:label('Setup: image or manifest URL','设置：图片或清单地址'),
        description=self:label('Use your own server or the built-in demo. City, timezone and layout are configured on the renderer. Then choose Test image.','使用自己的图源或内置示例。城市、时区和布局在生成端配置。保存后测试图片。'),
        input=self.cloud or '',buttons={{
        {text=self:label('Cancel','取消'),callback=function() UI:close(dialog) end},
        {text=self:label('Save & test','保存并测试'),callback=function()
            local v=dialog:getInputValue() or ''
            if v:match('^https?://') then self:saveCloud(v);self:setOption('setup_complete',true);UI:close(dialog);self:safeRefresh() end
        end}}}}
    UI:show(dialog)
end
function Dash:rtcExperiment()
    local Confirm=require('ui/widget/confirmbox')
    if not Device.wakeup_mgr or not Device.canSuspend or not Device:canSuspend() then
        UI:show(Info:new{text=self:label('RTC wake is unavailable on this device.','此设备不支持 RTC 唤醒接口。')});return
    end
    UI:show(Confirm:new{text=self:label('Experimental: sleep once and attempt a wake in 2 minutes. Keep the power button accessible. This does not enable recurring sleep.','实验：休眠一次并尝试在2分钟后唤醒。请确保可按电源键恢复。不会开启循环休眠。'),
        ok_callback=function()
            if self._rtc_test then Device.wakeup_mgr:removeTasks(nil,self._rtc_test) end
            self._rtc_test=function()
                self._suspended=false;self:record('rtc_alarm_fired');self:onResume()
            end
            Device.wakeup_mgr:addTask(120,self._rtc_test)
            self:record('rtc_test_started');UI:suspend()
        end})
end
local old_menu=Dash.addToMainMenu
function Dash:addToMainMenu(menu)
    old_menu(self,menu)
    local old=menu['0kindledash'].sub_item_table_func
    menu['0kindledash'].sub_item_table_func=function()
        local items=old()
        table.insert(items,2,{text=self:label('Setup / test image','设置／测试图片'),callback=function() self:setupWizard() end})
        table.insert(items,3,{text=self:label('Device status','设备状态'),callback=function() self:showStatus() end})
        items[#items+1]={text=self:label('Refresh interval','刷新间隔'),callback=function() self:editInterval() end}
        for _,entry in ipairs({{'managed_wifi','Connect Wi-Fi for updates','更新时连接 Wi-Fi'},
            {'wifi_off','Turn off Wi-Fi started by dashboard','关闭看板开启的 Wi-Fi'},
            {'night_mode','Night schedule (23–07, every 2 hours)','夜间降频（23–07，每2小时）'}}) do
            local key,en,zh=unpack(entry)
            items[#items+1]={text=self:label(en,zh),checked_func=function() return self:option(key,false) end,
                callback=function() self:setOption(key,not self:option(key,false));self:armAutoRefresh() end}
        end
        items[#items+1]={text=self:label('Experimental: one RTC wake test','实验：单次 RTC 唤醒测试'),callback=function() self:rtcExperiment() end}
        return items
    end
end
end
