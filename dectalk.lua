--@name DECTalk is Classy
--@author Sayuri
--@shared

SPEAK_VOLUME = 9.2
SPEAK_PITCH = 1.0 -- 1.0 is normal voice

-- Server processes talk commands
if SERVER then
    function dtcRecvText(len,ply)
        if ply == owner() then
            local txt = net.readString()
            local pls = find.allPlayers()
            for k,v in pairs(pls) do
                net.start("dtc_speak")
                net.writeString(txt)
                net.send(v)
            end
        end
    end
    net.receive("dtc_talk",dtcRecvText)
end

-- Client renders speech
if CLIENT then
    dtcAudio = nil
    -- Plays the actual speech
    function dtcLoadSpeak(bs,er,nm)
        if dtcAudio ~= nil then
            dtcAudio:stop()
        end
        if bs ~= nil and bs:isValid() then
            bs:play(0)
            bs:setPos(owner():getPos())
            bs:setVolume(SPEAK_VOLUME)
            bs:setPitch(SPEAK_PITCH)
            dtcAudio = bs
        end
    end
    -- Turns text commands into loading text to speech
    function dtcRecvSpeak(len,ply)
        local txt = net.readString()
        local urltxt = "https://tts.cyzon.us/tts?text=" .. string.replace(txt," ","%20")
        bass.loadURL(urltxt,"3d noblock",dtcLoadSpeak)
    end
    net.receive("dtc_speak",dtcRecvSpeak)
end

-- When you chat you send the tts command to server
if CLIENT then
    function dtcChat(ply,text,tm,isded)
        if ply == owner() then
            net.start("dtc_talk")
            net.writeString(text)
            net.send()
        end
    end
    hook.add("PlayerChat","dtc_chat",dtcChat)
end
