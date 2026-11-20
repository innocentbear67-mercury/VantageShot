local I={}
local LIB=game.ServerStorage.IntLib
function I.native(n) local m=LIB[n] return Vector3.new(m:GetAttribute("SizeX"),m:GetAttribute("SizeY"),m:GetAttribute("SizeZ")) end
function I.put(name,par,cf,size)
 local m=LIB[name]:Clone()
 if size then local n=I.native(name) local s=Vector3.new(size.X/n.X,size.Y/n.Y,size.Z/n.Z)
  for _,p in ipairs(m:GetChildren()) do p.Size=p.Size*s p.Position=p.Position*s end end
 m.WorldPivot=CFrame.new() m:PivotTo(cf) m.Parent=par return m end
local function yawFor(dir,inN) -- local X along dir, front (-Z) facing inN
 local yaw=math.atan2(-dir.Z,dir.X) local cf=CFrame.Angles(0,yaw,0)
 if cf.LookVector:Dot(inN)<0 then yaw+=math.pi end return yaw end
I.yawFor=yawFor
local LOW={"Int_WallBay","Int_WallPipes","Int_WallLight","Int_WallVent","Int_WallBay","Int_WallPlain","Int_WallLight"}
local UP={"Int_WallPlain","Int_WallVent","Int_WallBay","Int_WallLight","Int_WallPlain"}
function I.wall(par,a,b,y0,y1,inN,seed)
 local d=Vector3.new(b.X-a.X,0,b.Z-a.Z) local L=d.Magnitude if L<1.5 then return end local dir=d.Unit
 local cnt=math.max(1,math.floor(L/8+0.5)) local w=L/cnt
 local rows=math.max(1,math.floor((y1-y0)/12+0.5)) local rh=(y1-y0)/rows
 local yaw=yawFor(dir,inN) seed=seed or 0
 for i=0,cnt-1 do local c=a+dir*w*(i+0.5)
  for r=0,rows-1 do local list=(r==0) and LOW or UP local nm=list[(i+seed+r*3)%#list+1]
   local nat=I.native(nm)
   I.put(nm,par,CFrame.new(c.X,y0+rh*r,c.Z)*CFrame.Angles(0,yaw,0),Vector3.new(w,rh,nat.Z)).Name="IW"
  end
 end
end
function I.ceiling(par,x1,z1,x2,z2,y,opts)
 opts=opts or {}
 local W,D=x2-x1,z2-z1 local alongX=W>=D
 local L=alongX and W or D local S=alongX and D or W
 local n=math.max(2,math.floor(L/12+0.5)) local step=L/n
 for i=0,n do local t=step*i if i==0 then t=0.8 elseif i==n then t=L-0.8 end
  local x=alongX and (x1+t) or (x1+W/2) local z=alongX and (z1+D/2) or (z1+t)
  local yaw=alongX and math.pi/2 or 0
  I.put("Int_CeilingBeam",par,CFrame.new(x,y-2.5,z)*CFrame.Angles(0,yaw,0),Vector3.new(S,2.5,1.5)).Name="CeilBeam"
 end
 -- lights between beams, two rows
 local k=0
 for i=0,n-1 do local t=step*(i+0.5)
  for _,f in ipairs((S>20) and {0.27,0.73} or {0.5}) do k+=1
   local x=alongX and (x1+t) or (x1+S*f) local z=alongX and (z1+S*f) or (z1+t)
   local nm=(opts.round and k%3==0) and "Int_LightRound" or "Int_LightPanel"
   local hang=(nm=="Int_LightRound") and 4.6 or 3.0
   local m=I.put(nm,par,CFrame.new(x,y-hang,z)*CFrame.Angles(0,alongX and math.pi/2 or 0,0),nil) m.Name="CeilLight"
   if k%2==1 then local e=m:FindFirstChild("Emit_White") if e then local s=Instance.new("SurfaceLight") s.Face=Enum.NormalId.Bottom s.Range=26 s.Brightness=1.5 s.Angle=120 s.Color=Color3.fromRGB(230,238,255) s.Parent=e end end
  end
 end
 -- cable tray + pipe run along one long side
 if not opts.noTray then
  local nt=math.max(1,math.floor(L/10+0.5)) local tw=L/nt
  for i=0,nt-1 do local t=tw*(i+0.5)
   local x=alongX and (x1+t) or (x1+3) local z=alongX and (z1+3) or (z1+t)
   I.put("Int_CableTray",par,CFrame.new(x,y-3.4,z)*CFrame.Angles(0,alongX and 0 or math.pi/2,0),Vector3.new(tw,3.1,2.0)).Name="Tray"
   local px=alongX and (x1+t) or (x2-2.2) local pz=alongX and (z2-2.2) or (z1+t)
   I.put("Int_PipeStraight",par,CFrame.new(px,y-5.2,pz)*CFrame.Angles(0,alongX and 0 or math.pi/2,0),Vector3.new(tw,1.6,1.5)).Name="Pipe"
  end
 end
end
function I.floor(par,x1,z1,x2,z2,y,grateEvery)
 local W,D=x2-x1,z2-z1 local nx=math.max(1,math.floor(W/8+0.5)) local nz=math.max(1,math.floor(D/8+0.5))
 local sx,sz=W/nx,D/nz local k=0
 for i=0,nx-1 do for j=0,nz-1 do k+=1
  local nm=(grateEvery and k%grateEvery==0) and "Int_FloorGrate" or "Int_FloorPlate"
  I.put(nm,par,CFrame.new(x1+sx*(i+0.5),y-0.45,z1+sz*(j+0.5)),Vector3.new(sx,0.5,sz)).Name="IFloor" end end
end
function I.pillar(par,x,z,y0,y1) I.put("Int_Pillar",par,CFrame.new(x,y0,z),Vector3.new(4.8,y1-y0,4.8)).Name="IPillar" end
function I.door(par,cx,cz,axis,w,h,y0,inN)
 local dir=axis=="x" and Vector3.xAxis or Vector3.zAxis local yaw=yawFor(dir,inN)
 local c=Vector3.new(cx,y0,cz)+inN*1.0
 local m=I.put("Int_Bulkhead",par,CFrame.new(c)*CFrame.Angles(0,yaw,0),Vector3.new(16*w/12,15.3*h/12.4,2.8)) m.Name="IDoor"
 local e=m:FindFirstChild("Emit_Blue") if e then local l=Instance.new("PointLight") l.Color=Color3.fromRGB(70,160,255) l.Range=14 l.Brightness=1.2 l.Parent=e end
 return m
end
function I.prop(name,par,x,y,z,yaw,scale)
 local nat=I.native(name) local m=I.put(name,par,CFrame.new(x,y,z)*CFrame.Angles(0,yaw or 0,0),scale and nat*scale or nil) m.Name=name
 local e=m:FindFirstChild("Emit_Screen") if e then local l=Instance.new("PointLight") l.Color=Color3.fromRGB(80,170,255) l.Range=10 l.Brightness=0.9 l.Parent=e end
 return m end
-- swap a kit rail model for the metal rail (keeps placement/length)
function I.swapRail(r)
 local cf,sz=r:GetBoundingBox() local piv=r:GetPivot()
 local len=math.max(sz.X,sz.Z)
 local m=I.put("Int_Rail",r.Parent,piv,Vector3.new(len,3.5,0.6)) m.Name=r.Name r:Destroy() return m end
return I
