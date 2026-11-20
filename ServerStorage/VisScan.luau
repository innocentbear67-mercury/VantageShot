return function(step)
 step=step or 14
 local rp=RaycastParams.new()
 local P={}
 for x=-220,220,step do for z=-282,160,step do
  local hit=workspace:Raycast(Vector3.new(x,90,z),Vector3.new(0,-110,0),rp)
  if hit and hit.Instance.CanCollide then local y=hit.Position.Y
   local ok=(y<31 and y>-20) or (y>50 and y<54 and x>118 and x<162 and z>-22 and z<22)
   if ok and not workspace:Raycast(hit.Position+Vector3.new(0,0.5,0),Vector3.new(0,6,0),rp) then table.insert(P,{x=x,z=z,y=y,e=hit.Position+Vector3.new(0,5,0)}) end end end end
 local N=#P local vis,maxd={}, {} for i=1,N do vis[i]=0 maxd[i]=0 end
 local c=0
 for i=1,N do for j=i+1,N do local a,b=P[i].e,P[j].e local d=b-a
  if not workspace:Raycast(a,d,rp) then vis[i]+=1 vis[j]+=1 local m=d.Magnitude if m>maxd[i] then maxd[i]=m end if m>maxd[j] then maxd[j]=m end end
  c+=1 if c%6000==0 then task.wait() end end end
 local out={} local sum,over,long=0,0,0
 for i=1,N do local f=vis[i]/(N-1) sum+=f if f>0.2 then over+=1 end if maxd[i]>200 then long+=1 end
  table.insert(out,string.format("%d,%d,%.0f,%.3f,%.0f",P[i].x,P[i].z,P[i].y,f,maxd[i])) end
 return string.format("N=%d avg=%.1f%% see>20%%: %d (%.0f%%) sightline>200: %d (%.0f%%)",N,sum/N*100,over,over/N*100,long,long/N*100), table.concat(out,";")
end