"""Exercise the installed runtime using KOReader boundaries, without device power actions."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from PIL import Image
import kindle_plugin_test as harness

lua = harness.lua
lua.execute('''
unpack=table.unpack
package.preload['bit']=function()
    local function signed(x) x=x & 0xffffffff;return x>=0x80000000 and x-0x100000000 or x end
    return {tobit=signed,band=function(a,b) return signed(a & b) end,
        bxor=function(a,b,c) local n=a ~ b;if c then n=n ~ c end;return signed(n) end,
        bnot=function(a) return signed(~a) end,rshift=function(a,n) return (a & 0xffffffff)>>n end,
        ror=function(a,n) a=a & 0xffffffff;return signed((a>>n)|(a<<(32-n))) end,
        tohex=function(a) return string.format('%08x',a & 0xffffffff) end}
end
package.preload['json']=function() return {
    decode=function(raw) if raw=='manifest' then return TEST_META end;error('bad JSON') end,
    encode=function() return '{}' end} end
require('device').screen.getWidth=function() return 1072 end
require('device').screen.getHeight=function() return 1448 end
NET={connected=true,on=true}
function NET:isConnected() return self.connected end
function NET:isWifiOn() return self.on end
function NET:turnOnWifiAndWaitForConnection(cb) self.callback=cb end
function NET:disableWifi() self.disabled=true end
package.preload['ui/network/manager']=function() return NET end
package.preload['ui/renderimage']=function() return {renderImageFile=function()
    if DECODE_FAIL then return nil end
    return {getWidth=function() return 1072 end,getHeight=function() return 1448 end,free=function() end}
end} end
''')
root = Path(__file__).resolve().parents[1]
lua.globals().PLUGIN_DIR = str(root / 'KindleDash.koplugin') + '/'
lua.execute("dofile(PLUGIN_DIR..'runtime.lua')(Plugin,PLUGIN_DIR); SHA=dofile(PLUGIN_DIR..'sha256.lua')")

class RuntimeTests(unittest.TestCase):
    def test_sha256_known_vectors(self):
        for data in [b'',b'abc',b'a'*1000,bytes(range(256))]:
            self.assertEqual(lua.globals().SHA(data), hashlib.sha256(data).hexdigest())

    def test_corrupt_download_and_decode_keep_cache(self):
        out=io.BytesIO();Image.new('L',(1072,1448),255).save(out,'PNG')
        lua.globals().PNG=out.getvalue()
        lua.globals().HASH=hashlib.sha256(out.getvalue()).hexdigest()
        with tempfile.TemporaryDirectory() as tmp:
            lua.globals().CACHE=tmp+'/screen.png'
            Path(tmp+'/screen.png').write_bytes(b'previous-good-image')
            lua.execute('''
            local d=Plugin:new{language='en'}
            d.ensureCacheDir=function() end
            d.cacheImg=function() return CACHE end
            d.readMetadata=function() return {} end
            d.endpoints=function() return {{url='https://example.test/manifest.json',name='Cloud'}} end
            TEST_META={schemaVersion=1,sha256=HASH,generatedAt=os.time()*1000,image_url='image.png',width=1072,height=1448}
            d.request=function(_,url) if url:match('json$') then return 'manifest' end;return PNG..'bad' end
            assert(d:fetchScreen()==nil)
            local f=io.open(CACHE,'rb');assert(f:read('*a')=='previous-good-image');f:close()
            d.request=function(_,url) return url:match('json$') and 'manifest' or PNG end
            local bytes=d:fetchScreen();assert(bytes==PNG)
            DECODE_FAIL=true;assert(not d:writePng(CACHE,bytes))
            f=io.open(CACHE,'rb');assert(f:read('*a')=='previous-good-image');f:close()
            DECODE_FAIL=false;assert(d:writePng(CACHE,bytes))
            f=io.open(CACHE,'rb');assert(f:read('*a')==PNG);f:close()
            assert(not d:writePng(CACHE,'bad image'))
            ''')

    def test_network_deadline_backoff_and_success_reset(self):
        lua.execute('''
        local d=Plugin:new{language='en',auto_on=true,dash_widget={}}
        d.option=function(_,key,default) if key=='managed_wifi' or key=='wifi_off' then return true end;return default end
        d.record=function() end
        NET.connected=false;NET.on=false;NET.disabled=false
        d.refreshDashboard=function() return true end
        d:requestRefresh(true,false)
        assert(d._busy and UI.queue[d._network_deadline]==60)
        local late=NET.callback;d._network_deadline()
        assert(not d._busy and NET.disabled and UI.queue[d._auto_timer]==60)
        late();assert(d._failures==1)
        NET.connected=true
        d:requestRefresh(true,false)
        assert(d._failures==0 and d._last_error==nil and not d._busy)
        d.refreshDashboard=function() return false end
        d:requestRefresh(true,false);assert(UI.queue[d._auto_timer]==60)
        d:requestRefresh(true,false);assert(UI.queue[d._auto_timer]==120)
        d._failures=99;assert(d:retryDelay()==1800)
        local old=d.dash_widget
        d.buildScreen=function() error('bad render') end
        assert(d:showDashboard('broken',false)==false and d.dash_widget==old)
        ''')
