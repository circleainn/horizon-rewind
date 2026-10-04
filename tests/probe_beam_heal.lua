-- Read installed constructors at runtime; no game source is copied or changed.
require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local bundle=assert(require('jbeam/loader').loadVehicleStage1(1,'vehicles/covet/',jsonReadFile('vehicles/covet/15se_M.pc')))
local car=assert(engine:spawnObject2(1,'vehicles/covet/',lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30)))
local function queue(code,dt,count)
  car:queueLuaCommand(code)
  for _=1,count or 8 do engine:update(dt and dt>0 and dt or 0.001,dt or 0) end
end
queue([[
  obj:setGravity(0); obj:setGhostEnabled(true)
  function beamHealFind(fn,wanted,seen)
    seen=seen or {}
    if type(fn)~='function' or seen[fn] then return nil end
    seen[fn]=true
    for i=1,100 do
      local name,value=debug.getupvalue(fn,i)
      if not name then break end
      if name==wanted then return value end
      if type(value)=='function' then
        local found=beamHealFind(value,wanted,seen)
        if found then return found end
      end
    end
  end
  beamHealAdd=assert(beamHealFind(require('jbeam/stage2').loadVehicleStage2,'addBeamByData'))
  local original=onVehicleReset
  beamHealResetCount=0
  onVehicleReset=function(...) beamHealResetCount=beamHealResetCount+1; return original(...) end
  local originalBroken=onBeamBroke
  onBeamBroke=function(cid,energy)
    print('BEAM_HEAL_EVENT phase='..tostring(beamHealPhase)..' cid='..cid..' energy='..tostring(energy))
    return originalBroken(cid,energy)
  end
  beamHealIds={}
  for _,beam in pairs(v.data.beams) do
    local kind=beam.beamType or 0
    if not beamHealIds[kind] and kind~=6 and not beam.wheelID and not obj:beamIsBroken(beam.cid) and not beam.breakGroup then beamHealIds[kind]=beam.cid end
  end
  for name,value in pairs(getmetatable(obj).__index) do
    local lower=name:lower()
    if lower:find('torsion') or lower:find('triangle') or lower:find('colltri') or lower:find('slide') then print('BEAM_HEAL_API '..name..' '..type(value)) end
  end
]],0.001,10)
queue([[
  beamHealRest={}; beamHealPositions={}
  local origin=vec3(obj:getPosition())
  for _,node in pairs(v.data.nodes) do beamHealPositions[node.cid]=vec3(obj:getNodePosition(node.cid))+origin end
  for kind,cid in pairs(beamHealIds) do
    beamHealRest[cid]=obj:getBeamRestLength(cid)
    obj:breakBeam(cid)
    assert(obj:beamIsBroken(cid), 'Beam did not break')
  end
  beamHealPhase='waitingAfterBreak'
]],0.001,10)
queue([[
  beamHealPhase='healing'
  -- This first feasibility case heals at the current pose without teleports.
  for kind,cid in pairs(beamHealIds) do
    beamHealAdd(v.data,deepcopy(v.data.beams[cid]))
    obj:setBeamLength(cid,beamHealRest[cid])
    local b=v.data.beams[cid]
    print('BEAM_HEAL_PARAMETERS '..cid..' strength='..tostring(b.beamStrength)..' spring='..tostring(b.beamSpring)..' deform='..tostring(b.beamDeform)..' length='..obj:nodeLength(b.id1,b.id2))
    print('BEAM_HEAL_IMMEDIATE type='..kind..' cid='..cid..' broken='..tostring(obj:beamIsBroken(cid))..' rest='..obj:getBeamRestLength(cid)..' originalRest='..beamHealRest[cid])
  end
  obj:commitLoad()
  beamHealPhase='healed'
]])
queue([[
  for kind,cid in pairs(beamHealIds) do print('BEAM_HEAL_COMMIT type='..kind..' cid='..cid..' broken='..tostring(obj:beamIsBroken(cid))) end
]])
queue([[
  for kind,cid in pairs(beamHealIds) do print('BEAM_HEAL_STEPPED type='..kind..' cid='..cid..' broken='..tostring(obj:beamIsBroken(cid))) end
  print('BEAM_HEAL_RESET_COUNT '..beamHealResetCount)
]],0.001,10)
print('BEAM_HEAL_PROBE_DONE')
