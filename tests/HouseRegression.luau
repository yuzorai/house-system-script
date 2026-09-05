-- Edit-mode regression suite. Fake data stores only; never reads or writes player saves.
return function(root)
    local function module(name)
        local fn, reason = loadstring(root:FindFirstChild(name).Source, "=" .. name)
        assert(fn, reason)
        return fn()
    end
    local Geometry, Snapshot = module("HousePlacementGeometry"), module("HouseSnapshot")
    local Data, History = module("HouseDataService"), module("HouseMoveHistory")
    local Validator = module("HouseTemplateValidator")
    local config = module("HouseConfig")
    local function copy(value)
        if typeof(value) ~= "table" then return value end
        local result = {}; for k,v in pairs(value) do result[k] = copy(v) end; return result
    end
    local registry = {SanitizeState = copy, SerializeState = copy,
        GetFunctionName = function(item) return item and item:GetAttribute("HouseFunction") or "None" end,
        HasHandler = function(name) return table.find({"None","Seat","MusicPlayer","EditableSign","ItemDisplay"},name) ~= nil end}
    local schema = module("HouseDataSchema").new(config, registry)
    local checks, trash = {}, {}
    local function object(class, name, parent)
        local item=Instance.new(class); item.Name=name or class; item.Parent=parent
        table.insert(trash,item); return item
    end
    local function check(name, callback)
        local ok, reason=pcall(callback)
        table.insert(checks,{Name=name,Passed=ok,Error=not ok and tostring(reason) or nil})
    end
    local function houseData()
        local data=schema.Default()
        data.SelectedHouse="Physical:1";data.HouseKind="Physical";data.PhysicalHouseId="1"
        data.Placements={{PlacementId="couch",ItemName="Modern Couch",LocalCFrame={CFrame.new():GetComponents()},
            CraftedRecordId="record-oak",CraftedFinish={Wood1Name="Oak",Wood2Name="Oak"},
            FunctionState={EditableSign={Text="A safe example"},MusicPlayer={SoundId="123"}}}}
        return data
    end
    local function fixture()
        local now, serial=1000,0
        local store={Records={},Writes=0,FailBefore=0,FailAfter=0}
        function store:GetAsync(key) return copy(self.Records[key]) end
        function store:UpdateAsync(key, callback)
            self.Writes+=1
            if self.FailBefore>0 then self.FailBefore-=1; error("simulated unavailable store") end
            local nextValue=callback(copy(self.Records[key]))
            if nextValue==nil then return nil end
            self.Records[key]=copy(nextValue)
            if self.FailAfter>0 then self.FailAfter-=1;error("simulated lost acknowledgement") end
            return copy(nextValue)
        end
        local deps={Now=function() return now end,Wait=function() end,Guid=function() serial+=1;return "op-"..serial end,JobId="A"}
        local a=Data.new(store,schema,config,deps)
        local b=Data.new(store,schema,config,deps)
        return a,b,store,function(value) now=value end
    end
    check("New house defaults to Private without furniture",function()
        local a=fixture();local data,handle=a:Acquire(10)
        assert(handle and data.HouseAccess=="Private" and #data.Placements==0 and data.SelectedHouse==nil)
    end)
    check("Shared serializer preserves crafted ID and both woods",function()
        local output=schema.Serialize(houseData()).Placements[1]
        assert(output.CraftedRecordId=="record-oak" and output.CraftedFinish.Wood1Name=="Oak" and output.CraftedFinish.Wood2Name=="Oak")
    end)
    check("Shared serializer preserves furniture function state",function()
        assert(schema.Serialize(houseData()).Placements[1].FunctionState.EditableSign.Text=="A safe example")
    end)
    check("Malformed CFrame placement is not loaded",function()
        local data=houseData();data.Placements[1].LocalCFrame={0/0};assert(#schema.Sanitize(data).Placements==0)
    end)
    check("Legacy Friends access migrates to Private",function() assert(schema.Sanitize({HouseAccess="Friends"}).HouseAccess=="Private") end)
    check("One server acquires a player write lease",function()
        local a,b=fixture();assert(a:Acquire(10));local second,reason=b:Acquire(10);assert(second==nil and reason)
    end)
    check("Independent players can load concurrently",function() local a,b=fixture();assert(a:Acquire(10));assert(b:Acquire(11)) end)
    check("Visitors read an active owner's snapshot",function()
        local a,b=fixture();assert(a:Acquire(10));local data,reason,active=b:Read(10);assert(data and not reason and active)
    end)
    check("Offline visitor cannot overwrite active writer",function()
        local a,b=fixture();assert(a:Acquire(10));local data=b:Read(10);data.TaxReserve=999
        local ok,reason=b:Write(10,data);assert(not ok and reason=="WriterActive")
    end)
    check("Owner write preserves crafted furniture",function()
        local a,_,store=fixture();local _,handle=a:Acquire(10);local data=houseData()
        assert(a:Write(10,data,handle));assert(store.Records.Player_10.Placements[1].CraftedRecordId=="record-oak")
    end)
    check("Offline compare-and-swap rejects stale revision",function()
        local a,b,store=fixture();store.Records.Player_10=houseData()
        local first=a:Read(10);local stale=b:Read(10);assert(a:Write(10,first))
        local ok,reason=b:Write(10,stale);assert(not ok and reason=="RevisionConflict")
    end)
    check("Offline write preserves crafted furniture",function()
        local a,_,store=fixture();store.Records.Player_10=houseData();local data=a:Read(10)
        data.TaxDueAmount=100;assert(a:Write(10,data));assert(store.Records.Player_10.Placements[1].CraftedFinish.Wood1Name=="Oak")
    end)
    check("Expired original writer cannot overwrite takeover",function()
        local a,b,_,clock=fixture();local data,old=a:Acquire(10);clock(1201);assert(b:Acquire(10))
        local ok,reason=a:Write(10,data,old);assert(not ok and reason=="LeaseLost" and old.Lost)
    end)
    check("Lease renew keeps writer ownership",function()
        local a,b,_,clock=fixture();local _,handle=a:Acquire(10);clock(1100);assert(a:Renew(handle));clock(1150);assert(b:Acquire(10)==nil)
    end)
    check("Release permits the next server to acquire",function()
        local a,b=fixture();local data,handle=a:Acquire(10);assert(a:Write(10,data,handle,true));assert(b:Acquire(10))
    end)
    check("Transient save failure retries without losing data",function()
        local a,_,store=fixture();local data,handle=a:Acquire(10);data.TaxReserve=725;store.FailBefore=2
        assert(a:Write(10,data,handle));assert(store.Records.Player_10.TaxReserve==725)
    end)
    check("Lost save acknowledgement is idempotent",function()
        local a,_,store=fixture();local data,handle=a:Acquire(10);data.TaxReserve=725;store.FailAfter=1
        local ok,revision=a:Write(10,data,handle);assert(ok and revision==1 and store.Records.Player_10.Revision==1)
    end)
    check("Failed save does not advance acknowledged revision",function()
        local a,_,store=fixture();local data,handle=a:Acquire(10);store.FailBefore=8
        assert(not a:Write(10,data,handle));assert(handle.Revision==0)
    end)
    check("Overlapping write is rejected while handle is busy",function()
        local a=fixture();local data,handle=a:Acquire(10);handle.Busy=true;assert(not a:Write(10,data,handle))
    end)
    local function volumes(specs)
        local result={}
        for _,spec in ipairs(specs) do table.insert(result,{CFrame=spec[1],Half=spec[2]*0.5+Vector3.one*0.03}) end
        return result
    end
    check("Interior furniture is accepted",function() assert(Geometry.ContainsBox(CFrame.new(),Vector3.new(2,2,2),volumes({{CFrame.new(),Vector3.new(10,10,10)}}))) end)
    check("Cursor inside but furniture outside is rejected",function() assert(not Geometry.ContainsBox(CFrame.new(4.5,0,0),Vector3.new(3,2,2),volumes({{CFrame.new(),Vector3.new(10,10,10)}}))) end)
    check("Furniture spanning adjoining room volumes is accepted",function() assert(Geometry.ContainsBox(CFrame.new(),Vector3.new(6,2,2),volumes({{CFrame.new(-2,0,0),Vector3.new(4,6,6)},{CFrame.new(2,0,0),Vector3.new(4,6,6)}}))) end)
    check("A gap between rooms cannot be bridged",function() assert(not Geometry.ContainsBox(CFrame.new(),Vector3.new(6,2,2),volumes({{CFrame.new(-2,0,0),Vector3.new(3,6,6)},{CFrame.new(2,0,0),Vector3.new(3,6,6)}}))) end)
    check("Offset gap missed by outer corners is still rejected",function() assert(not Geometry.ContainsBox(CFrame.new(),Vector3.new(6,2,2),volumes({{CFrame.new(-1.1,0,0),Vector3.new(4.2,6,6)},{CFrame.new(2.2,0,0),Vector3.new(1.6,6,6)}}))) end)
    check("Rotated house coordinates are supported",function()
        local cf=CFrame.new(20,5,10)*CFrame.Angles(0,math.rad(37),0)
        assert(Geometry.ContainsBox(cf,Vector3.new(4,2,4),volumes({{cf,Vector3.new(8,8,8)}})))
    end)
    check("Locked expansion bounds are excluded",function()
        local folder=object("Folder");local bound=object("Part","Room",folder);bound.Size=Vector3.new(10,10,10);bound:SetAttribute("RequiredUpgradeStage",2)
        assert(#Geometry.GetVolumes(folder,1)==0 and #Geometry.GetVolumes(folder,2)==1)
    end)
    check("Invisible helper geometry does not enlarge furniture",function()
        local folder=object("Folder");local bound=object("Part","Room",folder);bound.Size=Vector3.new(10,10,10)
        local model=object("Model");local part=object("Part","Cushion",model);part.Size=Vector3.new(2,2,2)
        local helper=object("Part","Helper",model);helper.Position=Vector3.new(500,0,0);helper.Transparency=1
        assert(Geometry.ValidateModel(model,folder,0))
    end)
    check("Duplicate furniture station marker survives sanitizing clone",function()
        local placement=module("HousePlacementService").new({Config=config,FurnitureFolder=object("Folder"),Registry=registry,IsFiniteNumber=function()return true end,Geometry=Geometry})
        local station=object("Model");station:SetAttribute("FurnitureCraftingStation",true);object("Part","Base",station)
        local a,b=placement.sanitizeFurnitureClone(station),placement.sanitizeFurnitureClone(station)
        table.insert(trash,a);table.insert(trash,b)
        assert(a~=b and a:GetAttribute("FurnitureCraftingStation")==true and b:GetAttribute("FurnitureCraftingStation")==true)
    end)
    check("Virtual session creation preserves nested spawn and separate cells",function()
        local template=object("Model","TestHouse");local door=object("Model","Door",template)
        local nested=object("Folder","Entry",door);object("Part","HouseSpawn",nested)
        object("Folder","PlacementBounds",template)
        local a,b={UserId=1,Name="OwnerA"},{UserId=2,Name="OwnerB"}
        local caches={[a]={Data={SelectedHouse="TestHouse",UpgradeStage=0}},[b]={Data={SelectedHouse="TestHouse",UpgradeStage=0}}}
        local restores,exits=0,0
        local service=module("HouseSessionService").new({Config=config,Caches=caches,Sessions={},RuntimeSessions={},
            ActiveHouses=object("Folder"),GetHouseTemplate=function()return template end,ApplyUpgradeStage=function()end,
            Restore=function()restores+=1 end,AttachExit=function()exits+=1 end})
        local first,second=service.createRuntimeSession(a),service.createRuntimeSession(b)
        assert(first.House~=second.House and first.CellIndex~=second.CellIndex)
        assert(service.getSessionSpawn(first) and restores==2 and exits==2)
        service.releaseCell(first.CellIndex);assert(service.allocateCell()==first.CellIndex)
    end)
    check("Shared session joins owner and visitor independently",function()
        local house=object("Model");local door=object("Model","Door",house);object("Part","HouseSpawn",door)
        local session={Id="Shared",House=house,HouseKind="Virtual",Participants={},DeathConnections={}}
        local players,sessions={},{}
        for i=1,2 do players[i]={SetAttribute=function()end} end
        local teleports,snapshots=0,0
        local service=module("HouseSessionService").new({Config=config,Sessions=sessions,AttachExit=function()end,
            Teleport=function()teleports+=1;return true end,BuildSnapshot=function()return {}end,
            SendState=function()snapshots+=1 end,EndSession=function()error("Unexpected failed join")end})
        assert(service.joinRuntimeSession(players[1],session));assert(service.joinRuntimeSession(players[2],session))
        assert(sessions[players[1]]==sessions[players[2]] and session.Participants[players[1]] and session.Participants[players[2]])
        assert(teleports==2 and snapshots==2)
    end)
    check("Snapshot sends only the changed furniture",function()
        local before={SessionId="A",StreamSequence=1,Placements={{PlacementId="a",CFrame=CFrame.new()},{PlacementId="b",CFrame=CFrame.new(5,0,0)}}}
        local after=copy(before);after.StreamSequence=2;after.Placements[1].CFrame=CFrame.new(1,0,0)
        local delta=Snapshot.Diff(before,after);assert(#delta.Placements==1 and delta.Placements[1].PlacementId=="a")
        assert(Snapshot.Equal(after,Snapshot.Apply(before,delta)))
    end)
    check("Snapshot removes stored furniture",function()
        local before={SessionId="A",StreamSequence=1,Placements={{PlacementId="a"}}}
        local after={SessionId="A",StreamSequence=2,Placements={}}
        assert(#Snapshot.Apply(before,Snapshot.Diff(before,after)).Placements==0)
    end)
    check("Missing snapshot sequence requests recovery",function()
        local state={SessionId="A",StreamSequence=1};assert(Snapshot.Apply(state,{SessionId="A",BaseSequence=3})==nil)
    end)
    check("Delta from another session is rejected",function() assert(Snapshot.Apply({SessionId="A",StreamSequence=1},{SessionId="B",BaseSequence=1})==nil) end)
    check("Move history retains trusted before and after transforms",function()
        local session={};History.Record(session,"a",CFrame.new(),CFrame.new(1,0,0),40)
        assert(History.Peek(session,"Undo").Before==CFrame.new());History.Commit(session,"Undo");assert(History.Peek(session,"Redo").After==CFrame.new(1,0,0))
    end)
    check("New move clears redo history",function()
        local session={};History.Record(session,"a",CFrame.new(),CFrame.new(1,0,0));History.Commit(session,"Undo")
        History.Record(session,"a",CFrame.new(),CFrame.new(2,0,0));assert(History.Peek(session,"Redo")==nil)
    end)
    check("Storing furniture clears only its history",function()
        local session={};History.Record(session,"a",CFrame.new(),CFrame.new(1,0,0));History.Record(session,"b",CFrame.new(),CFrame.new(2,0,0))
        History.Remove(session,"b");assert(History.Peek(session,"Undo").PlacementId=="a")
    end)
    check("History size is bounded",function()
        local session={};for i=1,100 do History.Record(session,"a",CFrame.new(i,0,0),CFrame.new(i+1,0,0),40) end;assert(#session.MoveHistory.Undo==40)
    end)
    check("Setup report identifies missing Door and bounds",function()
        local houses=object("Folder");local model=object("Model","BadHouse",houses);model:SetAttribute("House",true)
        local report=Validator.Report(houses,object("Folder"),object("Folder"),nil,registry,true)
        local codes={};for _,entry in ipairs(report.Errors) do codes[entry.Code]=true end
        assert(codes.DOOR_MISSING and codes.BOUNDS_MISSING)
    end)
    check("Setup report rejects unknown furniture function",function()
        local furniture=object("Folder");local item=object("Model","BadFurniture",furniture);item:SetAttribute("HouseFunction","Unknown")
        local report=Validator.Report(object("Folder"),object("Folder"),furniture,nil,registry,true)
        assert(report.Errors[1].Code=="UNKNOWN_FUNCTION")
    end)
    check("Build controls create search, precision and undo without strokes",function()
        local panel=game.StarterGui.HouseGui.BuildPanel:Clone();table.insert(trash,panel)
        local ui=module("HouseBuildTools").new(panel)
        assert(ui.SearchBox:IsA("TextBox") and ui.UndoButton and ui.RedoButton)
        assert(not ui.GridButton:FindFirstChildWhichIsA("UIStroke",true))
        ui.Reset();assert(ui.Offset==Vector3.zero and not ui.Frozen)
    end)
    check("HouseController cold start with no active house",function()
        local gui=game.StarterGui.HouseGui:Clone();table.insert(trash,gui)
        local toolbar=game.StarterGui.mainToolbar:Clone();table.insert(trash,toolbar)
        local buildModule=root.HouseBuildTools:Clone();buildModule.Parent=gui
        local function signal() return {Connect=function() return {Disconnect=function()end} end} end
        local remotes=setmetatable({}, {__index=function(t,name)
            local remote={OnClientEvent=signal(),FireServer=function()end,InvokeServer=function()return {Active=false}end}
            rawset(t,name,remote);return remote
        end})
        function remotes:WaitForChild(name) return self[name] end
        local shared={HousePlacementGeometry=root.HousePlacementGeometry,HouseSnapshot=root.HouseSnapshot}
        function shared:WaitForChild(name) return self[name] end
        local replicated={HouseShared=shared,HouseRemotes=remotes,Items=game.ReplicatedStorage.Items,ItemRegistry="MockItemRegistry"}
        function replicated:WaitForChild(name) return self[name] end
        local playerGui={HouseGui=gui,mainToolbar=toolbar}
        function playerGui:WaitForChild(name) return self[name] end
        function playerGui:FindFirstChild(name) return self[name] end
        local attributes={}
        local player={Name="EditModeTest",UserId=1,ChildAdded=signal(),CharacterAdded=signal()}
        function player:WaitForChild(name) if name=="PlayerGui" then return playerGui end;error("Unexpected player child "..name) end
        function player:FindFirstChild() return nil end
        function player:GetMouse() return {} end
        function player:GetAttribute(name) return attributes[name] end
        function player:SetAttribute(name,value) attributes[name]=value end
        function player:GetAttributeChangedSignal() return signal() end
        local fakeWorkspace={CurrentCamera={ViewportSize=Vector2.new(1920,1080)},PhysicalHouses=game.Workspace.PhysicalHouses}
        function fakeWorkspace:GetPropertyChangedSignal() return signal() end
        function fakeWorkspace:FindFirstChild(name) return self[name] end
        local services={Players={LocalPlayer=player,GetPlayers=function()return {}end},ReplicatedStorage=replicated,
            RunService={RenderStepped=signal(),Heartbeat=signal()},
            UserInputService={InputBegan=signal(),InputChanged=signal()},
            ContextActionService={BindActionAtPriority=function()end}}
        local env=setmetatable({script={Parent=gui},workspace=fakeWorkspace,
            game={GetService=function(_,name) assert(services[name],name);return services[name] end},
            task={spawn=function()end,delay=function()end,wait=function()end},
            require=function(item) if item=="MockItemRegistry" then return {NormalizeIconId=function()return ""end} end;return module(item.Name) end,
        },{__index=getfenv()})
        local startup=assert(loadstring(root.HouseController.Source,"=HouseControllerSmoke"))
        setfenv(startup,env)
        startup()
        assert(gui.BuildPanel.Visible==false and gui.BuildPanel.BuildTools.UndoButton.Active==false)
    end)
    check("All staged sources compile",function()
        for _,item in ipairs(root:GetChildren()) do if item:IsA("ModuleScript") then assert(loadstring(item.Source,"="..item.Name)) end end
    end)
    for _,item in ipairs(trash) do item:Destroy() end
    local passed=0;for _,result in ipairs(checks) do if result.Passed then passed+=1 end end
    return {Passed=passed,Total=#checks,Checks=checks}
end
