-- Shawn Kanban · Kindle 端显示插件（混合路线 v1）
-- 拉取 PC 端 /api/screen 渲染好的整屏 PNG（1-bit 抖动 / ~24KB），
-- 用 ImageWidget 满屏显示。排版/字体/灰度/抖动全部在 PC 端完成。
-- 自动刷新：onResume 唤醒即刷 + 30 分钟定时器；离线时用上次缓存。

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local ImageWidget = require("ui/widget/imagewidget")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local GestureRange = require("ui/gesturerange")
local http = require("socket.http")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local logger = require("logger")

local REFRESH_SEC = 30 * 60
local DEFAULT_HOST = "192.168.31.188"
local DEFAULT_PORT = "8787"
-- KOReader 上可写临时目录（restart 后丢失；offline 缓存用同一目录）
local SCREEN_PATH = "/tmp/dash_screen.png"
local CACHE_PATH = "/tmp/dash_screen_cache.png"

local KindleDash = WidgetContainer:new{
    name = "KindleDash",
    is_doc_only = false,
    sorting_hint = "tools",
}

function KindleDash:init()
    self.auto_on = true
    self.host = self:loadHost()
    self.dash_widget = nil
    self._auto_timer = nil
    self._last_ok = false
    self._offline = false
    self:armAutoRefresh()
    self.ui.menu:registerToMainMenu(self)
end

-- ---------- 设置 ----------
function KindleDash:settingsPath()
    return DataStorage:getSettingsDir() .. "/kindledash.lua"
end
function KindleDash:loadHost()
    local host, port = DEFAULT_HOST, DEFAULT_PORT
    local ok, s = pcall(function() return LuaSettings:open(self:settingsPath()) end)
    if ok and s then
        if s:has("host") then host = s:readSetting("host") or DEFAULT_HOST end
        if s:has("port") then port = s:readSetting("port") or DEFAULT_PORT end
    end
    if host and not host:find(":", 1, true) then
        host = host .. ":" .. port
    end
    return host
end
function KindleDash:saveHost(host)
    local ok, s = pcall(function() return LuaSettings:open(self:settingsPath()) end)
    if ok and s then
        s:saveSetting("host", host)
        local h, p = host:match("^(.-):(%d+)$")
        if h and p then
            s:saveSetting("host", h)
            s:saveSetting("port", p)
        end
        s:flush()
    end
    self.host = host
end

-- ---------- 拉取屏幕 ----------
function KindleDash:fetchScreen()
    local url = "http://" .. self.host .. "/api/screen"
    local ok, body, code = pcall(function() return http.request(url) end)
    if not ok then
        return nil, "request error: " .. tostring(body)
    end
    if not body or body == "" or code ~= 200 then
        return nil, "fetch failed (" .. tostring(code) .. ")"
    end
    -- /api/screen 出错时会返回 text/plain，必须确认拿到的是真 PNG，否则 ImageWidget 会炸
    if body:sub(1, 4) ~= "\137PNG" then
        return nil, "not a PNG (" .. tostring(body):sub(1, 60) .. ")"
    end
    return body, nil
end

-- 保存 PNG 到临时文件（ImageWidget 需要 file 或 BlitBuffer，用 file 最稳）
function KindleDash:writePng(path, data)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(data)
    f:close()
    return true
end

function KindleDash:fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

-- ---------- 显示 ----------
function KindleDash:showDashboard(img_path, offline)
    if self.dash_widget then
        UIManager:close(self.dash_widget)
        self.dash_widget = nil
    end
    -- 用 Screen 尺寸最稳；ui.dimen 在文件管理器/阅读器切换时可能不对
    local w = Screen:getWidth()
    local h = Screen:getHeight()
    logger.info("ShawnKanban showDashboard screen=", w, "x", h, "img=", img_path)

    -- 整块构建包 pcall：ImageWidget 解码/渲染抛错时只弹提示，绝不把 KOReader 打回桌面
    local ok, err = pcall(function() self:buildScreen(img_path, w, h) end)
    if not ok then
        logger.err("ShawnKanban showDashboard failed: ", tostring(err))
        UIManager:show(InfoMessage:new{
            text = "看板显示失败:\n" .. tostring(err),
            timeout = 8,
        })
    end
end

function KindleDash:buildScreen(img_path, w, h)
    -- ImageWidget 满屏显示
    -- file_do_cache=false: 切换图时强制重新解码；close 时 ImageWidget:free() 释放 BlitBuffer
    local img = ImageWidget:new{
        file = img_path,
        width = w,
        height = h,
        scale_factor = 0,        -- 按 width/height 缩放填满（保持宽高比需 stretch_limit 或 align）
        file_do_cache = false,
    }
    local container = InputContainer:new{
        dimen = Geom:new{ w = w, h = h },
    }
    container[1] = img
    -- 吃手势（防 KOReader 退出/翻页穿透）
    container.ges_events = {
        TapScroll = { GestureRange:new{ ges = "tap", range = function() return container.dimen end } },
        SwipeScroll = { GestureRange:new{ ges = "swipe", range = function() return container.dimen end } },
    }
    function container:onTapScroll(_, ges)
        -- 顶部 10% 区域点击 = 退出（Kindle 无 Back 键，靠此关闭看板）
        if ges and ges.pos and ges.pos.y < h * 0.1 then
            container:onClose()
        end
        return true
    end
    function container:onSwipeScroll(_, ges)
        -- 顶部 25% 下滑 = 退出
        if ges and ges.pos and ges.direction == "south" and ges.pos.y < h * 0.25 then
            container:onClose()
        end
        return true
    end
    function container:onClose()
        UIManager:close(self)
        return true
    end
    function container:onBack()
        UIManager:close(self)
        return true
    end
    function container:onResume()
        -- 唤醒即刷
        pcall(function() KindleDash.refreshDashboard(KindleDash, true) end)
        return true
    end
    self.dash_widget = container
    UIManager:show(container)
