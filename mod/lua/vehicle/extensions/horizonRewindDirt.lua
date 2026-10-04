-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Optional Grime 2.0 integration. No third-party source or assets are bundled.
local M = {}
local ffi = require('ffi')
local Compat = require('horizonRewind/fluidCompat')
local Canvas = require('horizonRewind/dirtCanvas')
local core, skin, coreRefs, skinRefs, layout, cached, shown
local hooks, rewinding, lastCapture = {}, false, -math.huge
local reason = 'Grime 2.0 is not loaded.'
local visualKey,visualUpdates=nil,0
local scalarFields = {'rotate','clock','sendAcc','waterZ','mudZ','mudSeen','sinkSeen',
  'sinkHold','sinkSoft','splashN'}

local function extension(name)
  return extensions and rawget(extensions,name) or rawget(_G,name)
end

local function detach()
  for _, h in ipairs(hooks) do
    h.attached = false
    if h.module[h.name] == h.wrapper then h.module[h.name] = h.original end
  end
  hooks = {}
  if extensions.hookUpdate then
    extensions.hookUpdate('updateGFX'); extensions.hookUpdate('onReset')
  end
  core,skin,coreRefs,skinRefs,layout,cached,shown = nil,nil,nil,nil,nil,nil,nil
  lastCapture = -math.huge
  visualKey=nil
end

