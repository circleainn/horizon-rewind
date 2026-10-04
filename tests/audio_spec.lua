local made={}
local env=setmetatable({
  createObject=function(class)
    assert(class=='SFXEmitter')
    local e={fields={}}
    function e:setField(name,_,value) self.fields[name]=value end
    function e:registerObject() end
    function e:play() self.playing=true end
    function e:stop() self.playing=false end
    function e:delete() self.deleted=true end
    function e:setVolumePitchCT(volume,pitch) self.volume,self.pitch=volume,pitch end
    made[#made+1]=e;return e
  end,
  scenetree={}, log=function() end
},{__index=_G})
local mod=setfenv(assert(loadstring(testAudioSource)),env)()
mod.update(false,2,.1);assert(#made==0)
mod.update(true,.25,.1);local e=made[1]
assert(e.playing and e.fields.sourceGroup=='AudioGui' and e.fields.isLooping=='1')
local slow=e.pitch
mod.update(true,8,.1);assert(e.pitch>slow and #made==1)
for _=1,20 do mod.update(false,8,.02) end
assert(e.deleted and not e.playing,'Sound outlived rewind')
mod.update(true,1,.1);mod.stop();assert(made[2].deleted)
env.createObject=function() error('Audio unavailable') end
mod.update(true,1,.1);mod.update(true,1,.1) -- optional audio cannot stop rewind
print('AUDIO_SPEC_PASSED: lifecycle, pitch, silence, failure isolation')
