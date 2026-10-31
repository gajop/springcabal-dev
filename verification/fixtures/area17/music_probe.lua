function gadget:GetInfo() return {name='Music playback probe',layer=100000,enabled=true} end
if gadgetHandler:IsSyncedCode() then return false end
local began,previous,steps
function gadget:Initialize()
 began=Spring.GetTimer();previous=-1;steps=0
 Spring.Echo('[MusicProbe] init frame='..Spring.GetGameFrame())
end
function gadget:GameStart() Spring.Echo('[MusicProbe] GAMESTART') end
function gadget:DrawScreen()
 local elapsed=Spring.DiffTimers(Spring.GetTimer(),began)
 local step=math.floor(elapsed*2)
 if step~=previous then
  previous=step
  local played,length=Spring.GetSoundStreamTime()
  Spring.Echo(string.format('[MusicProbe] elapsed=%.2f frame=%d played=%.4f length=%.4f master=%s music=%s',elapsed,Spring.GetGameFrame(),played,length,Spring.GetConfigInt('snd_volmaster',100),Spring.GetConfigInt('snd_volmusic',100)))
 end
 if elapsed>8 then Spring.SendCommands('quitforce') end
end
