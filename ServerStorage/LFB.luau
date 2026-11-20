local SS=game.ServerStorage
local L={}
L.G,L.T1,L.T2=2,28,54
L.WHITE=Color3.fromRGB(234,235,231) L.DARK=Color3.fromRGB(52,54,58) L.BEAM=Color3.fromRGB(40,42,46)
L.BLUE=Color3.fromRGB(70,160,255) L.FLOOR=Color3.fromRGB(38,40,44)
function L.init()
 local K=require(SS.KitPlace:Clone())
 local M=_G.LFM
 if not M then M=require(SS.Mass3:Clone()) M.init(K) M.bounds=nil _G.LFM=M
  -- re-register any existing volumes
  for _,d in ipairs(workspace.Map_LiveFire.Structure:GetDescendants()) do if d:IsA("Model") and d:FindFirstChild("Core") and d.Core:IsA("BasePart") then M.register(d.Parent,d) end end
 end
 L.K=K L.M=M L.B=require(SS.CompoundTools:Clone().Build)
 L.S=workspace.Map_LiveFire.Structure
 return L
end
function L.part(par,name,x1,y1,z1,x2,y2,z2,color,mat)
 local p=Instance.new("Part") p.Name=name p.Anchored=true p.TopSurface=0 p.BottomSurface=0
 p.Size=Vector3.new(math.max(math.abs(x2-x1),0.05),math.max(math.abs(y2-y1),0.05),math.max(math.abs(z2-z1),0.05))
 p.CFrame=CFrame.new((x1+x2)/2,(y1+y2)/2,(z1+z2)/2) p.Color=color or L.DARK p.Material=mat or Enum.Material.Metal p.Parent=par return p end
function L.face(m,f) if m and m:GetPivot().LookVector:Dot(f)<0 then m:PivotTo(m:GetPivot()*CFrame.Angles(0,math.pi,0)) end return m end
local function lineTiles(par,kit,a,b,h,depth,maxw,out,name,yoff)
 local d=Vector3.new(b.X-a.X,0,b.Z-a.Z) local Ln=d.Magnitude if Ln<0.5 then return end local dir=d.Unit
 local n=math.max(1,math.floor(Ln/maxw+0.5)) local seg=Ln/n local yaw=math.atan2(-dir.Z,dir.X)
 for i=0,n-1 do local c=a+dir*seg*(i+0.5)+(out*(yoff or 0))
  local m=L.K.put(kit,par,CFrame.new(c)*CFrame.Angles(0,yaw,0),Vector3.new(seg,h,depth)) L.face(m,out) m.Name=name end
end
function L.rail(par,a,b,y,out) lineTiles(par,"Kit_Rail",Vector3.new(a.X,y,a.Z),Vector3.new(b.X,y,b.Z),3.6,0.4,6.3,out,"Rail") end
function L.fascia(par,a,b,ytop,out) lineTiles(par,"Kit_FasciaX",Vector3.new(a.X,ytop-4.2,a.Z),Vector3.new(b.X,ytop-4.2,b.Z),4.2,1.5,5.3,out,"Fascia",0.75) end
function L.deck(par,name,x1,z1,x2,z2,top)
 local m=Instance.new("Model") m.Name=name m.Parent=par
 L.part(m,"DeckBeam",x1,top-1.4,z1,x2,top-0.4,z2,L.BEAM)
 local W,D=x2-x1,z2-z1 local nx=math.max(1,math.floor(W/10+0.5)) local nz=math.max(1,math.floor(D/10+0.5))
 for i=0,nx-1 do for j=0,nz-1 do local g=L.K.put("Kit_GrateFloor",m,CFrame.new(x1+W/nx*(i+0.5),top-0.4,z1+D/nz*(j+0.5)),Vector3.new(W/nx,0.4,D/nz))
  for _,p in ipairs(g:GetChildren()) do p.TextureID="" p.Material=Enum.Material.DiamondPlate p.Color=Color3.fromRGB(78,80,84) end g.Name="Grate" end end
 return m
