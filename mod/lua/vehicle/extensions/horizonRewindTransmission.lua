-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Stock shift controllers keep DCT shaft selection outside their public state.
-- Restore writable tables and resume in-gear. Private scalar setters are blocked
-- by BeamNG's sandbox; never resume an old shift callback with reset targets.
local M = {}
local cached, binding
local tableNames = {clutchHandling=true, dct=true, gearboxLogic=true}

local function read(c)
  local name, value = debug.getupvalue(c.fn, c.index)
  if name == c.name then return value end
end
local function discover()
  local main = controller and controller.mainController
  if not main or not debug or not debug.getupvalue then return end
  local logic
  if type(main.getState) == 'function' then
    for i=1,30 do
      local name,value = debug.getupvalue(main.getState,i)
      if not name then break end
      if name == 'controlLogicModule' then logic=value;break end
    end
  end
  if type(logic) ~= 'table' then return end
  if cached == logic then return binding end
  cached,binding=logic,nil
  local cells,seen={},{}
  local function visit(fn,depth)
    if type(fn)~='function' or seen[fn] or depth>6 then return end
    seen[fn]=true
    local info=debug.getinfo(fn,'S')
    local source=info and (info.source or ''):gsub('\\','/') or ''
    if not source:find('lua/vehicle/controller/vehicleController/shiftLogic/',1,true) then return end
    for i=1,60 do
      local name,value=debug.getupvalue(fn,i)
      if not name then break end
      if tableNames[name] then cells[name]={fn=fn,index=i,name=name} end
      if type(value)=='function' then visit(value,depth+1) end
      if name=='gearboxAvailableLogic' and type(value)=='table' then
        for _,mode in pairs(value) do
          if type(mode)=='table' then for _,f in pairs(mode) do visit(f,depth+1) end end
        end
      end
    end
  end
  for _,fn in pairs(logic) do visit(fn,0) end
  if not cells.gearboxLogic then return end
  binding={logic=logic,cells=cells}
  return binding
end
local function scalars(source)
  local out={}
  for key,value in pairs(source or {}) do
    if type(value)=='number' or type(value)=='boolean' or type(value)=='string' then out[key]=value end
  end
  return out
end
local function put(target,source)
  if type(target)~='table' then return end
  for key,value in pairs(source or {}) do if target[key]~=nil then target[key]=value end end
end
function M.capture()
  local b=discover();if not b then return end
  local f={owner=b.logic,timer=scalars(b.logic.timer),clutch={},electrics={}}
  if b.cells.clutchHandling then f.clutch=scalars(read(b.cells.clutchHandling)) end
  local d=b.cells.dct and read(b.cells.dct)
  if d then f.primary=d.primaryAccess==d.access2 and 2 or 1;f.clutchTime=d.clutchTime end
  local modes=read(b.cells.gearboxLogic)
  if type(modes)=='table' then
    for name,fn in pairs(modes) do if fn==b.logic.updateGearboxGFX then f.phase=name end end
  end
  for _,device in pairs(powertrain.getDevices()) do
    for _,key in ipairs({'electricsClutchRatio1Name','electricsClutchRatio2Name'}) do
      local name=device[key]
      if type(name)=='string' and type(electrics.values[name])=='number' then f.electrics[name]=electrics.values[name] end
    end
  end
  return f
end
function M.restore(f)
  local b=discover();if not b or type(f)~='table' or f.owner~=b.logic then return end
  put(b.logic.timer,f.timer)
  if b.cells.clutchHandling then put(read(b.cells.clutchHandling),f.clutch) end
  local d=b.cells.dct and read(b.cells.dct)
  if d and f.primary then
    d.primaryAccess=f.primary==2 and d.access2 or d.access1
    d.secondaryAccess=f.primary==2 and d.access1 or d.access2
    d.clutchTime=f.clutchTime
  end
  local modes=read(b.cells.gearboxLogic)
  if type(modes)=='table' and type(modes.inGear)=='function' then b.logic.updateGearboxGFX=modes.inGear end
  for name,value in pairs(f.electrics) do electrics.values[name]=value end
end
return M
