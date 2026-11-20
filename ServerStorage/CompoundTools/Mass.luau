local P=require(script.Parent.Plot) local K=require(script.Parent.Kit2) local D=require(script.Parent.Dress)
local M={}
local G=P.G
M.TH=78
local JOINT=K.JOINT
-- faces: table with keys N,S,E,W = true (N = -z side, S = +z side, W = -x, E = +x)
function M.mass(par,name,x1,z1,x2,z2,y0,H,faces,rng,opts)
 opts=opts or {}
 local m=P.model(par,name)
 local core=P.box(m,"Core",x1,y0,z1,x2,y0+H,z2,"d") core.Color=JOINT core.Material=Enum.Material.Concrete core.MaterialVariant=""
 local cap=P.box(m,"Cap",x1-0.8,y0+H,z1-0.8,x2+0.8,y0+H+1.6,z2+0.8,"d")
 local py0=(y0<=G+0.5) and y0+2.1 or y0
 local function face(side)
  if side=="N" then K.panels(m,"x",x1,x2,z1,-1,py0,y0+H,rng,9,13) if y0<=G+0.5 then P.baseStrip(m,"x",x1,x2,z1,-1,y0) end
  elseif side=="S" then K.panels(m,"x",x1,x2,z2,1,py0,y0+H,rng,9,13) if y0<=G+0.5 then P.baseStrip(m,"x",x1,x2,z2,1,y0) end
  elseif side=="W" then K.panels(m,"z",z1,z2,x1,-1,py0,y0+H,rng,9,13) if y0<=G+0.5 then P.baseStrip(m,"z",z1,z2,x1,-1,y0) end
  elseif side=="E" then K.panels(m,"z",z1,z2,x2,1,py0,y0+H,rng,9,13) if y0<=G+0.5 then P.baseStrip(m,"z",z1,z2,x2,1,y0) end end
 end
 for _,s in ipairs({"N","S","E","W"}) do if faces[s] then face(s) end end
 -- dark horizontal bands every ~26 (storey lines) on visible faces
 for yy=y0+26,y0+H-4,26 do for _,s in ipairs({"N","S","E","W"}) do if faces[s] then
  if s=="N" then P.band(m,"x",x1,x2,z1,-1,yy,yy+1.4,"d",1.0) elseif s=="S" then P.band(m,"x",x1,x2,z2,1,yy,yy+1.4,"d",1.0)
  elseif s=="W" then P.band(m,"z",z1,z2,x1,-1,yy,yy+1.4,"d",1.0) else P.band(m,"z",z1,z2,x2,1,yy,yy+1.4,"d",1.0) end end end end
 -- truss columns + vents + an occasional cantilever box
 for _,s in ipairs({"N","S","E","W"}) do if faces[s] then
  local axis=(s=="N" or s=="S") and "x" or "z"
  local a1,a2=(axis=="x") and x1 or z1,(axis=="x") and x2 or z2
  local f=(s=="N" and z1) or (s=="S" and z2) or (s=="W" and x1) or x2
  local n=(s=="N" or s=="W") and -1 or 1
  local L=a2-a1
  if L>=40 then for a=a1+L*0.18,a2-4,math.max(40,L/3) do D.truss(m,axis,a,f,n,y0,y0+H) end end
  for k=1,math.floor(L*H/700) do local sz=rng:NextNumber()<0.7 and 1.2 or 0.9 local h=rng:NextNumber()<0.3 and 2.6 or sz
   local u=rng:NextNumber(a1+2,a2-2-sz) local yy=rng:NextNumber(y0+6,y0+H-4)
   local v=axis=="x" and P.box(m,"Vent",u,yy,f+n*0.3,u+sz,yy+h,f+n*0.66,"void") or P.box(m,"Vent",f+n*0.3,yy,u,f+n*0.66,yy+h,u+sz,"void")
   if v then K.drip(m,axis=="x" and Vector3.new(u+sz/2,yy,f+n*0.62) or Vector3.new(f+n*0.62,yy,u+sz/2),axis,sz,n) end end
  if L>=36 and rng:NextNumber()<0.6 then local c=rng:NextNumber(a1+10,a2-24) D.cantilever(m,axis,c,c+18,f,n,y0+H-16,y0+H-6,5) end
 end end
 return m
end
return M