end
-- bridge between two points on same y, axis aligned; rails + fascia both sides
function L.bridge(par,name,ax,az,bx,bz,y,w)
 w=w or 8 local m
 if math.abs(ax-bx)>math.abs(az-bz) then local x1,x2=math.min(ax,bx),math.max(ax,bx)
  m=L.deck(par,name,x1,az-w/2,x2,az+w/2,y)
  L.rail(m,Vector3.new(x1,0,az-w/2+0.3),Vector3.new(x2,0,az-w/2+0.3),y,Vector3.new(0,0,-1)) L.rail(m,Vector3.new(x1,0,az+w/2-0.3),Vector3.new(x2,0,az+w/2-0.3),y,Vector3.new(0,0,1))
  L.fascia(m,Vector3.new(x1,0,az-w/2),Vector3.new(x2,0,az-w/2),y,Vector3.new(0,0,-1)) L.fascia(m,Vector3.new(x1,0,az+w/2),Vector3.new(x2,0,az+w/2),y,Vector3.new(0,0,1))
 else local z1,z2=math.min(az,bz),math.max(az,bz)
  m=L.deck(par,name,ax-w/2,z1,ax+w/2,z2,y)
  L.rail(m,Vector3.new(ax-w/2+0.3,0,z1),Vector3.new(ax-w/2+0.3,0,z2),y,Vector3.new(-1,0,0)) L.rail(m,Vector3.new(ax+w/2-0.3,0,z1),Vector3.new(ax+w/2-0.3,0,z2),y,Vector3.new(1,0,0))
  L.fascia(m,Vector3.new(ax-w/2,0,z1),Vector3.new(ax-w/2,0,z2),y,Vector3.new(-1,0,0)) L.fascia(m,Vector3.new(ax+w/2,0,z1),Vector3.new(ax+w/2,0,z2),y,Vector3.new(1,0,0))
 end
 return m
end
function L.pillar(par,x,z,y0,y1,w)
 L.K.put("Kit_PillarShaft",par,CFrame.new(x,y0,z),Vector3.new(w,y1-y0,w)).Name="Pillar"
 L.K.put("Kit_PillarFoot",par,CFrame.new(x,y0-0.2,z),Vector3.new(w+1.6,2.4,w+1.6)).Name="Pillar"
 L.K.put("Kit_PillarCap",par,CFrame.new(x,y1-1.2,z),Vector3.new(w+1,1.2,w+1)).Name="Pillar"
end
function L.stair(par,x,z,dir,w,y0,y1) return L.B.wideStair(par,x,z,dir,w,y0,y1,"both") end
function L.neon(par,x1,y1,z1,x2,y2,z2,color,light)
 local p=L.part(par,"BlueStrip",x1,y1,z1,x2,y2,z2,color or L.BLUE,Enum.Material.Neon) p.CanCollide=false
 if light then local s=Instance.new("PointLight") s.Range=light s.Brightness=1.4 s.Color=color or L.BLUE s.Parent=p end
 return p end
function L.vol(par,name,x1,z1,x2,z2,y0,y1,opt) return L.M.vol(par,name,x1,z1,x2,z2,y0,y1,opt) end
function L.dress(list,seed) local rng=Random.new(seed or 7) for i,v in ipairs(list) do L.M.dress(v,rng) if i%3==0 then task.wait() end end end
-- hollow shell: walls (with door gaps + lintels) and a hidden roof slab; returns list of volumes
-- doors: {side="N"|"S"|"E"|"W", c=centre along wall, w=width, h=height}
function L.shell(par,name,x1,z1,x2,z2,y0,y1,t,doors,roofT)
 t=t or 4 roofT=roofT or 2 doors=doors or {} local vols={}
 local walls={N={axis="x",a=x1,b=x2,o1=z1,o2=z1+t,inN=Vector3.new(0,0,1)},S={axis="x",a=x1,b=x2,o1=z2-t,o2=z2,inN=Vector3.new(0,0,-1)},
  W={axis="z",a=z1+t,b=z2-t,o1=x1,o2=x1+t,inN=Vector3.new(1,0,0)},E={axis="z",a=z1+t,b=z2-t,o1=x2-t,o2=x2,inN=Vector3.new(-1,0,0)}}
 for side,wl in pairs(walls) do
  local ds={} for _,d in ipairs(doors) do if d.side==side then table.insert(ds,d) end end
  table.sort(ds,function(p,q) return p.c<q.c end)
  local cur=wl.a local k=0
  local function seg(s,e,ya,yb,suffix)
   if e-s<0.5 then return end k+=1
   local v if wl.axis=="x" then v=L.vol(par,name.."_"..side..suffix..k,s,wl.o1,e,wl.o2,ya,yb,{skip={wl.inN}})
   else v=L.vol(par,name.."_"..side..suffix..k,wl.o1,s,wl.o2,e,ya,yb,{skip={wl.inN}}) end
   table.insert(vols,v) end
  for _,d in ipairs(ds) do local s,e=d.c-d.w/2,d.c+d.w/2 seg(cur,s,y0,y1,"") seg(s,e,y0+d.h,y1,"L") cur=e end
  seg(cur,wl.b,y0,y1,"")
 end
 local r=L.vol(par,name.."_Roof",x1+t,z1+t,x2-t,z2-t,y1-roofT,y1,{skip={Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1)}})
 r.roof=true table.insert(vols,r)
 return vols
