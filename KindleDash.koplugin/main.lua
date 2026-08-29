-- Shawn Kanban · Kindle 端显示插件（混合路线 v2）
-- 拉取渲染好的整屏 PNG（1072x1448，1-bit 抖动 / ~30KB），用 ImageWidget 满屏显示。
-- 排版/字体/灰度/抖动全部在渲染端完成，Kindle 只负责取图与显示。
--
-- 取图三级降级链（关键：电脑关机也能拿到新内容）：
--   1) 局域网 PC（/api/screen）—— 数据最新最全，电脑关机时连不上
--   2) 云端静态图（GitHub Pages）—— 由 Actions 每 15 分钟渲染，电脑关机仍可用
--   3) 本地持久缓存（settings 目录）—— 网络全断时显示最后一次的图
--
-- 自动刷新：onResume 唤醒即刷 + 30 分钟定时器。

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
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
-- 通知 autosuspend 插件别挂起设备（官方机制，autoturn/keepalive 同款）。
-- 用 pcall 防御：模块万一缺失也不能让整个插件加载失败（重演 lfs 事故的教训）。
local ok_ps, PluginShare = pcall(require, "pluginshare")
if not ok_ps then PluginShare = nil end

-- 网络请求超时：电脑关机时不要让用户等太久，8 秒无响应就切换离线缓存
http.TIMEOUT = 8

local REFRESH_SEC = 30 * 60
local DEFAULT_HOST = "192.168.31.188"
local DEFAULT_PORT = "8787"
-- 云端静态图完整 URL（GitHub Pages），留空则只用局域网
local DEFAULT_CLOUD = ""
-- 缓存存到 settings 目录（/mnt/us/koreader/settings/），Kindle 重启后仍在
local CACHE_IMG_NAME = "kindledash_screen.png"
local CACHE_TS_NAME  = "kindledash_ts.txt"
-- KOReader 自带的 CA 证书，用于校验 https
local CA_BUNDLE = DataStorage:getDataDir() .. "/ca-bundle.crt"

local KindleDash = WidgetContainer:new{
    name = "KindleDash",
    is_doc_only = false,
    sorting_hint = "tools",
}

function KindleDash:init()
    self.auto_on = true
    self.host = self:loadHost()
    self.cloud = self:loadCloud()
    self.dash_widget = nil
    self._auto_timer = nil
    self._last_ok = false
    self._offline = false
    self._source = nil   -- 本次图像来自哪里：本机 / 云端 / 缓存
    self:armAutoRefresh()
    self.ui.menu:registerToMainMenu(self)
end

-- ---------- 设置 ----------
function KindleDash:settingsPath()
    return DataStorage:getSettingsDir() .. "/kindledash.lua"
end
function KindleDash:cacheDir()
    return DataStorage:getSettingsDir()
end
function KindleDash:cacheImg()
    return self:cacheDir() .. "/" .. CACHE_IMG_NAME
end
function KindleDash:cacheTs()
    return self:cacheDir() .. "/" .. CACHE_TS_NAME
