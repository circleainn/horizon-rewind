-- Inject testRecoverySource for BeamNG's sandboxed console, or run with Lua.
local scriptPath=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local scriptDirectory=scriptPath:match('^(.*)/') or '.'
local factory=testRecoverySource and assert(loadstring(testRecoverySource))
  or assert(loadfile(scriptDirectory..'/../mod/lua/vehicle/extensions/horizonRewindRecovery.lua'))
local passed=0
local function eq(a,b,label) assert(a==b,(label or 'value')..': expected '..tostring(b)..', got '..tostring(a)) end
local function fixture()
  local f={starts=0,stops=0,resets=0,updates=0,down=0,up=0,position=11,acks={}}
  f.record=function() end
  f.nativeUpdate=function() f.updates=f.updates+1 end
  f.start=function(alt)
    f.starts=f.starts+1; f.alt=alt; f.pressPosition=f.position
    recovery.updateGFX=f.nativeUpdate
  end
  f.stop=function(player)
    f.stops=f.stops+1; f.player=player
    if recovery.updateGFX==f.record then return end
    f.position=f.pressPosition; f.resets=f.resets+1; recovery.updateGFX=f.record
  end
  recovery={startRecovering=f.start,stopRecovering=f.stop,updateGFX=f.record}
  extensions={horizonRewind={
    recoveryDown=function(id,token) eq(id,17); f.down=f.down+1; f.downToken=token end,
    recoveryUp=function(id,token) eq(id,17); f.up=f.up+1; f.upToken=token; f.resetsWhenUp=f.resets end,
    recoveryTakenOver=function(id,token,accepted) eq(id,17); f.acks[#f.acks+1]={token,accepted} end
  }}
  obj={getId=function() return 17 end, queueGameEngineLua=function(_,code) assert(loadstring(code))() end}
  f.module=factory()
  f.module.configure(9,true)
  return f
end
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error(name..': '..tostring(err),0) end
  passed=passed+1; print('PASS recovery '..name)
end

test('tap preserves press pose, alternate mode and player',function()
  local f=fixture(); recovery.startRecovering(true)
  eq(f.starts,1); eq(f.alt,true); eq(f.downToken,9)
  recovery.updateGFX(3); eq(f.updates,0,'native wireframe gated')
  f.position=55; recovery.stopRecovering(2)
  eq(f.position,11); eq(f.resets,1); eq(f.player,2); eq(f.up,1); eq(recovery.updateGFX,f.record)
  eq(f.resetsWhenUp,1,'native stop precedes GE release notification')
end)
test('repeated down and up are ignored',function()
  local f=fixture(); recovery.startRecovering(); recovery.startRecovering(true)
  eq(f.starts,1); eq(f.down,1); eq(f.alt,nil)
  recovery.stopRecovering(0); recovery.stopRecovering(0)
  eq(f.stops,1); eq(f.up,1)
end)
test('takeover restores native recorder and consumes release',function()
  local f=fixture(); recovery.startRecovering(); f.position=55
  eq(f.module.takeOver(9),true); eq(recovery.updateGFX,f.record)
  eq(f.acks[1][1],9); eq(f.acks[1][2],true)
  eq(f.module.takeOver(9),false); recovery.stopRecovering(0)
  eq(f.position,55); eq(f.stops,0); eq(f.resets,0); eq(f.up,1)
end)
test('takeover after release and stale tokens cannot arm rewind',function()
  local f=fixture(); recovery.startRecovering()
  eq(f.module.takeOver(8),false); recovery.stopRecovering(0)
  eq(f.module.takeOver(9),false); eq(f.module.passthrough(9),false)
  eq(f.acks[1][1],8); eq(f.acks[1][2],false); eq(f.acks[2][2],false)
  eq(recovery.updateGFX,f.record); eq(f.resets,1)
end)
test('passthrough hands long hold back to stock',function()
  local f=fixture(); recovery.startRecovering(true)
  eq(f.module.passthrough(9),true); eq(recovery.updateGFX,f.nativeUpdate)
  recovery.updateGFX(1); eq(f.updates,1); eq(f.module.takeOver(9),false)
  recovery.stopRecovering(3); eq(f.resets,1); eq(f.player,3)
end)
test('disable cancels pending gate without resetting old vehicle',function()
  local f=fixture(); recovery.startRecovering(); f.position=55
  f.module.configure(9,false)
  eq(recovery.startRecovering,f.start); eq(recovery.stopRecovering,f.stop)
  eq(recovery.updateGFX,f.record); eq(f.position,55); eq(f.resets,0)
  recovery.stopRecovering(0); eq(f.resets,0)
end)
test('unload after takeover restores only owned functions',function()
  local f=fixture(); recovery.startRecovering(); f.module.takeOver(9)
  f.module.onExtensionUnloaded()
  eq(recovery.startRecovering,f.start); eq(recovery.stopRecovering,f.stop)
  eq(recovery.updateGFX,f.record); eq(f.resets,0)
end)
test('disable cancels native passthrough without resetting',function()
  local f=fixture(); recovery.startRecovering(); f.module.passthrough(9)
  f.module.configure(9,false); eq(recovery.updateGFX,f.record); eq(f.resets,0)
end)
test('external wrapper ownership survives unload and re-enable',function()
  local f=fixture(); local priorStart,priorStop=recovery.startRecovering,recovery.stopRecovering
  local outerStart=function(alt) return priorStart(alt) end
  local outerStop=function(player) return priorStop(player) end
  recovery.startRecovering,recovery.stopRecovering=outerStart,outerStop
  f.module.configure(9,false)
  eq(recovery.startRecovering,outerStart); eq(recovery.stopRecovering,outerStop)
  recovery.startRecovering(true); recovery.stopRecovering(3)
  eq(f.starts,1); eq(f.resets,1); eq(f.down,0)
  f.module.configure(10,true); recovery.startRecovering(false); recovery.stopRecovering(2)
  eq(f.starts,2); eq(f.resets,2); eq(f.down,1); eq(f.downToken,10); eq(f.upToken,10)
end)
test('does not overwrite another owner of updateGFX',function()
  local f=fixture(); recovery.startRecovering()
  local other=function() end; recovery.updateGFX=other
  eq(f.module.takeOver(9),false); f.module.onExtensionUnloaded()
  eq(recovery.updateGFX,other); eq(f.resets,0)
end)
test('reset and new configuration clear pending state',function()
  local f=fixture(); recovery.startRecovering(); f.module.onReset()
  eq(recovery.updateGFX,f.record); eq(f.module.takeOver(9),false)
  f.module.configure(10,true); recovery.startRecovering(); eq(f.downToken,10)
  f.module.configure(11,true); eq(recovery.updateGFX,f.record)
  eq(f.module.takeOver(10),false); recovery.startRecovering(); eq(f.downToken,11)
end)
print('RECOVERY_SPEC_DONE passed='..passed)