end
-- interior wall dressing along an inner face line
function L.intWall(par,a,b,y0,y1,inN,opts)
 opts=opts or {}
 local d=Vector3.new(b.X-a.X,0,b.Z-a.Z) local Ln=d.Magnitude local dir=d.Unit
 local n=math.max(1,math.floor(Ln/10+0.5)) local seg=Ln/n local rows=math.max(1,math.floor((y1-y0)/12+0.5)) local rh=(y1-y0)/rows
 local yaw=math.atan2(-dir.Z,dir.X)
 for i=0,n-1 do for r=0,rows-1 do local c=a+dir*seg*(i+0.5)+inN*0.6
  local m=L.K.put("Kit_GunmetalPanel",par,CFrame.new(c.X,y0+rh*r,c.Z)*CFrame.Angles(0,yaw,0),Vector3.new(seg,rh,1.2)) L.face(m,inN) m.Name="IntPanel" end end
 -- blue light strips between every 2 panels
 if opts.blue~=false then for i=2,n-1,3 do local c=a+dir*seg*i+inN*1.25
  local half=Vector3.new(math.abs(inN.Z)*0.25+0.01,0,math.abs(inN.X)*0.25+0.01)
  L.neon(par,c.X-half.X-math.abs(dir.X)*0.3,y0+3,c.Z-half.Z-math.abs(dir.Z)*0.3,c.X+half.X+math.abs(dir.X)*0.3,y1-4,c.Z+half.Z+math.abs(dir.Z)*0.3,L.BLUE,i%6==2 and 18 or nil) end end
 if opts.pipe then for i=0,math.floor(Ln/20)-1 do local c=a+dir*(20*i+10)+inN*1.9 L.face(L.K.put("Kit_PipeRun",par,CFrame.new(c.X,y1-6,c.Z)*CFrame.Angles(0,yaw,0),Vector3.new(20,2.4,1.3)),inN) end end
end
-- ceiling light grid
function L.ceiling(par,x1,z1,x2,z2,y,step)
 step=step or 14 local k=0
 for x=x1+step/2,x2-step/2,step do for z=z1+step/2,z2-step/2,step do k+=1
  local p=L.part(par,"CeilLight",x-3,y-0.3,z-1.2,x+3,y,z+1.2,Color3.fromRGB(235,242,255),Enum.Material.Neon) p.CanCollide=false
  if k%3==1 then local s=Instance.new("SurfaceLight") s.Face=Enum.NormalId.Bottom s.Range=26 s.Brightness=1.6 s.Angle=110 s.Color=Color3.fromRGB(230,238,255) s.Parent=p end
  L.part(par,"CeilBeam",x1,y,z-0.4,x2,y+1.2,z+0.4,L.BEAM).CanCollide=false
 end end
end
-- console with blue screen
function L.console(par,x,y,z,yaw)
 local m=L.K.put("Kit_Cabinet",par,CFrame.new(x,y,z)*CFrame.Angles(0,yaw or 0,0),Vector3.new(5,3.6,2.6)) m.Name="Console"
 local cf=CFrame.new(x,y+4.6,z)*CFrame.Angles(0,yaw or 0,0)*CFrame.Angles(math.rad(-15),0,0)
 local s=Instance.new("Part") s.Name="Screen" s.Anchored=true s.Size=Vector3.new(4.6,2.6,0.25) s.CFrame=cf s.Material=Enum.Material.Neon s.Color=Color3.fromRGB(60,150,255) s.Parent=par
 local fr=Instance.new("Part") fr.Name="ScreenFrame" fr.Anchored=true fr.Size=Vector3.new(5.0,3.0,0.3) fr.CFrame=cf*CFrame.new(0,0,0.2) fr.Material=Enum.Material.Metal fr.Color=L.BEAM fr.Parent=par
 local pl=Instance.new("PointLight") pl.Range=10 pl.Brightness=0.9 pl.Color=Color3.fromRGB(80,160,255) pl.Parent=s
