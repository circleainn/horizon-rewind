-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Wheel-local interpolation keeps rotating rings from collapsing into chords.
-- All geometry and angular velocity come from the recorded nodes, including
-- deformation; no vehicle names, wheel directions or pristine tire shapes.
local M = {}
local pi, sqrt = math.pi, math.sqrt
local function finite(value) return value == value and value ~= math.huge and value ~= -math.huge end
local function add(a,b) return {a[1]+b[1],a[2]+b[2],a[3]+b[3]} end
local function sub(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
local function mul(a,s) return {a[1]*s,a[2]*s,a[3]*s} end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
local function cross(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
local function unit(a)
  local length=sqrt(dot(a,a))
  if not finite(length) or length<1e-7 then return nil end
  return mul(a,1/length)
end
local function node(f,k) return {f.nodes[k],f.nodes[k+1],f.nodes[k+2]} end
local function velocity(f,k) return {f.nodes[k+3],f.nodes[k+4],f.nodes[k+5]} end
local function mix(a,b,t) return add(mul(a,1-t),mul(b,t)) end
local function radial(p,center,axis)
  local r=sub(p,center)
  return sub(r,mul(axis,dot(r,axis)))
end
local function rotate(v,axis,angle)
  local c,s=math.cos(angle),math.sin(angle)
  return add(add(mul(v,c),mul(cross(axis,v),s)),mul(axis,dot(axis,v)*(1-c)))
end
local function atan2(y,x)
  if math.atan2 then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and pi or -pi) end
  return y>0 and pi/2 or (y<0 and -pi/2 or 0)
end

local function restPosition(nodes,cid)
  local n=nodes and nodes[cid]
  local p=n and n.pos
  if not p then return nil end
  local x,y,z=p.x or p[1],p.y or p[2],p.z or p[3]
  if type(x)~='number' or type(y)~='number' or type(z)~='number' then return nil end
  return {x,y,z}
end

-- Partition the original ring once. Recorded side centroids then follow a free
-- tire's own axle, even after it leaves the car. Rim, tread and added inner
-- rings have separate frames: deflated tires can slip against their supports.
local function indexSides(item,cids,offsets,definitions,wheel)
  local a,b=restPosition(definitions,wheel.node1),restPosition(definitions,wheel.node2)
  local axis=a and b and unit(sub(b,a))
  if not axis then return end
  local points={}
  for _,cid in ipairs(cids) do
    local p=restPosition(definitions,cid)
    if not p then return end
    points[#points+1]={k=offsets[cid],z=dot(sub(p,a),axis)}
  end
  table.sort(points,function(x,y) return x.z<y.z end)
  local gap,split=1e-6,nil
  for i=3,#points-3 do
    local d=points[i+1].z-points[i].z
    if d>gap then gap,split=d,i end
  end
  if not split then return end
  item.low,item.high={},{}
  for i,p in ipairs(points) do
    local side=i<=split and item.low or item.high
    side[#side+1]=p.k
  end
end

function M.index(wheels,nodeIds,flexbodies,nodeDefinitions)
  local offsets,result={},{}
  for i,cid in ipairs(nodeIds) do offsets[cid]=(i-1)*7 end
  for _,w in pairs(wheels or {}) do
    if type(w)=='table' and offsets[w.node1] and offsets[w.node2] and type(w.nodes)=='table' then
      local function ring(ids,kind)
        local item={a=offsets[w.node1],b=offsets[w.node2],nodes={},radius=tonumber(w.radius),name=w.name,kind=kind}
        local seen,cids={},{}
        for _,cid in pairs(ids or {}) do
          local k=offsets[cid]
          if k and k~=item.a and k~=item.b and not seen[k] then
            item.nodes[#item.nodes+1]=k; seen[k]=true; cids[#cids+1]=cid
          end
        end
        if #item.nodes<3 then return nil end
        item.frameNodes={}
        for _,k in ipairs(item.nodes) do item.frameNodes[#item.frameNodes+1]=k end
        indexSides(item,cids,offsets,nodeDefinitions,w)
        result[#result+1]=item
        return item,seen
      end
      ring(w.nodes,'rim')
      local tire=ring(w.treadNodes,'tire')
      if tire and w.name then
        local helpers,seen={},{}
        for _,k in ipairs(tire.nodes) do seen[k]=true end
        for _,cid in pairs(w.nodes) do if offsets[cid] then seen[offsets[cid]]=true end end
        for _,fb in pairs(flexbodies or {}) do
          if type(fb)=='table' and fb._tireDebeadingReplacement==true and fb._tireDebeadingWheel==w.name then
            -- Explicit ownership avoids assigning a dually's helpers to its
            -- coaxial sibling. Unknown custom nodes stay on the ordinary path.
            if type(fb._tireDebeadingHubDuplicateNodeIds)=='table' then
              for _,cid in pairs(fb._tireDebeadingHubDuplicateNodeIds) do
                local k=offsets[cid]
                if k and not seen[k] and k~=tire.a and k~=tire.b then
                  helpers[#helpers+1]=cid; seen[k]=true
                end
              end
            end
          end
        end
        -- The mod initially parks this ring against the rim, then releases it
        -- onto the carcass. Recording its own motion handles both phases and
        -- prevents a relative half-turn from shrinking it through the center.
        ring(helpers,'helper')
      end
    end
  end
  return result
end

local function mean(f,indices,read)
  local sum={0,0,0}
  for _,k in ipairs(indices) do sum=add(sum,read(f,k)) end
  return mul(sum,1/#indices)
end

local function basis(w,f)
  if w.low then
    local low,high=mean(f,w.low,node),mean(f,w.high,node)
    return mix(low,high,0.5),unit(sub(high,low)),mix(mean(f,w.low,velocity),mean(f,w.high,velocity),0.5)
  end
  return mix(node(f,w.a),node(f,w.b),0.5),unit(sub(node(f,w.b),node(f,w.a))),mix(velocity(f,w.a),velocity(f,w.b),0.5)
end

local function angularVelocity(w,f,center,axis,centerVelocity)
  local numerator,denominator=0,0
  for _,k in ipairs(w.frameNodes) do
    local r=radial(node(f,k),center,axis)
    numerator=numerator+dot(cross(r,sub(velocity(f,k),centerVelocity)),axis)
    denominator=denominator+dot(r,r)
  end
  return denominator>1e-8 and numerator/denominator or 0
end

local function prepare(w,a,b,t)
  local ca,ua,va=basis(w,a)
  local cb,ub,vb=basis(w,b)
  if not ua or not ub then return nil end
  local alignment=math.max(-1,math.min(1,dot(ua,ub)))
  if alignment < -0.999 then return nil end -- a destroyed/flipped axle is ambiguous
  local tiltAxis=unit(cross(ua,ub)) or {1,0,0}
  local tilt=math.acos(alignment)
  local best,quality,maxRadius= nil,0,0
  for _,k in ipairs(w.frameNodes) do
    local ra,rb=radial(node(a,k),ca,ua),radial(node(b,k),cb,ub)
    local aa,bb=dot(ra,ra),dot(rb,rb)
    local candidate=math.min(aa,bb)
    if candidate>quality then best,quality=k,candidate end
    maxRadius=math.max(maxRadius,aa,bb)
  end
  -- Reject destroyed rings, measured relative to their own recorded center.
  if not best or quality<1e-8 or (w.radius and w.radius>0 and maxRadius>(w.radius*3)^2) then return nil end
  local ea=unit(radial(node(a,best),ca,ua))
  local eb=unit(radial(node(b,best),cb,ub))
  local transported=rotate(ea,tiltAxis,tilt)
  local principal=atan2(dot(ub,cross(transported,eb)),dot(transported,eb))
  local expected=(angularVelocity(w,a,ca,ua,va)+angularVelocity(w,b,cb,ub,vb))*0.5*(b.time-a.time)
  if not finite(expected) then return nil end
  local spin=principal+2*pi*math.floor((expected-principal)/(2*pi)+0.5)
  local u=rotate(ua,tiltAxis,tilt*t)
  local e=rotate(rotate(ea,ua,spin*t),tiltAxis,tilt*t)
  return {a=a,b=b,t=t,ca=ca,cb=cb,ua=ua,ub=ub,ea=ea,eb=eb,
    fa=cross(ua,ea),fb=cross(ub,eb),u=u,e=e,f=cross(u,e),
    center=mix(add(ca,a.origin),add(cb,b.origin),t),spin=spin}
end

function M.plans(wheels,a,b,alpha)
  local result={}
  if a==b or alpha<=0 or alpha>=1 then return result end
  for _,w in ipairs(wheels) do
    local plan=prepare(w,a,b,alpha)
    if plan then for _,k in ipairs(w.nodes) do result[k]=plan end end
  end
  return result
end

function M.position(plan,k)
  local ra,rb=sub(node(plan.a,k),plan.ca),sub(node(plan.b,k),plan.cb)
  local t=plan.t
  local x=dot(ra,plan.ea)*(1-t)+dot(rb,plan.eb)*t
  local y=dot(ra,plan.fa)*(1-t)+dot(rb,plan.fb)*t
  local z=dot(ra,plan.ua)*(1-t)+dot(rb,plan.ub)*t
  return plan.center[1]+plan.e[1]*x+plan.f[1]*y+plan.u[1]*z,
    plan.center[2]+plan.e[2]*x+plan.f[2]*y+plan.u[2]*z,
    plan.center[3]+plan.e[3]*x+plan.f[3]*y+plan.u[3]*z
end
return M
