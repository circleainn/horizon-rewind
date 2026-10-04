-- Vehicle-side read-only measurements; only detach() invokes the installed
-- tire mod's public diagnostic commands to create a repeatable tire event.
local M={}
local rawWheel,groups,bounds,edges={}, {}, {}, {}
local offsets,historyRef,cursorRef,independentGeometry={},nil,nil,nil
local tracking,elapsed=true,0
local function optional(name) return rawget(_G,name) or rawget(extensions,name) end
local function emit(value)
  obj:queueGameEngineLua('extensions.horizonRewindTireSmoke.receive('..serialize(value)..')')
end
local function group(name,ids)
  local list,seen={},{}
  for _,id in pairs(ids or {}) do if type(id)=='number' and not seen[id] then list[#list+1]=id;seen[id]=true end end
  table.sort(list); groups[name]=list; edges[name]={}
  for _,beam in pairs(v.data.beams) do
    if seen[beam.id1] and seen[beam.id2] then
      local initial=(vec3(v.data.nodes[beam.id1].pos)-vec3(v.data.nodes[beam.id2].pos)):length()
      if initial>.001 then edges[name][#edges[name]+1]={beam.id1,beam.id2,initial} end
    end
  end
end
local function metrics(name,frame,plans)
  local ids=groups[name]
  local center=vec3();local positions={}
  for _,id in ipairs(ids) do
    local p
    local k=offsets[id]
    if plans and plans[k] then local x,y,z=require('horizonRewind/wheelInterpolation').position(plans[k],k);p=vec3(x,y,z)
    elseif frame then p=vec3(frame.nodes[k],frame.nodes[k+1],frame.nodes[k+2])
    else p=vec3(obj:getNodePosition(id));if plans then p=p+vec3(obj:getPosition()) end end
    positions[id]=p;center=center+p
  end
  if #ids>0 then center=center/#ids end
  local sum,maxRadius,maxEdge=0,0,0
  for _,id in ipairs(ids) do local r=(positions[id]-center):length();sum=sum+r*r;maxRadius=math.max(maxRadius,r) end
  for _,edge in ipairs(edges[name]) do maxEdge=math.max(maxEdge,(positions[edge[1]]-positions[edge[2]]):length()/edge[3]) end
  local worldCenter=frame and center+vec3(frame.origin) or (plans and center or center+vec3(obj:getPosition()))
  return {count=#ids,rms=#ids>0 and math.sqrt(sum/#ids) or 0,maxRadius=maxRadius,maxEdgeRatio=maxEdge,center=worldCenter:toTable()}
end
local function findState(fn,wanted,seen)
  seen=seen or {};if seen[fn] then return end;seen[fn]=true
  for i=1,128 do
    local name,value=debug.getupvalue(fn,i);if not name then break end
    if name==wanted then return function() return select(2,debug.getupvalue(fn,i)) end end
    if type(value)=='function' then local found=findState(value,wanted,seen);if found then return found end end
  end
end
local function angular(name,frame)
  local center,velocity=vec3(),vec3()
  for _,cid in ipairs(groups[name]) do local k=offsets[cid];center=center+vec3(frame.nodes[k],frame.nodes[k+1],frame.nodes[k+2]);velocity=velocity+vec3(frame.nodes[k+3],frame.nodes[k+4],frame.nodes[k+5]) end
  center,velocity=center/#groups[name],velocity/#groups[name]
  local ka,kb=offsets[rawWheel.node1],offsets[rawWheel.node2]
  local axis=(vec3(frame.nodes[kb],frame.nodes[kb+1],frame.nodes[kb+2])-vec3(frame.nodes[ka],frame.nodes[ka+1],frame.nodes[ka+2])):normalized()
  local n,d=0,0
  for _,cid in ipairs(groups[name]) do
    local k=offsets[cid];local r=vec3(frame.nodes[k],frame.nodes[k+1],frame.nodes[k+2])-center
    r=r-axis*r:dot(axis)
    local v=vec3(frame.nodes[k+3],frame.nodes[k+4],frame.nodes[k+5])-velocity
    n,d=n+r:cross(v):dot(axis),d+r:squaredLength()
  end
  return d>0 and n/d or 0
end
local function sample(tag)
  local tire=optional('tireDebeadingDebug')
  local runtime=wheels.wheels[rawWheel.wheelID or rawWheel.cid]
  if not runtime then for _,wheel in pairs(wheels.wheels) do if wheel.name==rawWheel.name then runtime=wheel;break end end end
  local result={tag=tag,wheel=rawWheel.name,modLoaded=tire~=nil,punctureLoaded=optional('selfPunctureGlobal')~=nil,
    pressure=obj:getGroupPressure(v.data.pressureGroups[rawWheel.pressureGroup]),
    deflated=runtime and runtime.isTireDeflated==true,groups={},bounds=bounds}
  result.detached=tire and tire._meshSwapPolicy.isDetachFinalized(rawWheel) or false
  result.replacement=tire and tire._visualLifecycle.shouldReplacementBeVisible(rawWheel) or false
  result.resetSafety=tire and tire._resetSafety and tire._resetSafety.active==true
  local _,ledger=tire._collisionMutationLedgerCounts(); result.collisionLedgerNodes=ledger
  local flags={selfCollision=0,collision=0,staticCollision=0}
  for _,id in pairs(rawWheel.treadNodes or {}) do local n=v.data.nodes[id];for k in pairs(flags) do if n[k]==true then flags[k]=flags[k]+1 end end end
  result.treadFlags=flags
  local adapter=rawget(extensions,'horizonRewindTires')
  result.adapter=adapter and adapter.status and adapter.status() or nil
  for name in pairs(groups) do result.groups[name]=metrics(name) end
  local bound=bounds.helper
  if tag:find('preview-',1,true) and historyRef and cursorRef then
    local h,c=historyRef(),cursorRef()
    if c then
      local a,b,t=h:bracket(c)
      local plans=require('horizonRewind/wheelInterpolation').plans(independentGeometry,a,b,t)
      result.bracket={aTime=a.time,bTime=b.time,alpha=t,aHelper=metrics('helper',a),bHelper=metrics('helper',b),
        aTread=metrics('tread',a),bTread=metrics('tread',b),alternativeHelper=metrics('helper',nil,plans),
        helperAngularA=angular('helper',a),helperAngularB=angular('helper',b),treadAngularA=angular('tread',a),treadAngularB=angular('tread',b),
        detachedA=a.tireState and a.tireState.detached.FL,detachedB=b.tireState and b.tireState.detached.FL}
      result.bracket.aGroups,result.bracket.bGroups={},{}
      for name in pairs(groups) do result.bracket.aGroups[name]=metrics(name,a);result.bracket.bGroups[name]=metrics(name,b) end
    end
  end
  return result
end
function M.prepare()
  rawWheel=nil
  for _,wheel in pairs(v.data.wheels) do if wheel.name=='FL' then rawWheel=wheel;break end end
  assert(rawWheel,'No FL pressureWheel')
  assert(optional('tireDebeadingDebug'),'Detachable Tires runtime did not autoload')
  assert(optional('selfPunctureGlobal'),'TireImpactPunctures runtime did not autoload')
  group('hub',rawWheel.nodes);group('tread',rawWheel.treadNodes)
  local helper={}
  for _,fb in pairs(v.data.flexbodies) do
    if fb._tireDebeadingWheel=='FL' then
      for _,id in pairs(fb._tireDebeadingHubDuplicateNodeIds or {}) do helper[#helper+1]=id end
    end
  end
  group('helper',helper)
  local carcass={}
  for _,id in pairs(rawWheel.treadNodes or {}) do carcass[#carcass+1]=id end
  for _,id in ipairs(helper) do carcass[#carcass+1]=id end
  group('carcass',carcass)
  local ids={};for _,node in pairs(v.data.nodes) do ids[#ids+1]=node.cid end;table.sort(ids)
  for i,cid in ipairs(ids) do offsets[cid]=(i-1)*7 end
  local recorder=extensions.horizonRewindVehicle
  historyRef=findState(recorder.seek,'history');cursorRef=findState(recorder.seek,'cursor')
  assert(historyRef and cursorRef,'Read-only recorder bracket diagnostics unavailable')
  independentGeometry=require('horizonRewind/wheelInterpolation').index({{name='FL helper',node1=rawWheel.node1,node2=rawWheel.node2,nodes=helper,radius=rawWheel.radius}},ids,{},v.data.nodes)
  emit(sample('prepared'))
end
function M.sample(tag) emit(sample(tag)) end
function M.setTracking(value) tracking=value end
function M.detach()
  local tire=assert(optional('tireDebeadingDebug'))
  tire.deflateTestTire('FL')
  local ok=tire.detachAllBeadsAtOnce('FL')
  emit({tag='detached-command',ok=ok})
end
function M.updateGFX(dt)
  if not rawWheel or not rawWheel.name or not tracking then return end
  elapsed=elapsed+dt;if elapsed<.1 then return end;elapsed=0
  for name in pairs(groups) do
    local m=metrics(name);local b=bounds[name] or {minRms=math.huge,maxRms=0,maxEdgeRatio=0,maxRadius=0,samples=0}
    b.minRms=math.min(b.minRms,m.rms);b.maxRms=math.max(b.maxRms,m.rms)
    b.maxEdgeRatio=math.max(b.maxEdgeRatio,m.maxEdgeRatio);b.maxRadius=math.max(b.maxRadius,m.maxRadius);b.samples=b.samples+1
    bounds[name]=b
  end
end
return M