end
function L.screenWall(par,cx,y0,cz,w,h,inN)
 local half=Vector3.new(math.abs(inN.Z)*w/2,0,math.abs(inN.X)*w/2)
 local c=Vector3.new(cx,0,cz)+inN*0.9
 local fr=L.part(par,"ScreenFrame",c.X-half.X-0.6*math.abs(inN.Z)-0.2*math.abs(inN.X),y0-0.6,c.Z-half.Z-0.6*math.abs(inN.X)-0.2*math.abs(inN.Z),c.X+half.X+0.6*math.abs(inN.Z)+0.2*math.abs(inN.X),y0+h+0.6,c.Z+half.Z+0.6*math.abs(inN.X)+0.2*math.abs(inN.Z),L.BEAM)
 local sc=inN*0.25 local p=L.part(par,"BigScreen",c.X+sc.X-half.X-0.1*math.abs(inN.X),y0,c.Z+sc.Z-half.Z-0.1*math.abs(inN.Z),c.X+sc.X+half.X+0.1*math.abs(inN.X),y0+h,c.Z+sc.Z+half.Z+0.1*math.abs(inN.Z),Color3.fromRGB(40,120,230),Enum.Material.Neon)
 p.CanCollide=false local s=Instance.new("SurfaceLight") s.Range=24 s.Brightness=1.2 s.Color=Color3.fromRGB(80,160,255) s.Face=(inN.X>0.5 and Enum.NormalId.Right) or (inN.X<-0.5 and Enum.NormalId.Left) or (inN.Z>0.5 and Enum.NormalId.Back) or Enum.NormalId.Front s.Parent=p
end
-- blue-lit door frame on a wall opening: centre (cx,cz), axis "x" (wall runs along x) or "z", width w, height h, out normal
function L.doorFrame(par,cx,cz,axis,w,h,y0,out)
 local jt=1.4
 for _,s in ipairs({-1,1}) do
  local ox=axis=="x" and s*(w/2+jt/2) or 0 local oz=axis=="z" and s*(w/2+jt/2) or 0
  local o=out*1.2
  L.part(par,"DoorJamb",cx+ox-(axis=="x" and jt/2 or 1.2),y0,cz+oz-(axis=="z" and jt/2 or 1.2),cx+ox+(axis=="x" and jt/2 or 1.2),y0+h+jt,cz+oz+(axis=="z" and jt/2 or 1.2),L.BEAM)
  local bx=cx+(axis=="x" and s*(w/2-0.15) or 0)+o.X local bz=cz+(axis=="z" and s*(w/2-0.15) or 0)+o.Z
  L.neon(par,bx-0.15,y0+0.5,bz-0.15,bx+0.15,y0+h-0.3,bz+0.15,L.BLUE)
 end
 local hx=axis=="x" and (w/2+jt) or 1.2 local hz=axis=="z" and (w/2+jt) or 1.2
 L.part(par,"DoorHeader",cx-hx,y0+h,cz-hz,cx+hx,y0+h+jt,cz+hz,L.BEAM)
 local nx=cx+out.X*1.25 local nz=cz+out.Z*1.25
 L.neon(par,nx-(axis=="x" and w/2 or 0.12),y0+h+0.35,nz-(axis=="z" and w/2 or 0.12),nx+(axis=="x" and w/2 or 0.12),y0+h+0.65,nz+(axis=="z" and w/2 or 0.12),L.BLUE,16)
end
-- polished interior floor
function L.floor(par,x1,z1,x2,z2,y)
 local p=L.part(par,"IntFloor",x1,y-0.6,z1,x2,y,z2,L.FLOOR,Enum.Material.SmoothPlastic) p.Reflectance=0.08 return p end
