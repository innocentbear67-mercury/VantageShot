local M={}
local K
local JOINT=Color3.fromRGB(62,64,68)
M.vols={}
function M.init(k) K=k M.vols={} end
function M.vol(par,name,x1,z1,x2,z2,y0,y1,opt)
 local v={name=name,x1=x1,z1=z1,x2=x2,z2=z2,y0=y0,y1=y1,opt=opt or {},par=par}
 local p=Instance.new("Part") p.Name="Core" p.Anchored=true p.Material=Enum.Material.SmoothPlastic p.Color=JOINT
 p.Size=Vector3.new(x2-x1,y1-y0,z2-z1) p.CFrame=CFrame.new((x1+x2)/2,(y0+y1)/2,(z1+z2)/2)
 local m=Instance.new("Model") m.Name=name p.Parent=m m.Parent=par v.model=m
 table.insert(M.vols,v) return v end
local function inside(pt,skip)
 if M.bounds and (pt.X<M.bounds[1] or pt.X>M.bounds[2] or pt.Z<M.bounds[3] or pt.Z>M.bounds[4]) then return true end
 for _,v in ipairs(M.vols) do if v~=skip and pt.X>v.x1+0.05 and pt.X<v.x2-0.05 and pt.Z>v.z1+0.05 and pt.Z<v.z2-0.05 and pt.Y>v.y0 and pt.Y<v.y1 then return true end end
 return false end
M.inside=inside
local function faces(v)
 return {{a=Vector3.new(v.x1,0,v.z2),b=Vector3.new(v.x2,0,v.z2),n=Vector3.new(0,0,1)},{a=Vector3.new(v.x2,0,v.z1),b=Vector3.new(v.x1,0,v.z1),n=Vector3.new(0,0,-1)},
  {a=Vector3.new(v.x2,0,v.z2),b=Vector3.new(v.x2,0,v.z1),n=Vector3.new(1,0,0)},{a=Vector3.new(v.x1,0,v.z1),b=Vector3.new(v.x1,0,v.z2),n=Vector3.new(-1,0,0)}} end
local op
local function clear(cf,size)
 local parts=workspace:GetPartBoundsInBox(cf,size,op)
 for _,p in ipairs(parts) do if p.CanCollide then return false end end return true end
local function put(v,name,f,along,y,w,h,depth,off,check,tag)
 local dir=(f.b-f.a).Unit local yaw=math.atan2(-dir.Z,dir.X)
 local base=f.a+dir*along+f.n*(off+depth/2) base=Vector3.new(base.X,y,base.Z)
 if check and not clear(CFrame.new(base+Vector3.new(0,h/2,0))*CFrame.Angles(0,yaw,0),Vector3.new(math.max(w-0.6,0.2),math.max(h-0.6,0.2),depth+0.2)) then return end
 local m=K.put(name,v.model,CFrame.new(base)*CFrame.Angles(0,yaw,0),Vector3.new(w,h,depth))
 if m:GetPivot().LookVector:Dot(f.n)<0 then m:PivotTo(m:GetPivot()*CFrame.Angles(0,math.pi,0)) end
 m.Name=tag or name return m end
