local ESX=exports.es_extended:getSharedObject()
local busy,lastSpin,lastDataRequest={},{},{}
math.randomseed(os.time())

local function notify(src,msg,kind) TriggerClientEvent(Config.NotifyEvent,src,{title='GACHA',message=msg,type=kind or 'inform'}) end
local function spinFailed(src) TriggerClientEvent('lv_gacha:client:spinFailed',src) end
local function rank(r) return (Config.Rarities[r] and Config.Rarities[r].rank) or 0 end
local function playerFields(src,xPlayer)
 local ids={}
 local identifiers = src > 0 and GetPlayerIdentifiers(src) or {}
 for _,v in ipairs(identifiers) do ids[#ids+1]=v end
 local icName='Unknown'
 if xPlayer then
  if type(xPlayer.getName)=='function' then local ok,name=pcall(xPlayer.getName,xPlayer); if ok and name and name~='' then icName=name end
  elseif xPlayer.name and xPlayer.name~='' then icName=xPlayer.name end
 end
 return {
  {name='Tên IC',value=icName,inline=true},
  {name='Tên FiveM',value=('%s (ID %s)'):format(GetPlayerName(src) or 'Unknown',src),inline=true},
  {name='Identifier ESX',value=xPlayer and xPlayer.identifier or 'Unknown',inline=true},
  {name='Identifiers',value=table.concat(ids,'\n'):sub(1,1000),inline=false}
 }
end
local function log(src,xPlayer,title,message,color,fields)
 local webhook=GetConvar('lvGachaWebhook',Config.Log.Webhook or '')
 if not Config.Log.Enabled or webhook=='' or GetResourceState('legacyWebhook')~='started' then return end
 local all=playerFields(src,xPlayer); for _,f in ipairs(fields or {}) do all[#all+1]=f end
 local ok,err=pcall(function() exports.legacyWebhook:SendDiscordLog({webhook=webhook,title=title or Config.Log.Title,message=message,color=color or Config.Log.ColorSuccess,username=Config.Log.Username,fields=all}) end)
 if not ok then print(('[lv_gacha] LegacyWebhook error: %s'):format(tostring(err))) end
end
local function publicReward(r)
 local targetCase=r.type=='crate' and Config.Cases[r.caseId] or nil
 return {id=r.id,name=r.name,type=r.type,rarity=r.rarity,amount=r.amount or r.days or 1,image=r.image or (targetCase and (targetCase.image or targetCase.inventoryIcon)),item=r.item,model=r.model,chance=r.chance}
end
local function publicCases()
 local out={}; for id,c in pairs(Config.Cases) do local rewards={}; for i,r in ipairs(c.rewards) do rewards[i]=publicReward(r) end
  out[id]={label=c.label,description=c.description,boxItem=c.boxItem,keyItem=c.keyItem,keyAmount=c.keyAmount or 1,image=c.image,inventoryIcon=c.inventoryIcon,keyInventoryIcon=c.keyInventoryIcon,pity=c.pity,rewards=rewards}
 end return out
end
local function pick(c,guaranteed)
 local pool,total={},0; local min=rank(c.pity.minimumRarity)
 for _,r in ipairs(c.rewards) do if not guaranteed or rank(r.rarity)>=min then total=total+r.chance; pool[#pool+1]=r end end
 if total<=0 then return nil end
 local roll=math.random()*total; for _,r in ipairs(pool) do roll=roll-r.chance; if roll<=0 then return r end end return pool[#pool]
end
local chars='ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
local function newPlate()
 for _=1,20 do local p='GC'; for _=1,6 do local i=math.random(1,#chars); p=p..chars:sub(i,i) end
  if not MySQL.scalar.await('SELECT 1 FROM owned_vehicles WHERE plate=? LIMIT 1',{p}) then return p end
 end
end
local caseMetadata
local function grant(src,xPlayer,r)
 if r.type=='item' then
  if not exports.ox_inventory:CanCarryItem(src,r.item,r.amount or 1,r.metadata) then return false,'Túi đồ không đủ chỗ' end
  local ok,err=exports.ox_inventory:AddItem(src,r.item,r.amount or 1,r.metadata); return ok==true,err
 elseif r.type=='magazine' then
  if GetResourceState('lv_Magazine')~='started' then return false,'lv_Magazine chưa hoạt động' end
  local ok,added=exports.lv_Magazine:GiveMagazine(src,r.magType,r.amount or 1,r.metadata)
  return ok==true,ok and nil or ('Chỉ cấp được %d băng đạn'):format(tonumber(added) or 0)
 elseif r.type=='crate' then
  local targetCase=Config.Cases[r.caseId]
  if not targetCase or GachaValidCases[r.caseId]~=true then return false,'Hòm thưởng không hợp lệ' end
  local metadata=caseMetadata(r.caseId,targetCase,'crate')
  local amount=r.amount or 1
  if not exports.ox_inventory:CanCarryItem(src,targetCase.boxItem,amount,metadata) then return false,'Túi đồ không đủ chỗ' end
  local ok,err=exports.ox_inventory:AddItem(src,targetCase.boxItem,amount,metadata)
  return ok==true,err
 elseif r.type=='prime' then
  if GetResourceState('prime_status')~='started' then return false,'prime_status chưa hoạt động' end
  local ok,err=exports.prime_status:SetPrime(src,r.days); return ok==true,err
 elseif r.type=='vehicle' then
  local p=newPlate(); if not p then return false,'Không tạo được biển số' end
  local id=MySQL.insert.await('INSERT INTO owned_vehicles (vehicle,owner,plate,vehicleGarage,stored) VALUES (?,?,?,?,?)',{json.encode({model=joaat(r.model),plate=p}),xPlayer.identifier,p,Config.DefaultGarage,1})
  return id~=nil,id and nil or 'Không lưu được xe',id and {plate=p} or nil
 end
 return false,'Loại phần thưởng không hợp lệ'
end
local function state(identifier,id)
 local ok,row=pcall(MySQL.single.await,'SELECT pity,total_spins FROM lv_gacha_state WHERE identifier=? AND banner=?',{identifier,id})
 if not ok then print(('[lv_gacha] Database state error: %s'):format(tostring(row))); return 0,0,false end
 return row and row.pity or 0,row and row.total_spins or 0,true
end
caseMetadata=function(caseId, caseData, kind)
 local isCrate = kind == 'crate'
 local metadata = {
  caseId = caseId,
  label = isCrate and caseData.label or (caseData.label .. ' Key'),
  description = isCrate and ('Hòm '..caseData.label) or ('Chìa khóa dùng cho '..caseData.label)
 }
 local inventoryIcon = isCrate and caseData.inventoryIcon or caseData.keyInventoryIcon
 if type(inventoryIcon) == 'string' and inventoryIcon ~= '' then
  if inventoryIcon:match('^https://') then
   metadata.imageurl = inventoryIcon
  else
   metadata.image = inventoryIcon
  end
 end
 return metadata
end
local function getCaseInfo(caseId)
 local caseData=Config.Cases[caseId]
 if not caseData or GachaValidCases[caseId]~=true then return nil end
 return {caseId=caseId,label=caseData.label,image=caseData.image or caseData.inventoryIcon,boxItem=caseData.boxItem,keyItem=caseData.keyItem,metadata=caseMetadata(caseId,caseData,'crate')}
end
exports('GetCaseInfo',getCaseInfo)
exports('GiveCrate',function(playerId,caseId,amount)
 local info=getCaseInfo(caseId)
 amount=math.floor(tonumber(amount) or 0)
 if not info or amount<1 then return false,'Hòm không hợp lệ' end
 if not exports.ox_inventory:CanCarryItem(playerId,info.boxItem,amount,info.metadata) then return false,'Túi đồ không đủ chỗ' end
 local success,response=exports.ox_inventory:AddItem(playerId,info.boxItem,amount,info.metadata)
 return success==true,response
end)
local function syncCaseItemMetadata(src, itemName, caseId, caseData, kind)
 local slots=exports.ox_inventory:Search(src,'slots',itemName) or {}
 local expected=caseMetadata(caseId,caseData,kind)
 for _,slotData in pairs(slots) do
  local metadata=slotData.metadata
  if type(metadata)=='table' and metadata.caseId==caseId then
   local changed=false
   for key,value in pairs(expected) do
    if metadata[key]~=value then metadata[key]=value; changed=true end
   end
   if expected.imageurl and metadata.image then metadata.image=nil; changed=true end
   if expected.image and metadata.imageurl then metadata.imageurl=nil; changed=true end
   if changed then exports.ox_inventory:SetMetadata(src,slotData.slot,metadata) end
  end
 end
end
local function sendData(src)
 local x=ESX.GetPlayerFromId(src); if not x then return end local states, counts = {}, {}
 for id,c in pairs(Config.Cases) do syncCaseItemMetadata(src,c.boxItem,id,c,'crate'); syncCaseItemMetadata(src,c.keyItem,id,c,'key'); local pity,total=state(x.identifier,id); states[id]={pity=pity,totalSpins=total}; counts[id]={boxes=exports.ox_inventory:GetItemCount(src,c.boxItem,{caseId=id},false),keys=exports.ox_inventory:GetItemCount(src,c.keyItem,{caseId=id},false)} end
 TriggerClientEvent('lv_gacha:client:data',src,{logo=Config.Logo,cases=publicCases(),rarities=Config.Rarities,states=states,counts=counts})
end
RegisterNetEvent('lv_gacha:server:requestData',function()
 local src=source; local now=GetGameTimer()
 if lastDataRequest[src] and now-lastDataRequest[src] < 750 then return end
 lastDataRequest[src]=now; sendData(src)
end)
RegisterNetEvent('lv_gacha:server:spin',function(caseId)
 local src=source
 if type(caseId) ~= 'string' or #caseId > 50 or not caseId:match('^[a-z0-9_-]+$') then spinFailed(src); return end
 local c=Config.Cases[caseId]; if not c or GachaValidCases[caseId] ~= true or busy[src] then spinFailed(src); return end
 local now=GetGameTimer(); if lastSpin[src] and now-lastSpin[src]<Config.SpinCooldownMs then spinFailed(src); return end
 busy[src],lastSpin[src]=true,now; local x=ESX.GetPlayerFromId(src); if not x then busy[src]=nil; spinFailed(src); return end
 local crateMeta=caseMetadata(caseId,c,'crate')
 local keyMeta=caseMetadata(caseId,c,'key')
 local pity,total,stateOk=state(x.identifier,caseId)
 if not stateOk then notify(src,'Hệ thống dữ liệu đang lỗi, vui lòng thử lại sau.','error'); busy[src]=nil; spinFailed(src); return end
 if exports.ox_inventory:GetItemCount(src,c.boxItem,{caseId=caseId},false)<1 or exports.ox_inventory:GetItemCount(src,c.keyItem,{caseId=caseId},false)<(c.keyAmount or 1) then notify(src,'Bạn cần đủ hòm và chìa khóa.','error'); log(src,x,'Mở hòm thất bại','Thiếu hòm hoặc chìa (cần '..(c.keyAmount or 1)..')',Config.Log.ColorError,{{name='Hòm',value=caseId,inline=true},{name='Số chìa cần',value=tostring(c.keyAmount or 1),inline=true}}); busy[src]=nil; spinFailed(src); return end
 if not exports.ox_inventory:RemoveItem(src,c.boxItem,1,{caseId=caseId},nil,false,false) then busy[src]=nil; spinFailed(src); return end
 if not exports.ox_inventory:RemoveItem(src,c.keyItem,c.keyAmount or 1,{caseId=caseId},nil,false,false) then exports.ox_inventory:AddItem(src,c.boxItem,1,crateMeta); busy[src]=nil; spinFailed(src); return end
 local guaranteed=c.pity.enabled and pity+1>=c.pity.at; local reward=pick(c,guaranteed)
 local called,ok,err,extra=pcall(grant,src,x,reward)
 if not called then err=ok; ok=false end
 if not ok then exports.ox_inventory:AddItem(src,c.boxItem,1,crateMeta); exports.ox_inventory:AddItem(src,c.keyItem,c.keyAmount or 1,keyMeta); notify(src,(err or 'Cấp thưởng lỗi')..' - đã hoàn hòm và chìa.','error'); log(src,x,'Hoàn hòm và chìa',err,Config.Log.ColorError,{{name='Hòm',value=caseId,inline=true},{name='Số chìa cần',value=tostring(c.keyAmount or 1),inline=true}}); busy[src]=nil; spinFailed(src); sendData(src); return end
 total=total+1; if rank(reward.rarity)>=rank(c.pity.minimumRarity) then pity=0 else pity=pity+1 end
 local saved,saveErr=pcall(function()
  MySQL.query.await('INSERT INTO lv_gacha_state (identifier,banner,pity,total_spins) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE pity=VALUES(pity),total_spins=VALUES(total_spins)',{x.identifier,caseId,pity,total})
  MySQL.insert.await('INSERT INTO lv_gacha_history (identifier,banner,reward_id,reward_name,reward_type,rarity) VALUES (?,?,?,?,?,?)',{x.identifier,caseId,reward.id,reward.name,reward.type,reward.rarity})
 end)
 if not saved then print(('[lv_gacha] Database save error: %s'):format(tostring(saveErr))); log(src,x,'LỖI LƯU GACHA',tostring(saveErr),Config.Log.ColorError,{{name='Case ID',value=caseId,inline=true},{name='Reward',value=reward.id,inline=true}}) end
 local item=publicReward(reward); item.extra=extra
 log(src,x,rank(reward.rarity)>=4 and 'PHẦN THƯỞNG HIẾM' or 'Mở hòm thành công',('Nhận **%s** từ **%s**'):format(reward.name,c.label),rank(reward.rarity)>=4 and Config.Log.ColorRare or Config.Log.ColorSuccess,{{name='Reward ID',value=reward.id,inline=true},{name='Loại / Rarity',value=reward.type..' / '..reward.rarity,inline=true},{name='Chance',value=reward.chance..'%',inline=true},{name='Pity',value=pity..' / '..c.pity.at,inline=true},{name='Biển số',value=extra and extra.plate or '-',inline=true}})
 TriggerClientEvent('lv_gacha:client:result',src,{reward=item,pity=pity,case=caseId}); sendData(src); busy[src]=nil
end)
AddEventHandler('playerDropped',function() busy[source],lastSpin[source],lastDataRequest[source]=nil,nil,nil end)

local function adminNotify(src, message, kind)
    if src == 0 then
        print(('[lv_gacha] %s'):format(message))
        return
    end
    notify(src, message, kind)
end

local function hasAdminGivePermission(src)
    if src == 0 then return true end
    if GetResourceState('aCore') ~= 'started' then return false end
    local called, level, allowed = pcall(function()
        return exports.aCore:GetAdminLevel(src), exports.aCore:HasPermission(src, 'giveitem')
    end)
    return called and type(level) == 'number' and level >= Config.AdminGiveMinLevel and allowed == true
end

local function parseAdminAmount(raw)
    if raw == nil then return 1 end
    local amount = tonumber(raw)
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > Config.AdminMaxGive then
        return nil
    end
    return amount
end

local function targetIcName(xTarget)
    if not xTarget then return 'Unknown' end
    if type(xTarget.getName) == 'function' then
        local ok, name = pcall(xTarget.getName, xTarget)
        if ok and type(name) == 'string' and name ~= '' then return name end
    end
    return xTarget.name or 'Unknown'
end

local function giveGachaAdminItem(src, args, itemName, kind, commandName)
    if not hasAdminGivePermission(src) then
        adminNotify(src, 'Bạn không có quyền sử dụng lệnh này.', 'error')
        return
    end

    local targetId = tonumber(args[1])
    local caseId = tostring(args[2] or ''):lower()
    local amount = parseAdminAmount(args[3])
    if not targetId or targetId ~= math.floor(targetId) or targetId < 1 or caseId == '' or not amount then
        adminNotify(src, ('Cú pháp: /%s [id] [case_id] [số lượng 1-%d]'):format(commandName, Config.AdminMaxGive), 'error')
        return
    end

    local caseData = Config.Cases[caseId]
    if not caseData then
        local available = {}
        for availableId in pairs(Config.Cases) do available[#available + 1] = availableId end
        table.sort(available)
        adminNotify(src, ('Case ID không tồn tại: %s. ID hiện có: %s'):format(caseId, table.concat(available, ', ')), 'error')
        return
    end

    if GachaValidCases[caseId] ~= true then
        local reasons = GachaCaseValidationErrors[caseId] or {'không rõ lỗi'}
        adminNotify(src, ('Case %s đang bị vô hiệu: %s'):format(caseId, table.concat(reasons, '; ')), 'error')
        return
    end

    local metadata = caseMetadata(caseId, caseData, kind)
    local displayName = kind == 'crate' and caseData.label or (caseData.label .. ' Key')
    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then
        adminNotify(src, 'Người chơi không tồn tại hoặc đã offline.', 'error')
        return
    end

    if not exports.ox_inventory:Items(itemName) then
        adminNotify(src, ('Item %s chưa được khai báo trong ox_inventory.'):format(itemName), 'error')
        return
    end

    if not exports.ox_inventory:CanCarryItem(targetId, itemName, amount, metadata) then
        adminNotify(src, 'Túi đồ người chơi không đủ chỗ.', 'error')
        return
    end

    local success, response = exports.ox_inventory:AddItem(targetId, itemName, amount, metadata)
    if success ~= true then
        adminNotify(src, ('Cấp item thất bại: %s'):format(tostring(response or 'unknown')), 'error')
        return
    end

    local xAdmin = src == 0 and nil or ESX.GetPlayerFromId(src)
    local adminName = src == 0 and 'Console' or (GetPlayerName(src) or 'Unknown')
    adminNotify(src, ('Đã cấp x%d %s cho %s (ID %d).'):format(amount, displayName, targetIcName(xTarget), targetId), 'success')
    notify(targetId, ('Bạn đã nhận x%d %s từ Admin'):format(amount, displayName), 'success')
    log(src, xAdmin, 'ADMIN CẤP VẬT PHẨM GACHA',
        ('**%s** đã cấp **x%d %s** cho **%s** (ID %d).'):format(adminName, amount, displayName, targetIcName(xTarget), targetId),
        Config.Log.ColorRare,
        {
            { name = 'Target identifier', value = xTarget.identifier or 'Unknown', inline = false },
            { name = 'Item', value = itemName, inline = true },
            { name = 'Case ID', value = caseId, inline = true },
            { name = 'Số lượng', value = tostring(amount), inline = true }
        })
end

RegisterCommand('givegachacrate', function(src, args)
    giveGachaAdminItem(src, args, Config.CrateItem, 'crate', 'givegachacrate')
end, false)

RegisterCommand('givegachakey', function(src, args)
    giveGachaAdminItem(src, args, Config.KeyItem, 'key', 'givegachakey')
end, false)

GachaValidCases = {}
GachaCaseValidationErrors = {}
do
    for caseId, caseData in pairs(Config.Cases) do
        local valid, sum, seen = true, 0, {}
        local function invalidate(reason)
            valid = false
            GachaCaseValidationErrors[caseId] = GachaCaseValidationErrors[caseId] or {}
            GachaCaseValidationErrors[caseId][#GachaCaseValidationErrors[caseId] + 1] = reason
            print(('[lv_gacha] ^1CASE %s không hợp lệ: %s^0'):format(tostring(caseId), reason))
        end

        if type(caseId) ~= 'string' or caseId == '' then invalidate('case ID rỗng') end
        if caseData.boxItem ~= Config.CrateItem or caseData.keyItem ~= Config.KeyItem then invalidate('phải dùng crate/key chung') end
        if caseData.inventoryIcon ~= nil and (type(caseData.inventoryIcon) ~= 'string' or (caseData.inventoryIcon ~= '' and caseData.inventoryIcon:find('://', 1, true) and not caseData.inventoryIcon:match('^https://'))) then invalidate('inventoryIcon phải là URL https://, tên file local hoặc chuỗi rỗng') end
        if caseData.keyInventoryIcon ~= nil and (type(caseData.keyInventoryIcon) ~= 'string' or (caseData.keyInventoryIcon ~= '' and caseData.keyInventoryIcon:find('://', 1, true) and not caseData.keyInventoryIcon:match('^https://'))) then invalidate('keyInventoryIcon phải là URL https://, tên file local hoặc chuỗi rỗng') end
        if type(caseData.keyAmount) ~= 'number' or caseData.keyAmount < 1 or caseData.keyAmount ~= math.floor(caseData.keyAmount) then invalidate('keyAmount phải là số nguyên dương') end
        if type(caseData.pity) ~= 'table' or type(caseData.pity.at) ~= 'number' or caseData.pity.at < 1 or caseData.pity.at ~= math.floor(caseData.pity.at) or not Config.Rarities[caseData.pity.minimumRarity] then invalidate('cấu hình pity sai') end

        if type(caseData.rewards) ~= 'table' or #caseData.rewards == 0 then
            invalidate('không có reward')
        else
            for _, reward in ipairs(caseData.rewards) do
                local chance = tonumber(reward.chance)
                if type(reward.id) ~= 'string' or reward.id == '' or seen[reward.id] then invalidate('reward ID rỗng hoặc trùng') else seen[reward.id] = true end
                if not chance or chance < 0 then invalidate(('chance sai ở %s'):format(tostring(reward.id))) else sum = sum + chance end
                if not Config.Rarities[reward.rarity] then invalidate(('rarity sai ở %s'):format(tostring(reward.id))) end

                if reward.type == 'item' then
                    if not exports.ox_inventory:Items(reward.item) then invalidate(('item %s không tồn tại'):format(tostring(reward.item))) end
                    if type(reward.amount) ~= 'number' or reward.amount < 1 or reward.amount ~= math.floor(reward.amount) then invalidate(('amount sai ở %s'):format(tostring(reward.id))) end
                elseif reward.type == 'magazine' then
                    if type(reward.magType) ~= 'string' or not reward.magType:match('^magazine%-%w+$') then invalidate(('magType sai ở %s'):format(tostring(reward.id))) end
                    if type(reward.amount) ~= 'number' or reward.amount < 1 or reward.amount ~= math.floor(reward.amount) then invalidate(('amount sai ở %s'):format(tostring(reward.id))) end
                elseif reward.type == 'crate' then
                    if type(reward.caseId) ~= 'string' or not Config.Cases[reward.caseId] then invalidate(('caseId hòm thưởng sai ở %s'):format(tostring(reward.id))) end
                    if type(reward.amount) ~= 'number' or reward.amount < 1 or reward.amount ~= math.floor(reward.amount) then invalidate(('amount sai ở %s'):format(tostring(reward.id))) end
                elseif reward.type == 'vehicle' then
                    if type(reward.model) ~= 'string' or reward.model == '' then invalidate(('model xe sai ở %s'):format(tostring(reward.id))) end
                elseif reward.type == 'prime' then
                    if type(reward.days) ~= 'number' or reward.days < 1 or reward.days ~= math.floor(reward.days) then invalidate(('số ngày Prime sai ở %s'):format(tostring(reward.id))) end
                else
                    invalidate(('reward type sai ở %s'):format(tostring(reward.id)))
                end
            end
        end

        if math.abs(sum - 100.0) > 0.001 then invalidate(('tổng chance %.4f, bắt buộc = 100'):format(sum)) end
        GachaValidCases[caseId] = valid
        if valid then print(('[lv_gacha] ^2CASE %s validated (100%%)^0'):format(caseId)) end
    end
end
