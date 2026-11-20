local K={}
local LIB=game.ServerStorage.KitLib
function K.native(name) local m=LIB[name] return Vector3.new(m:GetAttribute("SizeX"),m:GetAttribute("SizeY"),m:GetAttribute("SizeZ")) end
-- put kit piece with bottom-centre at baseCF, optional kit-local target size
function K.put(name,parent,baseCF,size)
 local src=LIB:FindFirstChild(name) if not src then warn("no kit "..name) return end
 local m=src:Clone()
 if size then local n=K.native(name) local s=Vector3.new(size.X/n.X,size.Y/n.Y,size.Z/n.Z)
  for _,p in ipairs(m:GetChildren()) do if p:IsA("BasePart") then p.Size=p.Size*s p.Position=p.Position*s end end end
 m.WorldPivot=CFrame.new() m:PivotTo(baseCF) m.Parent=parent return m end
-- tile a piece along a line from a to b (bottom points), piece X along the line
function K.tile(name,parent,a,b,h,depth,maxW,out,tag)
 local d=b-a local L=Vector3.new(d.X,0,d.Z).Magnitude if L<0.5 then return end
 local n=K.native(name) local w=maxW or n.X local cnt=math.max(1,math.floor(L/w+0.5)) local seg=L/cnt
 local dir=Vector3.new(d.X,0,d.Z).Unit local yaw=math.atan2(-dir.Z,dir.X)
 for i=0,cnt-1 do local c=a+dir*(seg*(i+0.5))
  local m=K.put(name,parent,CFrame.new(c)*CFrame.Angles(0,yaw,0),Vector3.new(seg,h or n.Y,depth or n.Z))
  if m and out and m:GetPivot().LookVector:Dot(out)<0 then m:PivotTo(m:GetPivot()*CFrame.Angles(0,math.pi,0)) end
  if m and tag then m.Name=tag end end
end
-- fit a panel-like piece into an axis-aligned box (thin axis -> kit Z)
function K.fitBox(name,parent,cf,size,outward)
 local yaw=0 local kx,kz=size.X,size.Z
 if size.X<size.Z then yaw=math.pi/2 kx,kz=size.Z,size.X end
 if outward then -- outward world dir; kit front is +Z
  local f=CFrame.Angles(0,yaw,0).LookVector if f:Dot(outward)<0 then yaw+=math.pi end end
 return K.put(name,parent,CFrame.new(cf.Position-Vector3.new(0,size.Y/2,0))*CFrame.Angles(0,yaw,0),Vector3.new(kx,size.Y,math.max(kz,0.5)))
end
-- flip pieces so their front (-Z) faces open air
function K.faceOut(models,ignore)
 local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude
 local n=0
 for _,m in ipairs(models) do
  rp.FilterDescendantsInstances={m,ignore}
  local cf,sz=m:GetBoundingBox() local f=m:GetPivot().LookVector local d=math.max(sz.X,sz.Z)/2+6
  local hf=workspace:Raycast(cf.Position,f*d,rp) local hb=workspace:Raycast(cf.Position,-f*d,rp)
  if hf and not hb then m:PivotTo(m:GetPivot()*CFrame.Angles(0,math.pi,0)) n+=1 end
 end return n end
return K