end

-- ---------- 刷新（含离线缓存兜底） ----------
-- 菜单入口：任何异常都收敛成提示，避免把 KOReader 打回桌面
function KindleDash:safeRefresh()
    local ok, err = pcall(function() self:refreshDashboard(false) end)
    if not ok then
        logger.err("ShawnKanban refresh crashed: ", tostring(err))
        UIManager:show(InfoMessage:new{ text = "看板失败:\n" .. tostring(err), timeout = 8 })
    end
end

function KindleDash:refreshDashboard(silent)
    local data, err = self:fetchScreen()
    if not data then
        -- 拉取失败：尝试用上次缓存
        if self:fileExists(CACHE_PATH) then
            self._offline = true
            self._last_ok = true
            self:showDashboard(CACHE_PATH, true)
            if not silent then
                UIManager:show(InfoMessage:new{ text = "离线 · 显示上次缓存", timeout = 2 })
            end
        else
            if not silent then
                UIManager:show(InfoMessage:new{ text = "刷新失败: " .. tostring(err), timeout = 3 })
            end
        end
        logger.warn("ShawnKanban refresh failed:", err)
        return
    end
    -- 成功：写临时文件 + 刷新缓存 + 显示
    if self:writePng(SCREEN_PATH, data) then
        self:writePng(CACHE_PATH, data)   -- 同时写到缓存
    end
    self._offline = false
    self._last_ok = true
    self:showDashboard(SCREEN_PATH, false)
end

-- ---------- 自动刷新（对齐整点/半点） ----------
local function secondsToNextSlot()
    local t = os.date("*t")
    local mins = t.min
    local target = mins < 30 and 30 or 60
    return (target - mins) * 60 - t.sec
end

function KindleDash:armAutoRefresh()
    if not self.auto_on then return end
    local function tick()
        if not self.auto_on then return end
        -- 定时器里出错也必须续上下一次，且不能崩
        pcall(function() self:refreshDashboard(true) end)
        self._auto_timer = UIManager:scheduleIn(REFRESH_SEC, tick)
    end
    local first = secondsToNextSlot()
    if first < 30 then first = first + REFRESH_SEC end
    self._auto_timer = UIManager:scheduleIn(first, tick)
end
function KindleDash:toggleAutoRefresh()
    self.auto_on = not self.auto_on
    if self.auto_on then
        self:armAutoRefresh()
        UIManager:show(InfoMessage:new{ text = "自动刷新: 开 (整点/半点)", timeout = 2 })
    else
        UIManager:show(InfoMessage:new{ text = "自动刷新: 关", timeout = 2 })
    end
end

-- ---------- 菜单 ----------
function KindleDash:setServerAddress()
    local dialog
    dialog = InputDialog:new{
        title = "服务器地址 (IP:端口)",
        input = self.host,
        input_hint = "例如 192.168.31.188:8787",
        buttons = {
            {
                { text = "取消", callback = function() UIManager:close(dialog) end },
                { text = "保存", callback = function()
                    local v = dialog:getInputValue()
                    if v and v ~= "" then
                        self:saveHost(v)
                        UIManager:close(dialog)
                        UIManager:show(InfoMessage:new{ text = "已保存: " .. v, timeout = 2 })
                    end
                end }
            }
        }
    }
    UIManager:show(dialog)
end

function KindleDash:addToMainMenu(menu_items)
    menu_items.kindledash = {
        text = "Shawn Kanban",
        sorting_hint = "tools",
        callback = function() self:safeRefresh() end,
        submenus = {
            { text = "刷新看板",     callback = function() self:safeRefresh() end },
            { text = "设置服务器地址", callback = function() self:setServerAddress() end },
            { text = "切换自动刷新 (整点/半点)", callback = function() self:toggleAutoRefresh() end },
            { text = "关于", callback = function()
                UIManager:show(InfoMessage:new{
                    text = "Shawn Kanban\nPC 端 /api/screen 整屏图 · ~24KB 1-bit PNG\n满屏 ImageWidget 显示\n唤醒即刷 + 30 分自动\n顶部下滑/顶部点击返回",
                    timeout = 5
                })
            end }
        }
    }
end

-- 需要 GestureRange（KOReader 顶部全局已 require 过？保险起见 require）
return KindleDash
