--@name Rabbit Radio
--@author Sayuri
--@shared

-- Version number
VERSION_MAJOR = 0
VERSION_MINOR = 1

-- If 1 then doesnt actually play music (for testing)
RADIO_DISARM = 0

-- Wire integration
if SERVER then
    wire.adjustInputs({"PlayNext","RequestNumber","PlayRequest"},{"normal","normal","normal"})
    wire.adjustOutputs({"SongSource","SongTitle","Text"},{"string","string","string"})
    function rrwUpdateSongInfo(ss,st)
        wire.ports.SongSource = ss
        wire.ports.SongTitle = st
        wire.ports.Text = ss .. "\n" .. st
    end
end

-- Status hologram
if CLIENT then
    -- Drawing config
    TITLE_FONT = render.createFont("Tahoma",80,300)
    SOURCE_FONT = render.createFont("Tahoma",60,300)
    INFO_FONT = render.createFont("Tahoma",40,300)
    CLEAR_COLOR = Color(0,0,0,0)
    OUTLINE_COLOR = Color(0,0,0)
    OUTLINE_RADIUS = 3
    OUTLINE_RADIUS_2 = OUTLINE_RADIUS*0.5
    LINE_SIZE = 70
    DRAW_INTERVAL = 0.25
    -- Create the objects we need
    render.createRenderTarget("rr_context")
    rrMaterial = material.create("UnlitGeneric")
    rrMaterial:setTextureRenderTarget("$basetexture","rr_context")
    rrMaterial:setInt("$flags",256)
    rrHolo = holograms.create(owner():localToWorld(Vector(0,0,0)),Angle(0,0,0),"models/hunter/plates/plate1x1.mdl")
    rrHolo:setMaterial("!" .. rrMaterial:getName())
    -- Status strings
    rrDrawSongTitle = "..."
    rrDrawSongSource = "..."
    rrDrawSongCover = ""
    rrDrawSongOriginal = ""
    -- Draws outlined text
    function rrDrawText(x,y,str,col)
        render.setColor(OUTLINE_COLOR)
        render.drawText(x+OUTLINE_RADIUS,y,str,0)
        render.drawText(x-OUTLINE_RADIUS,y,str,0)
        render.drawText(x,y+OUTLINE_RADIUS,str,0)
        render.drawText(x,y-OUTLINE_RADIUS,str,0)
        render.drawText(x+OUTLINE_RADIUS_2,y+OUTLINE_RADIUS_2,str,0)
        render.drawText(x-OUTLINE_RADIUS_2,y-OUTLINE_RADIUS_2,str,0)
        render.drawText(x-OUTLINE_RADIUS_2,y+OUTLINE_RADIUS_2,str,0)
        render.drawText(x+OUTLINE_RADIUS_2,y-OUTLINE_RADIUS_2,str,0)
        render.setColor(col)
        render.drawText(x,y,str,0)
    end
    -- Handle rendering
    rrDrawLastTime = timer.realtime()
    function rrDraw()
        if (timer.realtime()-rrDrawLastTime) < DRAW_INTERVAL then
            return
        end
        rrDrawLastTime = timer.realtime()
        local dx = OUTLINE_RADIUS
        local dy = OUTLINE_RADIUS
        render.selectRenderTarget("rr_context")
        render.clear(CLEAR_COLOR)
        -- What's the title of the music?
        local ss = string.split(rrDrawSongTitle,"|")
        local t1 = ss[1]
        local t2 = ss[2]
        render.setFont(TITLE_FONT)
        rrDrawText(dx,dy,"MUSIC:",Color(255,128,255))
        dy = dy+LINE_SIZE
        rrDrawText(dx,dy,t1,Color(255,255,255))
        dy = dy+LINE_SIZE
        if t2 ~= nil then
            rrDrawText(dx,dy,t2,Color(255,255,255))
        end
        dy = dy+LINE_SIZE*1.5
        -- Where is it from?
        local ss = string.split(rrDrawSongSource,"|")
        local s1 = ss[1]
        local s2 = ss[2]
        render.setFont(SOURCE_FONT)
        rrDrawText(dx,dy,"From:",Color(120,120,255))
        dy = dy+LINE_SIZE*0.7
        rrDrawText(dx,dy,s1,Color(120,120,120))
        dy = dy+LINE_SIZE*0.7
        if s2 ~= nil then
            rrDrawText(dx,dy,s2,Color(120,120,120))
        end
        dy = dy+LINE_SIZE*0.7
        dy = dy+LINE_SIZE*0.7
        -- Was this a cover?
        if string.len(rrDrawSongCover) > 1 then
            render.setFont(INFO_FONT)
            rrDrawText(dx,dy,"Cover Of:",Color(20,170,20))
            dy = dy+LINE_SIZE*0.5
            rrDrawText(dx,dy,rrDrawSongCover,Color(120,120,120))
            dy = dy+LINE_SIZE*0.5
            dy = dy+LINE_SIZE*0.5
        end
        -- Original author?
        if string.len(rrDrawSongOriginal) > 1 then
            render.setFont(INFO_FONT)
            rrDrawText(dx,dy,"Original Artist:",Color(170,20,20))
            dy = dy+LINE_SIZE*0.5
            rrDrawText(dx,dy,rrDrawSongOriginal,Color(120,120,120))
        end
    end
    hook.add("renderoffscreen","rr_draw",rrDraw)
    -- Attach to player
    function rrAttachHolo()
        local pos = owner():getPos()
        pos:add(Vector(0,0,80))
        local ang = Angle(90,owner():getAngles().yaw+90,90)
        rrHolo:setPos(pos)
        rrHolo:setAngles(ang)
    end
    hook.add("think","rr_attach_holo",rrAttachHolo)
