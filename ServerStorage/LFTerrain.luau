local T={}
T.RX,T.RZ=330,280      -- compound plateau
T.OX,T.OZ=480,420      -- outer wilderness edge (cliffs start)
local noise=math.noise
local function sm(a,b,x) local t=math.clamp((x-a)/(b-a),0,1) return t*t*(3-2*t) end
function T.sample(x,z)
 local e=math.sqrt((x/T.RX)^2+(z/T.RZ)^2)
 local r=math.sqrt((x/T.OX)^2+(z/T.OZ)^2)
 local n1=noise(x/90,z/90,1.7) local n2=noise(x/30,z/30,4.2)
 if e<=1 then
  if e>0.93 then return 2,Enum.Material.Asphalt end
  return 2,Enum.Material.Concrete
 end
 if r<1 then
  local h=2+ (n1*5+n2*1.5) + 14*sm(0.82,1.0,r) + 3*sm(1.0,1.12,e)
  -- river channel west/north
  local ang=math.deg(math.atan2(z,x)) if ang<0 then ang+=360 end
  local rr=math.sqrt((x/400)^2+(z/352)^2)
  local mat=(n2>0.25 and Enum.Material.Ground) or (n1>0.35 and Enum.Material.Rock) or Enum.Material.Grass
  if ang>140 and ang<300 then local d=math.abs(rr-1)*370 if d<12 then return 0,Enum.Material.Mud,true elseif d<18 then return math.min(h,1),Enum.Material.Ground end end
  return h,mat
 end
 -- cliffs then mountains: ridged peaks rising away from the compound
 local k=r-1
 local ridge=1-math.abs(noise(x/160,z/160,9.1)) local ridge2=1-math.abs(noise(x/70,z/70,3.3))
 local h=16+k*150+ (ridge^2)*95*math.min(1,k*3)+ridge2*22*math.min(1,k*4)+n2*6
 h=math.min(h,175)
 local mat=Enum.Material.Rock if h>118+n2*20 then mat=Enum.Material.Snow end
 return h,mat
end
function T.fillStrip(x0,x1,z0,z1,cell,outerOnly)
 local TR=workspace.Terrain local c=0
 for x=x0,x1-cell,cell do for z=z0,z1-cell,cell do
  local cx,cz=x+cell/2,z+cell/2
  if outerOnly and math.sqrt((cx/T.OX)^2+(cz/T.OZ)^2)<1 then c+=1 continue end
  local h,mat,water=T.sample(cx,cz)
  local e=math.sqrt((cx/T.RX)^2+(cz/T.RZ)^2)
  local bottom=(e<=1.05) and -44 or -12
  local top=h
  if top>bottom then
   local sub=(mat==Enum.Material.Snow or mat==Enum.Material.Rock) and Enum.Material.Rock or ((e<=1) and Enum.Material.Concrete or Enum.Material.Ground)
   if top-bottom>6 then TR:FillBlock(CFrame.new(cx,(bottom+top-4)/2,cz),Vector3.new(cell,top-4-bottom,cell),sub) end
   TR:FillBlock(CFrame.new(cx,top-2,cz),Vector3.new(cell,4,cell),mat)
   if water then TR:FillBlock(CFrame.new(cx,1.5,cz),Vector3.new(cell,3,cell),Enum.Material.Water) end
  end
  c+=1 if c%400==0 then task.wait() end
 end end
 return c
end
return T
