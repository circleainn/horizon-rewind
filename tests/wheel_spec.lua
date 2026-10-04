-- Pure numeric regression checks; Lua 5.1/LuaJIT compatible.
local Wheel = testWheelSource and assert(loadstring(testWheelSource))()
  or require('horizonRewind/wheelInterpolation')
local count = 0
local function near(actual, expected, message, epsilon)
  assert(math.abs(actual-expected)<(epsilon or 1e-6),
    (message or 'Mismatch')..': '..tostring(actual)..' expected '..tostring(expected))
end
local function test(name, fn)
  fn(); count=count+1; print('WHEEL_SPEC_PASS '..name)
end
local ids={10,20,31,32,33,34}
local definitions={{node1=10,node2=20,nodes={31,32,33,34},radius=1}}
local geometry=Wheel.index(definitions,ids)
local function frame(angle, time, speed, center, tilt, scale)
  local result={nodes={},origin={0,0,0},time=time}
  center,tilt,scale=center or {0,0,0},tilt or 0,scale or 1
  local function put(k,x,y,z,vx,vy,vz)
    local c,s=math.cos(tilt),math.sin(tilt)
    result.nodes[k],result.nodes[k+1],result.nodes[k+2]=center[1]+x*c+z*s,center[2]+y,center[3]-x*s+z*c
    result.nodes[k+3],result.nodes[k+4],result.nodes[k+5]=vx*c+vz*s,vy,-vx*s+vz*c
    result.nodes[k+6]=1
  end
  put(0,0,0,-0.2,0,0,0); put(7,0,0,0.2,0,0,0)
  for i=0,3 do
    local theta=angle+i*math.pi/2
    local x,y=math.cos(theta)*scale,math.sin(theta)*scale
    put((i+2)*7,x,y,0,-y*speed,x*speed,0)
  end
  return result
end
local function position(a,b,t,k)
  local plans=Wheel.plans(geometry,a,b,t)
  assert(plans[k or 14], 'No wheel plan')
  return Wheel.position(plans[k or 14],k or 14)