local function guard(module, name)
  if type(module[name]) ~= 'function' then return end
  local h = {module=module,name=name,original=module[name],attached=true}
  h.wrapper = function(...)
    if h.attached and rewinding then return end
    return h.original(...)
  end
  module[name] = h.wrapper
  hooks[#hooks+1] = h
end

local function discover()
  local c,s = extension('dynamicDirtCore'),extension('dynamicDirtSkin')
  if c ~= core or s ~= skin then
    detach()
    if type(c) ~= 'table' or type(s) ~= 'table' then return false end
    local info = type(jsonReadFile)=='function' and jsonReadFile('mod_info/M76NCDKVR/info.json')
    if type(info)~='table' or info.version_string~='2.0' or info.resource_id~=39586 then
      reason = 'Unsupported Grime version.'; return false
    end
    local cr = Compat.discover(c, {'updateGFX','nodeState','surface'},
      {S='table',SURF='table',SOILS='table',shiftRGB='function'}, 'dynamicDirtCore.lua')
    local sr = Compat.discover(s, {'updateGFX','status','applyDirt','setSoil','setShade','setGlassEffect'},
      {glass='table',glassSent='table',gcall='function',role='string',shadeWanted='number',glassWanted='number'}, 'dynamicDirtSkin.lua')
    if not cr or not sr then reason='Unsupported Grime state layout.'; return false end
    core,skin,coreRefs,skinRefs = c,s,cr,sr
    for _, module in ipairs({core,skin}) do
      for _, name in ipairs({'updateGFX','onReset','reset','init','onInit'}) do guard(module,name) end
    end
    if extensions.hookUpdate then
      extensions.hookUpdate('updateGFX'); extensions.hookUpdate('onReset')
    end
  end
  if not core then return false end
  local state, status = Compat.get(coreRefs,'S'), skin.status()
  if not state.ready or not status.active or not status.texture or Compat.get(skinRefs,'role')~='own' then
    reason='Select Grime paint for this vehicle.'; return false
  end
  if type(state.nodes)~='table' or type(state.dirt)~='table' or type(state.mud)~='table'
    or type(state.sent)~='table' or type(state.sentW)~='table'
    or #state.nodes>4096 then reason='Unsupported Grime node state.'; return false end
  if not layout or layout.nodes~=state.nodes then
    local ids = {}
    for i,node in ipairs(state.nodes) do
      if type(node.cid)~='number' then return false end
      ids[i]=node.cid
    end
    local same=layout and #layout.ids==#ids
    if same then for i,cid in ipairs(ids) do if layout.ids[i]~=cid then same=false;break end end end
    if same then layout.nodes=state.nodes
    else layout={nodes=state.nodes, ids=ids, core=core, skin=skin} end
    cached,shown,lastCapture=nil,nil,-math.huge
  end
  reason='Recording Grime panel buildup and window film.'
  return true
end

local function capture()
  if not discover() then return nil end
  local state=Compat.get(coreRefs,'S')
  if cached and state.clock>=lastCapture and state.clock-lastCapture<0.1 then return cached end
  local f={layout=layout,values=ffi.new('float[?]',#layout.ids*2),scalars={}}
  for i,cid in ipairs(layout.ids) do
    f.values[(i-1)*2]=state.dirt[cid] or 0
    f.values[(i-1)*2+1]=state.mud[cid] or 0
  end
  for _,name in ipairs(scalarFields) do f.scalars[name]=state[name] end
  f.surface=assert(Compat.copy(Compat.get(coreRefs,'SURF'),{bytes=32768,items=128,depth=2}))
  f.glass=assert(Compat.copy(Compat.get(skinRefs,'glass'),{bytes=2048,items=4,depth=1}))
  f.sprayCur=assert(Compat.copy(state.sprayCur,{bytes=8192,items=64,depth=1}))
  f.splashAt=assert(Compat.copy(state.splashAt,{bytes=8192,items=64,depth=1}))
  lastCapture,cached=state.clock,f
  return f
end

local function apply(f, force)
  if not f or not discover() or f.layout~=layout then return false end
  if shown==f and not force then return true end
  local state=Compat.get(coreRefs,'S')
  local marks={}
  local config=core.getConfig()
  for i,cid in ipairs(layout.ids) do
    local dry,wet=f.values[(i-1)*2],f.values[(i-1)*2+1]
    state.dirt[cid],state.mud[cid]=dry,wet
    local amount=math.min(config.maxDirt or 1,dry+wet)
    local ratio=dry+wet>1e-6 and wet/(dry+wet) or 0
    state.sent[cid],state.sentW[cid]=amount,ratio
    if amount>0.004 then marks[#marks+1]={cid=cid,l=amount,w=ratio} end
  end
  for _,name in ipairs(scalarFields) do state[name]=f.scalars[name] end
  state.queue,state.qseen,state.qn={}, {}, 0
  state.pending,state.pendN={},0 -- do not replay future collision deposits
  state.sprayCur=assert(Compat.copy(f.sprayCur))
  state.splashAt=assert(Compat.copy(f.splashAt))
  Compat.set(coreRefs,'SURF',assert(Compat.copy(f.surface)))
  Compat.set(skinRefs,'glass',assert(Compat.copy(f.glass)))
  Compat.set(skinRefs,'glassSent',assert(Compat.copy(f.glass)))
  local html=require('htmlTexture')
  local palette=Compat.get(coreRefs,'SOILS')
  local color=palette[f.surface.soil] or palette.loam
  local shift=Compat.get(coreRefs,'shiftRGB')
  local dr,dg,db=shift(color.dr,color.dg,color.db)
  local wr,wg,wb=shift(color.wr,color.wg,color.wb)
  local soil={dr=dr,dg=dg,db=db,wr=wr,wg=wg,wb=wb,wet=f.surface.wet,
    rough=f.surface.rough,name=f.surface.soil}
  local glassCall=Compat.get(skinRefs,'gcall')
  local style={shade=Compat.get(skinRefs,'shadeWanted'),glass=Compat.get(skinRefs,'glassWanted')}
  local key=jsonEncode({marks,soil,f.glass,style})
  if force or key~=visualKey then
    Canvas.paint(html,obj,function()
      html.call('@dynamic_dirt','washDirt',{})
      html.call('@dynamic_dirt_rough','washDirt',{})
      skin.setSoil(soil)
      -- Include the palette even if Grime's Lua cache suppresses it: a newer
      -- streamed snapshot may replace the earlier job that contained it.
      html.call('@dynamic_dirt','setSoil',soil)
      glassCall('setSoil',soil)
      if #marks>0 then skin.applyDirt(marks) end
      glassCall('washDirt',{})
      glassCall('setGlass',f.glass)
    end,style)
    visualKey=key;visualUpdates=visualUpdates+1
  end
  shown=f
  return true
end

local function safe(fn,...)
  local ok,result=pcall(fn,...)
  if ok then return result end
  reason='Grime compatibility stopped: '..tostring(result)
  log('W','horizonRewindDirt',reason)
  rewinding=false;detach()
  return nil
end

M.capture=function() return safe(capture) end
M.preview=function(f) return safe(apply,f,false) end
M.restore=function(f) return safe(apply,f,true) end
M.begin=function() rewinding=true;shown=nil;visualKey=nil;safe(discover) end
M.finish=function() rewinding=false;cached=nil;lastCapture=-math.huge end
M.abort=function() rewinding=false;detach() end
M.onExtensionUnloaded=M.abort
M.getStatus=function() return {supported=core~=nil,active=rewinding,reason=reason,visualUpdates=visualUpdates} end
return M
