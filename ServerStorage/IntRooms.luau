local I=require(game.ServerStorage.IntB:Clone())
local R={}
local RM={IntPanel=1,CeilLight=1,CeilBeam=1,BlueStrip=1,Kit_PipeRun=1,IntFloor=1,Console=1,Screen=1,ScreenFrame=1,BigScreen=1,RoofTruss=1,FloorLine=1,Kit_Cabinet=1}
function R.clean(model) local n=0 for _,c in ipairs(model:GetChildren()) do if RM[c.Name] then c:Destroy() n+=1 end end return n end
function R.face(f) return math.atan2(-f.X,-f.Z) end
-- room: box, height, doors list {side,c1,c2,h}; builds walls with gaps + lintels, floor, ceiling, door frames
function R.room(par,x1,z1,x2,z2,y0,y1,doors,opts)
 opts=opts or {}
 local F=Instance.new("Model") F.Name="IntShell" F.Parent=par
 I.floor(F,x1,z1,x2,z2,y0+0.5,opts.grate or 9)
 local sides={N={a=Vector3.new(x1,0,z1),b=Vector3.new(x2,0,z1),n=Vector3.new(0,0,1),ax="x"},S={a=Vector3.new(x1,0,z2),b=Vector3.new(x2,0,z2),n=Vector3.new(0,0,-1),ax="x"},
  W={a=Vector3.new(x1,0,z1),b=Vector3.new(x1,0,z2),n=Vector3.new(1,0,0),ax="z"},E={a=Vector3.new(x2,0,z1),b=Vector3.new(x2,0,z2),n=Vector3.new(-1,0,0),ax="z"}}
 local seed=0
 for side,s in pairs(sides) do seed+=2
  local ds={} for _,d in ipairs(doors or {}) do if d[1]==side then table.insert(ds,d) end end table.sort(ds,function(p,q) return p[2]<q[2] end)
  local along=function(v) return s.ax=="x" and Vector3.new(v,0,s.a.Z) or Vector3.new(s.a.X,0,v) end
  local cur=s.ax=="x" and s.a.X or s.a.Z local fin=s.ax=="x" and s.b.X or s.b.Z
  for _,d in ipairs(ds) do I.wall(F,along(cur),along(d[2]),y0,y1,s.n,seed) I.wall(F,along(d[2]),along(d[3]),y0+d[4],y1,s.n,seed+1)
   local c=(d[2]+d[3])/2 local cx,cz=s.ax=="x" and c or s.a.X, s.ax=="x" and s.a.Z or c
   if not opts.noDoors then I.door(F,cx,cz,s.ax,d[3]-d[2],d[4],y0,s.n) end cur=d[3] end
  I.wall(F,along(cur),along(fin),y0,y1,s.n,seed+3)
 end
 if not opts.noCeiling then I.ceiling(F,x1,z1,x2,z2,y1,{round=opts.round,noTray=opts.noTray}) end
 return F
end
R.I=I
return R