end
test('indexes sparse node IDs and excludes axle nodes',function()
  assert(#geometry==1 and geometry[1].a==0 and geometry[1].b==7 and #geometry[1].nodes==4)
  local g=Wheel.index({{node1=10,node2=20,nodes={10,20,31,31,32,33,34},radius=1}},ids)
  assert(#g==1 and #g[1].nodes==4)
end)
test('half turn preserves the tire ring instead of collapsing',function()
  local a,b=frame(0,0,math.pi/0.05),frame(math.pi,0.05,math.pi/0.05)
  for k=14,35,7 do
    local x,y,z=position(a,b,0.5,k)
    near(x*x+y*y,1,'Radius squared'); near(z,0)
  end
  local x,y=position(a,b,0.5)
  near(x,0); near(y,1)
end)
test('node velocity resolves more than a full turn between samples',function()
  local angle=2.5*math.pi
  local a,b=frame(0,0,angle/0.05),frame(angle,0.05,angle/0.05)
  local x,y=position(a,b,0.5)
  near(x,math.cos(angle/2)); near(y,math.sin(angle/2))
end)
test('negative wheel rotation resolves long arcs',function()
  local angle=-3.5*math.pi
  local a,b=frame(0,0,angle/0.05),frame(angle,0.05,angle/0.05)
  local x,y=position(a,b,0.5)
  near(x,math.cos(angle/2)); near(y,math.sin(angle/2))
end)
test('time interval comes from actual sample times after a hitch',function()
  local angle=4*math.pi+0.3
  local a,b=frame(0,2,angle/0.18),frame(angle,2.18,angle/0.18)
  local x,y=position(a,b,0.25)
  near(x,math.cos(angle/4)); near(y,math.sin(angle/4))
end)
test('translates and steers the axle while preserving radius',function()
  local a,b=frame(0,0,math.pi/0.05),frame(math.pi,0.05,math.pi/0.05,{8,4,2},math.pi/2)
  local x,y,z=position(a,b,0.5)
  near(x,4); near(y,3); near(z,1)
end)
test('different vehicle origins remain world-space continuous',function()
  local a,b=frame(0,0,0),frame(0,0.05,0)
  a.origin={5,8,10}; b.origin={7,12,14}
  local x,y,z=position(a,b,0.5)
  near(x,7); near(y,10); near(z,12)
end)
test('preserves recorded deformation instead of inventing a pristine tire',function()
  local a,b=frame(0,0,math.pi/0.05),frame(math.pi,0.05,math.pi/0.05,nil,nil,0.6)
  local x,y=position(a,b,0.5)
  near(math.sqrt(x*x+y*y),0.8)
end)
test('endpoints remain exact and unmodified',function()
  local a,b=frame(0,0,0),frame(1,0.05,0)
  assert(next(Wheel.plans(geometry,a,b,0))==nil)
  assert(next(Wheel.plans(geometry,a,b,1))==nil)
  assert(next(Wheel.plans(geometry,a,a,0.5))==nil)
  near(a.nodes[14],1); near(b.nodes[14],math.cos(1))
end)
test('degenerate axle falls back to the ordinary node path',function()
  local a,b=frame(0,0,0),frame(1,0.05,0)
  b.nodes[9]=b.nodes[2]
  assert(next(Wheel.plans(geometry,a,b,0.5))==nil)
end)
test('detached fragments do not orbit their old axle',function()
  local a,b=frame(0,0,0),frame(1,0.05,0)
  b.nodes[14]=10
  assert(next(Wheel.plans(geometry,a,b,0.5))==nil)
end)
test('nonfinite velocity safely uses ordinary node interpolation',function()
  local a,b=frame(0,0,0),frame(1,0.05,0)
  b.nodes[17]=0/0
  assert(next(Wheel.plans(geometry,a,b,0.5))==nil)
end)
test('props and custom vehicles without wheel definitions are supported',function()
  assert(#Wheel.index(nil,ids)==0)
  assert(#Wheel.index({{}, {node1=900,node2=901,nodes={31,32,33}}},ids)==0)
  assert(next(Wheel.plans({},frame(0,0,0),frame(1,0.05,0),0.5))==nil)
end)

-- A pressure wheel has separate hub/tread rings. Detachable tire helpers are
-- extra physical flexbody anchors and deliberately absent from both lists.
local function assembly(withHelpers,dually)
  local h={ids={10,20},definitions={[10]={pos={0,0,-.2}},[20]={pos={0,0,.2}}},
    wheels={},flexbodies={},groups={},offsets={[10]=0,[20]=7}}
  local nextId=101
  local function rings(name,kind,radius,z)
    local group={name=name,kind=kind,radius=radius,z=z,ids={},points={}}
    for side=-1,1,2 do
      for ray=0,3 do
        local cid=nextId;nextId=nextId+7
        local theta=ray*math.pi/2
        local p={radius*math.cos(theta),radius*math.sin(theta),side*.2}
        h.ids[#h.ids+1]=cid;h.offsets[cid]=(#h.ids-1)*7
        h.definitions[cid]={pos={p[1],p[2],p[3]+z}}
        group.ids[#group.ids+1]=cid;group.points[cid]=p
      end
    end
    h.groups[name..kind]=group
    return group.ids
  end
  for index=1,(dually and 2 or 1) do
    local name=index==1 and 'left' or 'leftOuter'
    local z=dually and (index==1 and -.65 or .65) or 0
    local rim=rings(name,'rim',.5,z)
    local tread=rings(name,'tire',1,z)
    h.wheels[#h.wheels+1]={name=name,node1=10,node2=20,nodes=rim,treadNodes=tread,radius=1}
    if withHelpers then
      local helpers=rings(name,'helper',.5,z)
      local binding={}
      for _,list in ipairs({tread,helpers}) do for _,cid in ipairs(list) do binding[#binding+1]=cid end end
      h.flexbodies[#h.flexbodies+1]={_tireDebeadingReplacement=true,_tireDebeadingWheel=name,
        _group_nodes=binding,_tireDebeadingHubDuplicateNodeIds=helpers,
        -- An overlapping helper field must not produce duplicate membership.
        _tireDebeadingCollisionHelperNodeIds={helpers[1]}}
    end
  end
  h.geometry=Wheel.index(h.wheels,h.ids,h.flexbodies,h.definitions)
  function h.frame(time,states)
    local result={time=time,origin={0,0,0},nodes={}}
    local function put(cid,p,v)
      local k=h.offsets[cid]
      for i=1,3 do result.nodes[k+i-1],result.nodes[k+i+2]=p[i],v[i] end
      result.nodes[k+6]=1
    end
    put(10,{0,0,-.2},{0,0,0});put(20,{0,0,.2},{0,0,0})
    for key,group in pairs(h.groups) do
      local state=states[key] or (group.kind=='helper' and states[group.name..'tire']) or {}
      local angle,tilt=state.angle or 0,state.tilt or 0
      local center=state.center or {0,0,group.z}
      local translation=state.velocity or {0,0,0}
      local sx,sy=state.sx or 1,state.sy or 1
      local spin=state.speed or 0
      local ca,sa,ct,st=math.cos(angle),math.sin(angle),math.cos(tilt),math.sin(tilt)
      for _,cid in ipairs(group.ids) do
        local p=group.points[cid]
        local x,y=p[1]*sx*ca-p[2]*sy*sa,p[1]*sx*sa+p[2]*sy*ca
        local position={center[1]+x*ct+p[3]*st,center[2]+y,center[3]-x*st+p[3]*ct}
        local velocity={translation[1]-y*spin*ct,translation[2]+x*spin,translation[3]+y*spin*st}
        put(cid,position,velocity)
      end
    end
    return result
  end
  function h.point(plans,cid)
    local k=h.offsets[cid]
    assert(plans[k],'Missing plan for node '..cid)
    return Wheel.position(plans[k],k)
  end
  function h.assertFrame(plans,expected,list)
    for _,cid in ipairs(list) do
      local x,y,z=h.point(plans,cid);local k=h.offsets[cid]
      near(x,expected.nodes[k],'Node '..cid..' x')
      near(y,expected.nodes[k+1],'Node '..cid..' y')
      near(z,expected.nodes[k+2],'Node '..cid..' z')
    end
  end
  return h
end

test('stock pressure-wheel hub and tread rings both preserve radius',function()
  local h=assembly(false)
  assert(#h.geometry==2,'Stock rim and tread must both be indexed')
  local a=h.frame(0,{})
  local spin=math.pi/.05
  local b=h.frame(.05,{leftrim={angle=math.pi,speed=spin},lefttire={angle=math.pi,speed=spin}})
  a=h.frame(0,{leftrim={speed=spin},lefttire={speed=spin}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{leftrim={angle=math.pi/2},lefttire={angle=math.pi/2}})
  h.assertFrame(plans,expected,h.groups.leftrim.ids)
  h.assertFrame(plans,expected,h.groups.lefttire.ids)
  assert(plans[h.offsets[h.groups.leftrim.ids[1]]]~=plans[h.offsets[h.groups.lefttire.ids[1]]],
    'Rim and detachable tire need independent transforms')
end)

test('rigidly moving helper and carcass rings keep their flexbody anchors aligned',function()
  local h=assembly(true)
  local spin=math.pi/.05
  local a=h.frame(0,{lefttire={speed=spin}})
  local b=h.frame(.05,{lefttire={angle=math.pi,speed=spin}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{lefttire={angle=math.pi/2}})
  local memberships={}
  for _,group in ipairs(h.geometry) do memberships[group.kind]=#group.nodes end
  assert(memberships.tire==8 and memberships.helper==8,'Tread and helper ownership must stay distinct and deduplicated')
  h.assertFrame(plans,expected,h.flexbodies[1]._group_nodes)
  h.assertFrame(plans,expected,h.groups.leftrim.ids)
end)

test('a slipping inner helper half-turn preserves its bore while the tread stays still',function()
  local h=assembly(true)
  local spin,tilt=math.pi/.05,math.pi/4
  local a=h.frame(0,{lefthelper={speed=spin,tilt=tilt}})
  local b=h.frame(.05,{lefthelper={angle=math.pi,speed=spin,tilt=tilt}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{lefthelper={angle=math.pi/2,tilt=tilt}})
  h.assertFrame(plans,expected,h.groups.lefttire.ids)
  h.assertFrame(plans,expected,h.groups.lefthelper.ids)
  h.assertFrame(plans,expected,h.groups.leftrim.ids)
  local helperPlan=plans[h.offsets[h.groups.lefthelper.ids[1]]]
  near(helperPlan.u[1],math.sin(tilt));near(helperPlan.u[2],0);near(helperPlan.u[3],math.cos(tilt))
  for _,cid in ipairs(h.groups.lefthelper.ids) do
    local x,y,z=h.point(plans,cid)
    local axial=x*helperPlan.u[1]+y*helperPlan.u[2]+z*helperPlan.u[3]
    near(x*x+y*y+z*z-axial*axial,.25,'Helper bore radius squared')
    near(math.abs(axial),.2,'Helper ring half width')
  end
end)

test('free tire spins and tilts around its own moving center far from the axle',function()
  local h=assembly(true)
  local angle=2.5*math.pi;local spin=angle/.05
  local moving={120,45,-15}
  local a=h.frame(0,{lefttire={speed=spin,velocity=moving}})
  local b=h.frame(.05,{lefttire={angle=angle,speed=spin,tilt=math.pi/3,center={8,4,2},velocity=moving}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{lefttire={angle=angle/2,tilt=math.pi/6,center={4,2,1}}})
  h.assertFrame(plans,expected,h.flexbodies[1]._group_nodes)
  h.assertFrame(plans,expected,h.groups.leftrim.ids)
  local plan=plans[h.offsets[h.groups.lefttire.ids[1]]]
  near(plan.center[1],4);near(plan.center[2],2);near(plan.center[3],1)
end)

test('coaxial dually wheels retain separate tire and helper ownership',function()
  local h=assembly(true,true)
  local leftSpeed,rightSpeed=math.pi/.05,-math.pi/.05
  local a=h.frame(0,{lefttire={speed=leftSpeed},leftOutertire={speed=rightSpeed}})
  local b=h.frame(.05,{lefttire={angle=math.pi,speed=leftSpeed,center={6,0,-.65}},
    leftOutertire={angle=-math.pi,speed=rightSpeed,center={-4,0,.65}}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{lefttire={angle=math.pi/2,center={3,0,-.65}},
    leftOutertire={angle=-math.pi/2,center={-2,0,.65}}})
  for _,fb in ipairs(h.flexbodies) do h.assertFrame(plans,expected,fb._group_nodes) end
  h.assertFrame(plans,expected,h.groups.leftrim.ids)
  h.assertFrame(plans,expected,h.groups.leftOuterrim.ids)
  assert(plans[h.offsets[h.groups.lefthelper.ids[1]]]~=plans[h.offsets[h.groups.leftOuterhelper.ids[1]]],
    'Sharing axle node IDs must not merge distinct tires')
end)

test('tire and helper deformation survives interpolation without repairing the shape',function()
  local h=assembly(true)
  local spin=math.pi/.05
  local a=h.frame(0,{lefttire={speed=spin}})
  local b=h.frame(.05,{lefttire={angle=math.pi,speed=spin,sx=.6,sy=.8}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{lefttire={angle=math.pi/2,sx=.8,sy=.9}})
  h.assertFrame(plans,expected,h.flexbodies[1]._group_nodes)
  -- Endpoint samples remain the recorded deformed shape, without rewriting it.
  assert(next(Wheel.plans(h.geometry,a,b,0))==nil)
  assert(next(Wheel.plans(h.geometry,a,b,1))==nil)
  assert(next(Wheel.plans(h.geometry,a,a,.5))==nil)
  local first=h.offsets[h.groups.lefttire.ids[1]]
  near(a.nodes[first],1);near(b.nodes[first],-.6)
end)

test('deformed helper cages do not move the carcass center or axle',function()
  local h=assembly(true)
  local a=h.frame(0,{lefthelper={center={.4,0,0}}})
  local b=h.frame(.05,{lefthelper={center={.8,0,0}}})
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{lefthelper={center={.6,0,0}}})
  h.assertFrame(plans,expected,h.flexbodies[1]._group_nodes)
  local plan=plans[h.offsets[h.groups.lefttire.ids[1]]]
  near(plan.center[1],0);near(plan.center[2],0);near(plan.center[3],0)
  near(plan.u[1],0);near(plan.u[2],0);near(plan.u[3],1)
end)

test('a displaced helper cannot invent spin or shrink a stationary carcass',function()
  local h=assembly(true)
  local a,b=h.frame(0,{}),h.frame(.05,{})
  local helper=h.offsets[h.groups.lefthelper.ids[1]]
  -- One stretched anchor is now farther from the center than any tread node.
  -- Its unrelated diagonal velocity must not become the wheel's spin estimate.
  a.nodes[helper],a.nodes[helper+1]=2,0
  b.nodes[helper],b.nodes[helper+1]=0,2
  for _,sample in ipairs({a,b}) do sample.nodes[helper+3],sample.nodes[helper+4]=-40,40 end
  local plans=Wheel.plans(h.geometry,a,b,.5)
  local expected=h.frame(.025,{})
  h.assertFrame(plans,expected,h.groups.lefttire.ids)
  -- A deformed helper follows its independent frame or the ordinary fallback;
  -- either may differ from linear point motion, but neither may contaminate tread.
  for _,cid in ipairs(h.groups.lefthelper.ids) do
    local k=h.offsets[cid]
    local x,y,z
    if plans[k] then x,y,z=Wheel.position(plans[k],k)
    else x,y,z=(a.nodes[k]+b.nodes[k])*.5,(a.nodes[k+1]+b.nodes[k+1])*.5,(a.nodes[k+2]+b.nodes[k+2])*.5 end
    assert(x==x and y==y and z==z and x*x+y*y+z*z<9,'Helper interpolation became nonfinite or unbounded')
  end
end)
print('WHEEL_SPEC_DONE '..count)
