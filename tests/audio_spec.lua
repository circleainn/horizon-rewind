local made={}
local env=setmetatable({Engine={Audio={}},scenetree={},log=function() end},{__index=_G})
env.Engine.Audio.createSource=function(channel,path)
  assert(channel=='AudioGui' and path:find('/art/sound/horizonRewind/rewind',1,true))
  local e={path=path}
  function e:play() self.playing=true end
  function e:isPlaying() return self.playing==true end
  function e:setVolume(v) self.volume=v end
  made[#made+1]=e;return #made
end
env.Engine.Audio.deleteSource=function(id) made[id].deleted=true;made[id].playing=false end
env.scenetree.findObjectById=function(id) return made[id] end
local mod=setfenv(assert(loadstring(testAudioSource)),env)()
mod.update(false,2,.1);assert(#made==0)
mod.update(true,.25,.1);local e=made[1]
assert(e.playing and e.volume>0,'File source has zero gain')
assert(e.path:find('025.wav',1,true))
mod.update(true,8,.1);assert(e.deleted and #made==2)
e=made[2];assert(e.path:find('800.wav',1,true) and e.volume>0)
e.playing=false;mod.update(true,8,.1);assert(e.playing,'Cue did not repeat')
for _=1,20 do mod.update(false,8,.02) end
assert(e.deleted and not e.playing,'Sound outlived rewind')
mod.update(true,1,.1);mod.stop();assert(made[3].deleted)
env.Engine.Audio.createSource=function() return 0 end
mod.update(true,1,.1);assert(mod.getStatus().failed)
print('AUDIO_SPEC_PASSED: real source gain, pitch, looping, teardown, failure isolation')