-- remove rails (and optionally crown fascia/cornice) inside a box so a bridge/stair/landing can join an edge
function L.openEdge(x1,z1,x2,z2,y,tol)
 tol=tol or 3 local n=0
 for _,d in ipairs(L.S:GetDescendants()) do
  if d:IsA("Model") and (d.Name=="KRail" or d.Name=="Rail" or d.Name=="KFascia" or d.Name=="KCornice") then local p=d:GetPivot().Position
   local hy=(d.Name=="KFascia" or d.Name=="KCornice") and (p.Y+4.2) or p.Y
   if p.X>x1 and p.X<x2 and p.Z>z1 and p.Z<z2 and math.abs(hy-y)<tol then d:Destroy() n+=1 end end end
 return n end
-- dark gunmetal block (registered as a volume for exposure; dressed in gunmetal instead of white)
function L.darkBox(par,name,x1,z1,x2,z2,y0,y1,railTop)
 local v=L.vol(par,name,x1,z1,x2,z2,y0,y1) local mdl=v.model
 mdl.Core.Color=L.DARK mdl.Core.Material=Enum.Material.Metal
 local fs={{Vector3.new(x1,0,z2),Vector3.new(x2,0,z2),Vector3.new(0,0,1)},{Vector3.new(x2,0,z1),Vector3.new(x1,0,z1),Vector3.new(0,0,-1)},{Vector3.new(x2,0,z2),Vector3.new(x2,0,z1),Vector3.new(1,0,0)},{Vector3.new(x1,0,z1),Vector3.new(x1,0,z2),Vector3.new(-1,0,0)}}
 for _,f in ipairs(fs) do local a,b,n=f[1],f[2],f[3] local L2=(b-a).Magnitude local dir=(b-a).Unit local yaw=math.atan2(-dir.Z,dir.X)
  local cols=math.max(1,math.floor(L2/10+0.5)) local cw=L2/cols local rows=math.max(1,math.floor((y1-y0-4.2)/12+0.5)) local rh=(y1-y0-4.2)/rows
  for c=0,cols-1 do for r=0,rows-1 do local t=cw*(c+0.5) local q=a+dir*t
   if not L.M.inside(q+n*1.5+Vector3.new(0,y0+rh*(r+0.5),0),v) then
    L.face(L.K.put("Kit_GunmetalPanel",mdl,CFrame.new(q.X,y0+4.2+rh*r,q.Z)*CFrame.Angles(0,yaw,0),Vector3.new(cw,rh,1.2)),n).Name="KGun" end end end
  local fc=math.max(1,math.floor(L2/5.3+0.5)) local fw=L2/fc
  for c=0,fc-1 do local q=a+dir*fw*(c+0.5)
   if not L.M.inside(q+n*1.5+Vector3.new(0,y0+2,0),v) then L.face(L.K.put("Kit_FasciaX",mdl,CFrame.new(q.X+n.X*1.25,y0,q.Z+n.Z*1.25)*CFrame.Angles(0,yaw,0),Vector3.new(fw,4.2,1.5)),n).Name="KFascia" end
   if not L.M.inside(q+n*1.5+Vector3.new(0,y1-2,0),v) then L.face(L.K.put("Kit_FasciaX",mdl,CFrame.new(q.X+n.X*1.25,y1-4.2,q.Z+n.Z*1.25)*CFrame.Angles(0,yaw,0),Vector3.new(fw,4.2,1.5)),n).Name="KFascia" end
  end
  if railTop~=false then local rc=math.max(1,math.floor(L2/6.3+0.5)) local rw=L2/rc
   for c=0,rc-1 do local q=a+dir*rw*(c+0.5)+n*1.1 local mm=L.K.put("Kit_Rail",mdl,CFrame.new(q.X,y1,q.Z)*CFrame.Angles(0,yaw,0),Vector3.new(rw,3.6,0.4)) L.face(mm,n) mm.Name="KRail" end end
 end
 for _,c in ipairs({{x1,z1},{x2,z1},{x1,z2},{x2,z2}}) do L.K.put("Kit_EdgeTrim",mdl,CFrame.new(c[1],y0,c[2]),Vector3.new(2.6,y1-y0,2.6)).Name="KTrim" end
 return v
end
return L