end
function KindleDash:ensureCacheDir()
    local dir = self:cacheDir()
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
end
function KindleDash:readTs()
    local f = io.open(self:cacheTs(), "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s and s:match("^%s*(.-)%s*$") or nil
end
function KindleDash:writeTs(s)
    self:ensureCacheDir()
    local f, err = io.open(self:cacheTs(), "wb")
    if not f then return nil, err end
    f:write(s or ""); f:close()
    return true
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

function KindleDash:loadCloud()
    local ok, s = pcall(function() return LuaSettings:open(self:settingsPath()) end)
    if ok and s and s:has("cloud") then
        return s:readSetting("cloud") or DEFAULT_CLOUD
    end
    return DEFAULT_CLOUD
end
function KindleDash:saveCloud(url)
    local ok, s = pcall(function() return LuaSettings:open(self:settingsPath()) end)
    if ok and s then
        s:saveSetting("cloud", url or "")
        s:flush()
    end
    self.cloud = url or ""
end

-- ---------- 阻止深度挂起 ----------
-- Kindle 上 canStandby=false、canSuspend=true：一旦进 suspend，UIManager 定时器
-- 全部停止（整点自动刷新形同虚设），且历史上出现过电源键唤不醒、必须插电才恢复。
-- 所以看板显示期间用官方 PluginShare.pause_auto_suspend 阻止挂起，退出时恢复原值。
-- 严禁 preventStandby（会锁死电源键，历史事故）。
function KindleDash:holdAwake(on)
    if not PluginShare then return end
    if on then
        if self._hold_awake then return end
        self._saved_pause = PluginShare.pause_auto_suspend
        PluginShare.pause_auto_suspend = true
        self._hold_awake = true
        logger.info("ShawnKanban holdAwake ON")
    else
        if not self._hold_awake then return end
        PluginShare.pause_auto_suspend = self._saved_pause
        self._hold_awake = false
        logger.info("ShawnKanban holdAwake OFF")
    end
end

-- ---------- 拉取屏幕 ----------
-- 取图优先级：局域网 PC > 云端 Pages > 本地缓存（缓存由调用方处理）
function KindleDash:endpoints()
    local list = {}
    if self.host and self.host ~= "" then
        table.insert(list, { url = "http://" .. self.host .. "/api/screen", name = "本机" })
    end
    if self.cloud and self.cloud ~= "" then
        table.insert(list, { url = self.cloud, name = "云端" })
    end
    return list
end

-- 单个 URL 的取图。HTTPS 由 KOReader 定制版 socket.http 自动分派到 ssl.https，
-- 这里只额外指定 CA 与校验级别；绝不能传 create（会破坏 scheme 自动分派）。
function KindleDash:tryFetch(url)
    local https = url:sub(1, 8) == "https://"
    local ok, body, code = pcall(function()
        if https and self:fileExists(CA_BUNDLE) then
            return http.request{
                url = url,
                method = "GET",
                cafile = CA_BUNDLE,
                verify = "peer",
                protocol = "tlsv1_2",
            }
        end
        return http.request(url)
    end)
    if not ok then
        logger.warn("ShawnKanban fetch error", url, tostring(body))
        return nil
    end
    if not body or body == "" or code ~= 200 then
        logger.warn("ShawnKanban fetch http", url, tostring(code))
        return nil
    end
    -- 服务端出错会返回 text/plain，必须确认拿到的是真 PNG，否则 ImageWidget 会炸
    if body:sub(1, 4) ~= "\137PNG" then
        logger.warn("ShawnKanban not a PNG", url, tostring(body):sub(1, 60))
        return nil
    end
    return body
end

function KindleDash:fetchScreen()
    local eps = self:endpoints()
    if #eps == 0 then
        return nil, "未配置任何图源"
    end
    local tried = {}
    for _, ep in ipairs(eps) do
        local data = self:tryFetch(ep.url)
        if data then
            return data, nil, ep.name
        end
        table.insert(tried, ep.name)
    end
    return nil, table.concat(tried, "/") .. " 均不可用"
end

-- 保存 PNG 到文件（缓存目录持久化，Kindle 重启后仍在）
function KindleDash:writePng(path, data)
    self:ensureCacheDir()
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
    local dash = self    -- container 回调里的 self 是 container，这里留个插件实例的引用
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
        dash.dash_widget = nil      -- 先标记已关闭，否则后台刷新会误判成"看板正显示"
        dash:holdAwake(false)
        UIManager:close(self)
        return true
    end
    function container:onBack()
        dash.dash_widget = nil
        dash:holdAwake(false)
        UIManager:close(self)
        return true
    end
    function container:onResume()
        -- 唤醒即刷
        pcall(function() KindleDash.refreshDashboard(KindleDash, true, false) end)
        return true
    end
    self.dash_widget = container
    -- 看板显示期间不挂起，整点/半点的定时刷新才可能真正触发
    dash:holdAwake(true)
    UIManager:show(container)
end

-- ---------- 刷新（含离线缓存兜底） ----------
-- 菜单入口：任何异常都收敛成提示，避免把 KOReader 打回桌面
function KindleDash:safeRefresh()
    local ok, err = pcall(function() self:refreshDashboard(false, true) end)   -- 用户主动：必须显示看板
    if not ok then
        logger.err("ShawnKanban refresh crashed: ", tostring(err))
        UIManager:show(InfoMessage:new{ text = "看板失败:\n" .. tostring(err), timeout = 8 })
    end
end

-- manual=true 表示用户主动打开（点菜单）；false 表示定时/唤醒的后台刷新。
-- 后台刷新不应把已关闭的看板弹回来，但用户主动点就必须显示——
-- 首次打开时 dash_widget 本来就是 nil，不能拿它判断"用户想不想看"。
function KindleDash:refreshDashboard(silent, manual)
    local data, err, source = self:fetchScreen()
    local cacheImg = self:cacheImg()
    local showing = (self.dash_widget ~= nil)   -- 看板此刻是否正显示在屏幕上

    if not data then
        -- 拉取失败：看板正显示时（或用户主动打开时）用持久缓存顶上
        if self:fileExists(cacheImg) then
            self._offline = true
            self._last_ok = true
            if showing or manual then
                self:showDashboard(cacheImg, true)
                if not silent then
                    local ts = self:readTs()
                    local msg = ts and ("离线 · 最后 " .. ts) or "离线 · 显示上次缓存"
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 2 })
                end
            end
        elseif not silent then
            UIManager:show(InfoMessage:new{ text = "刷新失败: " .. tostring(err), timeout = 3 })
        end
        logger.warn("ShawnKanban refresh failed:", err)
        return
    end

    -- 成功：写持久缓存 + 时间戳
    if self:writePng(cacheImg, data) then
        self:writeTs(os.date("%H:%M"))
    end
    self._offline = false
    self._last_ok = true
    self._source = source

    -- 后台刷新且看板没在显示：只默默更新缓存，别把看板弹回来（下次打开即是最新）
    if not showing and not manual then
        logger.info("ShawnKanban bg refresh ok source=", source, " 看板未显示, 仅更新缓存")
        return
    end

    self:showDashboard(cacheImg, false)
    if not silent and source == "云端" then
        -- 电脑没开时走的正是这条路，明确告诉用户数据来自云端
        UIManager:show(InfoMessage:new{ text = "来自云端（电脑未连上）", timeout = 2 })
    end
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
        pcall(function() self:refreshDashboard(true, false) end)   -- 后台定时：不主动弹窗
        -- 每次都按整点/半点重新对齐：用固定间隔会因刷新耗时而累积漂移
        local delay = secondsToNextSlot()
        if delay < 30 then delay = delay + REFRESH_SEC end
        self._auto_timer = UIManager:scheduleIn(delay, tick)
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

