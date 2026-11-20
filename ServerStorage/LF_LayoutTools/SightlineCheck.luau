-- Base-to-base sightline check for Live Fire. Origins: standable spots on the RED half (x >= xmin),
-- at ground eye height (5) and on top of whatever is there (+5). Targets: the point-mirror (blue) spots.
local S={}
function S.run(opts)
	opts=opts or {}
	local root=workspace.Map_LiveFire.Arena
	local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={root}
	local function stand(x,z)
		local h=workspace:Raycast(Vector3.new(x,300,z),Vector3.new(0,-400,0),rp)
		if not h or h.Position.Y<-1 then return nil end
		return Vector3.new(x,h.Position.Y+5,z)
	end
	local pts={}
	for x=opts.xmin or 300,opts.xmax or 470,opts.step or 14 do for z=-255,255,opts.step or 14 do local p=stand(x,z) if p then table.insert(pts,p)
		if p.Y>20 then table.insert(pts,Vector3.new(x,5,z)) end end end end
	local clear,total=0,0 local bands={} local samples={}
	for _,a in ipairs(pts) do
		for _,b0 in ipairs(pts) do
			local b=Vector3.new(-b0.X,b0.Y,-b0.Z)
			total+=1
			if not workspace:Raycast(a,b-a,rp) then clear+=1
				local key=string.format("z%d->%d y%d",math.floor(a.Z/40)*40,math.floor(b.Z/40)*40,math.floor(a.Y/20)*20)
				bands[key]=(bands[key] or 0)+1
				if #samples<(opts.samples or 0) then table.insert(samples,string.format("(%.0f,%.0f,%.0f)->(%.0f,%.0f,%.0f)",a.X,a.Y,a.Z,b.X,b.Y,b.Z)) end end
		end
	end
	local list={} for k,v in pairs(bands) do table.insert(list,{k,v}) end
	table.sort(list,function(p,q) return p[2]>q[2] end)
	local out={} for i=1,math.min(#list,opts.top or 18) do table.insert(out,list[i][1].." x"..list[i][2]) end
	return clear,total,table.concat(out,"\n").."\n"..table.concat(samples,"\n"),#pts
end
return S
