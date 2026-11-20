local P=require(script.Parent.Plot)
local D=require(script.Parent.Dress)
local B={}
local G=P.G
B.L1=G+12.6 B.L2=G+24.6
-- shell: walls on 4 sides from y0..y1 with holes; doors {side,c,w,lo,h}
function B.shell(m,x1,z1,x2,z2,y0,y1,doors,k,t)
 t=t or 2
 local function hs(side) local r={} for _,d in ipairs(doors or {}) do if d[1]==side then local w=d[3] or 8 local lo=d[4] or y0 local h=d[5] or 9 table.insert(r,{d[2]-w/2,d[2]+w/2,lo,lo+h}) end end return r end
 P.wallX(m,x1,x2,z1+t/2,t,y0,y1,hs("N"),k) P.wallX(m,x1,x2,z2-t/2,t,y0,y1,hs("S"),k)
 P.wallZ(m,z1+t,z2-t,x1+t/2,t,y0,y1,hs("W"),k) P.wallZ(m,z1+t,z2-t,x2-t/2,t,y0,y1,hs("E"),k)
end
-- floor slab with rectangular holes {{x1,z1,x2,z2}}
function B.floor(m,x1,z1,x2,z2,y,th,holes,k)
 local bp={x1,x2} for _,h in ipairs(holes or {}) do table.insert(bp,math.clamp(h[1],x1,x2)) table.insert(bp,math.clamp(h[3],x1,x2)) end table.sort(bp)
 for i=1,#bp-1 do local u,v=bp[i],bp[i+1] if v-u>0.05 then local mid=(u+v)/2 local cuts={}
  for _,h in ipairs(holes or {}) do if mid>h[1] and mid<h[3] then table.insert(cuts,{h[2],h[4]}) end end
  table.sort(cuts,function(a,b) return a[1]<b[1] end) local z=z1
  for _,c in ipairs(cuts) do if c[1]>z then P.box(m,"Floor",u,y-th,z,v,y,c[1],k or "s") end z=math.max(z,c[2]) end
  if z<z2 then P.box(m,"Floor",u,y-th,z,v,y,z2,k or "s") end end end
end
-- bridge between two points along axis at deck height y (top), width w
function B.bridge(par,x1,z1,x2,z2,y,w,pillars)
 local m=P.model(par,"Bridge") w=w or 6
 local alongX=math.abs(x2-x1)>math.abs(z2-z1)
 if alongX then local zc=(z1+z2)/2 local a,b=math.min(x1,x2),math.max(x1,x2)
  P.box(m,"BridgeDeck",a,y-1,zc-w/2,b,y,zc+w/2,"t")
  P.box(m,"BridgeBeam",a,y-2.6,zc-w/2-0.2,b,y-1,zc-w/2+0.6,"d") P.box(m,"BridgeBeam",a,y-2.6,zc+w/2-0.6,b,y-1,zc+w/2+0.2,"d")
  P.rail(m,a,zc-w/2+0.2,b,zc-w/2+0.2,y) P.rail(m,a,zc+w/2-0.2,b,zc+w/2-0.2,y)
  if pillars then for x=a+10,b-6,16 do P.pillar(m,x,zc,pillars,y-2.6,1.8,"w") end end
 else local xc=(x1+x2)/2 local a,b=math.min(z1,z2),math.max(z1,z2)
  P.box(m,"BridgeDeck",xc-w/2,y-1,a,xc+w/2,y,b,"t")
  P.box(m,"BridgeBeam",xc-w/2-0.2,y-2.6,a,xc-w/2+0.6,y-1,b,"d") P.box(m,"BridgeBeam",xc+w/2-0.6,y-2.6,a,xc+w/2+0.2,y-1,b,"d")
  P.rail(m,xc-w/2+0.2,a,xc-w/2+0.2,b,y) P.rail(m,xc+w/2-0.2,a,xc+w/2-0.2,b,y)
  if pillars then for z=a+10,b-6,16 do P.pillar(m,xc,z,pillars,y-2.6,1.8,"w") end end
 end
 return m
end
-- wide hazard-edged ramp
function B.ramp(par,x1,z1,y1,x2,z2,y2,w)
 local m=P.model(par,"Ramp")
 local A,Bv=Vector3.new(x1,y1,z1),Vector3.new(x2,y2,z2) local L=(Bv-A).Magnitude local cf=CFrame.lookAt((A+Bv)/2,Bv)
 P.part(m,"RampDeck",Vector3.new(w,1,L+1),cf*CFrame.new(0,-0.5,0),"t")
 for _,s in ipairs({-1,1}) do
  local h=P.part(m,"RampHazard",Vector3.new(0.9,0.08,L),cf*CFrame.new(s*(w/2-0.6),0.02,0),"y") D.flat(h)
  P.part(m,"Barrier",Vector3.new(0.25,3.0,L),cf*CFrame.new(s*(w/2-0.1),1.5,0),"d")
  local cap=P.part(m,"BarrierCap",Vector3.new(0.45,0.5,L),cf*CFrame.new(s*(w/2-0.1),3.25,0),"y") cap.Color=D.ORANGE
  P.part(m,"RampSkirt",Vector3.new(0.6,1.4,L),cf*CFrame.new(s*(w/2+0.2),-1.2,0),"d")
 end
 for t=0.3,0.95,0.32 do local p=A:Lerp(Bv,t) local low=math.min(y1,y2) if p.Y-low>3 then P.box(m,"RampPier",p.X-0.9,low,p.Z-0.9,p.X+0.9,p.Y-1,p.Z+0.9,"w") end end
 return m
end
-- wide stair with solid plaster side walls (no rails). sides: "both","left","right","none" (left/right relative to climb direction)
function B.wideStair(par,x,z,dir,w,y0,y1,sides)
 sides=sides or "both"
 local m=P.stair(par,x,z,dir,w,y0,y1,false)
 local st=par:FindFirstChild("Stair") -- newest stair model is last child named Stair
 local kids=par:GetChildren() for i=#kids,1,-1 do if kids[i].Name=="Stair" then st=kids[i] break end end
 local n=math.max(1,math.ceil((y1-y0)/1.0)) local L=n*1.5
 local sgn=(dir:sub(1,1)=="+") and 1 or -1 local ax=dir:sub(2,2)
 local fwd=ax=="x" and Vector3.new(sgn,0,0) or Vector3.new(0,0,sgn)
 local right=Vector3.new(-fwd.Z,0,fwd.X)
 local A0=Vector3.new(x,y0,z) local B0=A0+fwd*L+Vector3.new(0,y1-y0,0)
 for _,sd in ipairs({-1,1}) do
  local want=(sides=="both") or (sides=="left" and sd==-1) or (sides=="right" and sd==1)
  if want then
   local off=right*sd*(w/2+0.4)
   require(game.ServerStorage.StairCheek:Clone())(st,A0+off,B0+off,Color3.fromRGB(234,235,231),Enum.Material.Plaster,Color3.fromRGB(40,42,46))
  end
 end
 -- step edge stripes
 for _,s in ipairs(st:GetChildren()) do if s.Name=="Step" then s.Color=Color3.fromRGB(150,152,150) s.Material=Enum.Material.Concrete s.MaterialVariant="" end end
 return st,L
end
return B
