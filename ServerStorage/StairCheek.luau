-- Solid stair cheek: flat-topped base block + wedge following the slope, vertical ends, sloped cap.
return function(par,A,B,color,mat,capColor,h,thick)
 h=h or 3.4 thick=thick or 0.8
 if A.Y>B.Y then A,B=B,A end
 local flat=Vector3.new(B.X-A.X,0,B.Z-A.Z) local L=flat.Magnitude if L<0.5 then return end
 local d=flat.Unit local R=B.Y-A.Y
 local mid=A+flat/2
 local base=Instance.new("Part") base.Name="StairWall" base.Anchored=true base.Color=color base.Material=mat
 base.Size=Vector3.new(thick,h,L) base.CFrame=CFrame.lookAt(mid+Vector3.new(0,h/2,0),mid+Vector3.new(0,h/2,0)+d) base.Parent=par
 if R>0.2 then
  local w=Instance.new("WedgePart") w.Name="StairWall" w.Anchored=true w.Color=color w.Material=mat
  w.Size=Vector3.new(thick,R,L) local wc=mid+Vector3.new(0,h+R/2,0) w.CFrame=CFrame.lookAt(wc,wc-d) w.Parent=par
 end
 local a=A+Vector3.new(0,h,0) local b=B+Vector3.new(0,h,0) local s=(b-a).Magnitude
 local cap=Instance.new("Part") cap.Name="StairWallCap" cap.Anchored=true cap.Color=capColor cap.Material=Enum.Material.SmoothPlastic
 cap.Size=Vector3.new(thick+0.3,0.35,s) cap.CFrame=CFrame.lookAt((a+b)/2,b)*CFrame.new(0,0.17,0) cap.Parent=par
 -- small end caps so the flat ends read clean
 for _,e in ipairs({{A,h},{B,h}}) do local p=Instance.new("Part") p.Name="StairWallCap" p.Anchored=true p.Color=capColor p.Material=Enum.Material.SmoothPlastic
  p.Size=Vector3.new(thick+0.3,0.35,0.6) p.CFrame=CFrame.lookAt(e[1]+Vector3.new(0,e[2]+0.17,0),e[1]+Vector3.new(0,e[2]+0.17,0)+d)*CFrame.new(0,0,(e[1]==A) and -0.3 or 0.3) p.Parent=par end
end