end

-- Config
PLAY_VOLUME = 0.8

PLAY_FAIL = 0
PLAY_SUCCEED = 1
PLAY_RETRY = 2
PLAY_AWAIT = 3

TIME_BETWEEN_SONGS = 4.0
TIMEOUT_TIME = 10.0

RETRY_MAX = 5

-- Music library
rrTrackList = {}
function rrMakeTrack(url,src,name,cover,original)
    local tup = {}
    if src == nil or name == nil or cover == nil or original == nil then
        return nil
    end
    tup["url"] = url
    tup["src"] = src
    tup["name"] = name
    tup["cover"] = cover
    tup["original"] = original
    return tup
end
function rrAddTrack(url,src,name,cover,original)
    local n = (#rrTrackList+1)
    local tup = rrMakeTrack(url,src,name,cover,original)
    if tup == nil then
        error("Track " .. url .. " is missing fields")
        return
    end
    rrTrackList[n] = tup
end
if SERVER then
    rrTrackOrder = {}
    rrCurrentTrack = 0
    rrPlayStatus = {}
    rrPlayIssueTime = {}
    rrRetryCount = {}
    -- Creates a shuffled list of index values
    function rrShuffle()
        local to = {}
        local ret = {}
        for n = 1,#rrTrackList do
            to[n] = n
        end
        while #to > 0 do
            local r = math.random(#to)
            local i = (#ret+1)
            ret[i] = to[r]
            -- ret[i] = 4
            table.remove(to,r)
        end
        return ret
    end
    -- Advances to the next song
    function rrNext()
        rrCurrentTrack = rrCurrentTrack+1
        if rrCurrentTrack > #rrTrackOrder then
            rrTrackOrder = rrShuffle()
            rrCurrentTrack = 1
        end
        return rrTrackOrder[rrCurrentTrack]
    end
    -- Resets playing status
    function rrResetPlayStatus()
        rrPlayStatus = {}
        local pls = find.allPlayers()
        for k,v in pairs(pls) do
            local uid = v:getSteamID()
            rrPlayStatus[uid] = PLAY_AWAIT
            rrPlayIssueTime[uid] = timer.realtime()
            rrRetryCount[uid] = 0
        end
    end
    -- Responds to next queries from client
    function rrChooseNextSong(si)
        local tup = rrTrackList[si]
        rrwUpdateSongInfo(tup["src"],tup["name"])
        rrResetPlayStatus()
        print("Your next song is: " .. si)
        net.start("rr_play")
        net.writeInt(si,8)
        net.send(find.allPlayers())
    end
    function rrRecvNextAction()
        local ret = rrNext()
        rrChooseNextSong(ret)
    end
    function rrRecvNext(len,ply)
        if ply == owner() then
            rrRecvNextAction()
        end
    end
    net.receive("rr_next",rrRecvNext)
    -- Alerts the owner if people can play the song or not
    function rrRecvConfirm(len,ply)
        local code = net.readInt(8)
        local index = net.readInt(8)
        local name = net.readString()
        local uid = ply:getSteamID()
        rrPlayStatus[uid] = code
        net.start("rr_confirm")
        net.writeInt(code,8)
        net.writeString(ply:getName())
        net.writeInt(index,8)
        net.writeString(name)
        net.send(owner())
    end
    net.receive("rr_confirm",rrRecvConfirm)
    -- Retries to play the current song for someone
    function rrRetryFor(ply)
        local uid = ply:getSteamID()
        net.start("rr_play")
        net.writeInt(rrTrackOrder[rrCurrentTrack],8)
        net.send(ply)
        local val = rrRetryCount[uid]
        val = val+1
        rrRetryCount[uid] = val
    end
    -- Retries for people who weren't able to play
    function rrHandleRetry()
        local pls = find.allPlayers()
        for k,v in pairs(pls) do
            local uid = v:getSteamID()
            local pstat = rrPlayStatus[uid]
            local itime = rrPlayIssueTime[uid]
            local rtcount = rrRetryCount[uid]
            if pstat ~= nil then
                if rtcount < RETRY_MAX then
                    if pstat == PLAY_FAIL then
                        -- print("Retrying for " .. v:getName() .. "..")
                        rrPlayStatus[uid] = PLAY_RETRY
                        rrRetryFor(v)
                    elseif pstat == PLAY_AWAIT then
                        local delta = timer.realtime()-itime
                        if delta > TIMEOUT_TIME then
                            -- print("Timed out for " .. v:getName() .. ", retrying..")
                            rrPlayIssueTime[uid] = timer.realtime()
                            rrRetryFor(v)
                        end
                    end
                end
            end
        end
    end
    hook.add("think","rr_handle_retry",rrHandleRetry)
end

-- Wire commands for controlling radio
if SERVER then
    rrWireRequestNumber = 0
    function rrWireReact(inp,val)
        if inp == "PlayNext" then
            if val ~= 0 then
                rrRecvNextAction()
            end
        end
        if inp == "RequestNumber" then
            rrWireRequestNumber = val
        end
        if inp == "PlayRequest" then
            if val ~= 0 then
                rrChooseNextSong(rrWireRequestNumber)
            end
        end
    end
    hook.add("input","rr_wire_react",rrWireReact)
end

-- Chat commands for controlling radio directly
if SERVER then
    function rrChatCommand(ply,text,tc)
        if ply == owner() then
            if text == "!rrnext" then
                rrRecvNextAction()
            else
                if string.startWith(text,"!rr") then
                    local ss = string.split(text," ")
                    rrChooseNextSong(tonumber(ss[2]))
                end
            end
        end
    end
    hook.add("PlayerSay","rr_chat_command",rrChatCommand)
end

-- Attempts to play music
if CLIENT then
    rrPlayingSong = nil
    rrNextSent = 0
    rrPlayTime = 0.0
    rrTimeLeft = 0.0
    rrPlayCommand = 0
    rrPlayCommandName = nil
    -- After the song has loaded, this starts playing it
    function rrLoaded(song,err,name)
        if rrPlayingSong ~= nil then
            rrPlayingSong:stop()
        end
        rrPlayingSong = song
        if rrPlayingSong~= nil and rrPlayingSong:isValid() then
            rrPlayingSong:play()
            rrPlayingSong:setVolume(PLAY_VOLUME)
            rrTimeLeft = rrPlayingSong:getLength()+TIME_BETWEEN_SONGS
            rrPlayTime = timer.realtime()
            if player() == owner() then
                rrNextSent = 2
            end
            net.start("rr_confirm")
            net.writeInt(PLAY_SUCCEED,8)
            net.writeInt(rrPlayCommand,8)
            net.writeString(rrPlayCommandName)
            net.send()
        else
            net.start("rr_confirm")
            net.writeInt(PLAY_FAIL,8)
            net.writeInt(rrPlayCommand,8)
            net.writeString(rrPlayCommandName)
            net.send()
        end
    end
    -- This command attempts to play a URL
    function rrPlay(url)
        bass.loadURL(url,"3d noblock",rrLoaded)
    end
    -- This command plays what the server tells it
    function rrRecvPlay(len,ply)
        local i = net.readInt(8)
        local tup = rrTrackList[i]
        if RADIO_DISARM == 0 then
            rrPlay(tup["url"])
        end
        rrPlayCommand = i
        rrPlayCommandName = tup["src"] .. " - " .. tup["name"]
        rrDrawSongTitle = tup["name"]
        rrDrawSongSource = tup["src"]
        rrDrawSongCover = tup["cover"]
        rrDrawSongOriginal = tup["original"]
    end
    net.receive("rr_play",rrRecvPlay)
    -- This command alerts the owner about people playing or not
    function rrRecvConfirmOwner(len,ply)
        local code = net.readInt(8)
        local who = net.readString()
        local index = net.readInt(8)
        local name = net.readString()
        if code == 1 then
            print(who .. " was able to play song " .. index .. ": " .. name)
        else
            -- print(who .. " was not able to play it")
        end
    end
    net.receive("rr_confirm",rrRecvConfirmOwner)
    -- This handles client action
    function rrMain()
        -- Attach playing song to the owner
        if rrPlayingSong ~= nil then
            rrPlayingSong:setPos(owner():getPos())
        end
        -- Uses the owner's client to control tracks
        if player() == owner() then
            -- Start next
            if rrNextSent == 0 then
                net.start("rr_next")
                net.send()
                rrNextSent = 1
            end
            -- Monitor for song end
            if rrNextSent == 2 then
                local delta = timer.realtime()-rrPlayTime
                if delta > rrTimeLeft then
                    rrNextSent = 0
                end
            end
        end
    end
    hook.add("think","rr_main",rrMain)
end

-- Tracklist
-- rrAddTrack(<file URL>,<Album/Work/Author>,<Title>,<Cover Of>,<Author/Original Author>)

-- Invoke
if SERVER then
    rrTrackOrder = rrShuffle()
    local trackliststr = ""
    for n = 1,#rrTrackOrder do
        trackliststr = trackliststr .. rrTrackOrder[n] .. " "
    end
    -- print(trackliststr)
end
if CLIENT then
    print("Rabbit Radio V" .. VERSION_MAJOR .. "." .. VERSION_MINOR .. " started")
end