function KindleDash:setCloudUrl()
    local dialog
    dialog = InputDialog:new{
        title = "云端图地址 (完整 URL)",
        description = "电脑关机时从这儿取图。留空则只用局域网。",
        input = self.cloud or "",
        input_hint = "https://用户名.github.io/shawn-kanban/screen.png",
        buttons = {
            {
                { text = "取消", callback = function() UIManager:close(dialog) end },
                { text = "保存", callback = function()
                    local v = dialog:getInputValue() or ""
                    self:saveCloud(v)
                    UIManager:close(dialog)
                    UIManager:show(InfoMessage:new{
                        text = v == "" and "已清空云端地址" or "已保存: " .. v, timeout = 3
                    })
                end }
            }
        }
    }
    UIManager:show(dialog)
end

function KindleDash:addToMainMenu(menu_items)
    menu_items["0kindledash"] = {
        text = "Shawn Kanban",
        sorting_hint = "tools",
        sub_item_table = {
            { text = "刷新看板",     callback = function() self:safeRefresh() end },
            { text = "设置局域网服务器", callback = function() self:setServerAddress() end },
            { text = "设置云端图地址", callback = function() self:setCloudUrl() end },
            { text = "切换自动刷新 (整点/半点)", callback = function() self:toggleAutoRefresh() end },
            { text = "关于", callback = function()
                UIManager:show(InfoMessage:new{
                    text = "Shawn Kanban\n取图顺序：局域网 PC > 云端 Pages > 本地缓存\n"
                       .. "云端每 15 分钟由 GitHub Actions 渲染\n"
                       .. "AI 额度走局域网实时，关机显示最后值\n"
                       .. "唤醒即刷 + 30 分自动\n顶部下滑/顶部点击返回",
                    timeout = 6
                })
            end }
        }
    }
end

-- 需要 GestureRange（KOReader 顶部全局已 require 过？保险起见 require）
return KindleDash
