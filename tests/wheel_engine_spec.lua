-- Uses stock JBeam wheel definitions and native FFI node snapshots.
-- Supply testWheelSource in the console host; no game files are modified.
require('lua/console/console-lib').initConsole()
local engine=initBeamEngine(2000)
local source=assert(testWheelSource)
wheelProbeDone=0
for id,model in ipairs({'pickup','sunburst2','citybus','rockbouncer'}) do
  local directory='vehicles/'..model..'/'
  local bundle=assert(require('jbeam/loader').loadVehicleStage1(id,directory,nil))
  local car=assert(engine:spawnObject2(id,directory,lpack.encode({vdata=bundle.vdata,config=bundle.config}),Vector3(0,0,30)))
  car:queueLuaCommand(string.format([[
    local Wheel=assert(loadstring(%q))()
    local ffi=require('ffi')
    local ids={}
    for _,n in pairs(v.data.nodes) do ids[#ids+1]=n.cid end
    table.sort(ids)
    local geometry=Wheel.index(v.data.wheels,ids,v.data.flexbodies,v.data.nodes)
    assert(#geometry>0, 'Stock vehicle has no mapped wheels')
    local origin=obj:getPosition()
    local a={time=0,origin={origin.x,origin.y,origin.z},nodes=ffi.new('float[?]',#ids*7)}
    local b={time=0.05,origin={origin.x,origin.y,origin.z},nodes=ffi.new('float[?]',#ids*7)}
    for i,cid in ipairs(ids) do
      local k=(i-1)*7
      local p=obj:getNodePosition(cid)
      a.nodes[k],a.nodes[k+1],a.nodes[k+2]=p.x,p.y,p.z
      a.nodes[k+3],a.nodes[k+4],a.nodes[k+5],a.nodes[k+6]=0,0,0,obj:getNodeMass(cid)
    end
    ffi.copy(b.nodes,a.nodes,ffi.sizeof(a.nodes))
    local spin=2.5*math.pi
    local function point(frame,k) return vec3(frame.nodes[k],frame.nodes[k+1],frame.nodes[k+2]) end
    local function rotate(r,u,angle)
      return r*math.cos(angle)+u:cross(r)*math.sin(angle)+u*(u:dot(r)*(1-math.cos(angle)))
    end
    local expected={}
    for _,w in ipairs(geometry) do
      local center=(point(a,w.a)+point(a,w.b))*0.5
      local axis=(point(a,w.b)-point(a,w.a)):normalized()
      for _,k in ipairs(w.nodes) do
        local r=point(a,k)-center
        local rotated=rotate(r,axis,spin)
        local p=center+rotated
        b.nodes[k],b.nodes[k+1],b.nodes[k+2]=p.x,p.y,p.z
        local va=axis:cross(r)*(spin/0.05)
        local vb=axis:cross(rotated)*(spin/0.05)
        a.nodes[k+3],a.nodes[k+4],a.nodes[k+5]=va.x,va.y,va.z
        b.nodes[k+3],b.nodes[k+4],b.nodes[k+5]=vb.x,vb.y,vb.z
        expected[k]=center+rotate(r,axis,spin*0.5)+vec3(origin)
      end
    end
    local plans=Wheel.plans(geometry,a,b,0.5)
    local checked,maxError=0,0
    for k,wanted in pairs(expected) do
      assert(plans[k], 'Native wheel topology unexpectedly rejected')
      local x,y,z=Wheel.position(plans[k],k)
      local error=(vec3(x,y,z)-wanted):length()
      maxError=math.max(maxError,error)
      assert(error<0.0001, 'Wheel interpolation changed its native shape')
      checked=checked+1
    end
    print('WHEEL_ENGINE_PASS model=%s wheels='..#geometry..' nodes='..checked..' maxError='..maxError)
    obj:queueGameEngineLua('wheelProbeDone=wheelProbeDone+1')
  ]],source,model))
  for _=1,12 do engine:update(0.001,0) end
  assert(wheelProbeDone==id, 'Native wheel test did not complete for '..model)
end
print('WHEEL_ENGINE_SPEC_DONE '..wheelProbeDone)