function M.dress(v,rng)
 op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Exclude op.FilterDescendantsInstances={v.par,workspace.Terrain}
 local H=v.y1-v.y0 local und=v.opt.under
 for _,f in ipairs(faces(v)) do
  local skipF=false if v.opt.skip then for _,u in ipairs(v.opt.skip) do if u:Dot(f.n)>0.9 then skipF=true end end end
  if skipF then continue end
  local L=(f.b-f.a).Magnitude local dir=(f.b-f.a).Unit
  local function exposed(t,y) return not inside(f.a+dir*t+f.n*1.5+Vector3.new(0,y,0),v) end
  local isUnder=false if und then if typeof(und)=="Vector3" then und={und} end for _,u in ipairs(und) do if u:Dot(f.n)>0.9 then isUnder=true end end end
  local pBot=v.y0 if v.y0<=2.5 then pBot=v.y0+6 end if isUnder then pBot=v.y0+4.2 end
  local pTop=v.y1 if v.y1<77 then pTop=v.y1-4.2 end
  -- panels
  local cols=math.max(1,math.floor(L/9+0.5)) local cw=L/cols
  local rows=math.max(1,math.floor((pTop-pBot)/13+0.5)) local rh=(pTop-pBot)/rows
  for c=0,cols-1 do for r=0,rows-1 do local t=cw*(c+0.5) local y=pBot+rh*r
   if exposed(t,y+rh/2) then local roll=rng:NextNumber()
    local nm=roll<0.7 and "Kit_PanelWall" or roll<0.9 and "Kit_PanelWorn" or "Kit_PanelVent"
    put(v,nm,f,t,y,cw,rh,0.5,0,false,"KPanel") end end end
  -- plinth
  if v.y0<=2.5 then local pc=math.max(1,math.floor(L/8+0.5)) local ps=L/pc
   for c=0,pc-1 do local t=ps*(c+0.5) if exposed(t,3) then put(v,"Kit_Plinth",f,t,v.y0,ps,6,1.6,0,true,"KPlinth") end end end
  -- crown: fascia + rail on lower volumes, cornice on tall
  local fc=math.max(1,math.floor(L/5.3+0.5)) local fs=L/fc
  if v.y1<77 then
   for c=0,fc-1 do local t=fs*(c+0.5) if exposed(t,H-2) then put(v,"Kit_FasciaX",f,t,v.y1-4.2,fs,4.2,1.5,0.5,true,"KFascia") end end
   local rc=math.max(1,math.floor(L/6.3+0.5)) local rs=L/rc
   for c=0,rc-1 do local t=rs*(c+0.5) if exposed(t,H-2) and not inside(f.a+dir*t-f.n*1+Vector3.new(0,v.y1+2,0),nil) then put(v,"Kit_Rail",f,t,v.y1,rs,3.6,0.4,0.6,false,"KRail") end end
  else
   local cc=math.max(1,math.floor(L/8+0.5)) local cs=L/cc
   for c=0,cc-1 do local t=cs*(c+0.5) if exposed(t,H-2) then put(v,"Kit_Cornice",f,t,v.y1-4.2,cs,4.2,3.2,0.2,true,"KCornice") end end
  end
  -- undercut front: fascia band at soffit + pillars
  if isUnder then
   for c=0,fc-1 do local t=fs*(c+0.5) put(v,"Kit_FasciaX",f,t,v.y0,fs,4.2,1.5,0.5,true,"KFascia") end
   local pc=math.max(2,math.floor(L/16)+1) for c=0,pc-1 do local t=4+(L-8)*c/(pc-1)
    local pos=f.a+dir*t-f.n*3
    if clear(CFrame.new(pos.X,(2+v.y0)/2,pos.Z),Vector3.new(3.4,v.y0-3,3.4)) then
     K.put("Kit_PillarShaft",v.model,CFrame.new(pos.X,2,pos.Z),Vector3.new(4.5,v.y0-2,4.5)).Name="KPillar"
     K.put("Kit_PillarFoot",v.model,CFrame.new(pos.X,1.8,pos.Z),Vector3.new(6,2.6,6)).Name="KPillar"
     K.put("Kit_PillarCap",v.model,CFrame.new(pos.X,v.y0-1.3,pos.Z),Vector3.new(5.6,1.3,5.6)).Name="KPillar" end end
  end
  -- gunmetal columns + windows on tall faces
  if pTop-pBot>=28 and L>=30 then local colsAt={}
   for t=15,L-10,34 do if exposed(t,(pBot+pTop)/2) then table.insert(colsAt,t)
    for y=pBot+2,pTop-14,12 do put(v,"Kit_GunmetalPanel",f,t,y,10,12,1.2,0.5,true,"KGun") end end end
   for j=1,#colsAt-1,2 do local mid=(colsAt[j]+colsAt[j+1])/2 local y=pBot+(pTop-pBot)*0.55
    if exposed(mid,y+4) then put(v,"Kit_WindowBand",f,mid-5.2,y,10.2,9,1.8,0.5,true,"KWindow") put(v,"Kit_WindowBand",f,mid+5.2,y,10.2,9,1.8,0.5,true,"KWindow") end end
  end
  -- lights
  if v.y0<=2.5 then for t=8,L-8,24 do if exposed(t,14) then local m=put(v,"Kit_WallLight",f,t,16,1.8,0.8,1.3,0.5,true,"KLight") end end end
 end
 -- corner trims
 for _,c in ipairs({{v.x1,v.z1,-1,-1},{v.x2,v.z1,1,-1},{v.x1,v.z2,-1,1},{v.x2,v.z2,1,1}}) do
  local p=Vector3.new(c[1]+c[3]*1.5,(v.y0+v.y1)/2,c[2]+c[4]*1.5)
  if not inside(p,v) and not inside(p+Vector3.new(-c[3]*3,0,0),v) and not inside(p+Vector3.new(0,0,-c[4]*3),v) then
   K.put("Kit_EdgeTrim",v.model,CFrame.new(c[1]+c[3]*0.6,v.y0,c[2]+c[4]*0.6),Vector3.new(2.4,v.y1-v.y0,2.4)).Name="KTrim" end end
end
function M.register(par,model)
 local c=model:FindFirstChild("Core") if not c then return end local h=c.Size/2 local p=c.Position
 table.insert(M.vols,{name=model.Name,x1=p.X-h.X,x2=p.X+h.X,z1=p.Z-h.Z,z2=p.Z+h.Z,y0=p.Y-h.Y,y1=p.Y+h.Y,opt={},par=par,model=model})
end
return M
