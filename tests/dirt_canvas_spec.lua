local Canvas=assert(loadstring(testDirtCanvasSource))()
local jobs={}
local forwarded=0
local original=function() forwarded=forwarded+1 end
local html={call=original}
local object={queueWebViewStreamJS=function(_,tag,key,script)
  assert(key=='horizonRewindDirt');jobs[tag]=script
end}
local marks={marks={{k=1,u=.5,v=.5,l=.8,w=.4,s=1,bx=1,by=0}}}
Canvas.paint(html,object,function()
  for _,tag in ipairs({'@dynamic_dirt','@dynamic_dirt_rough'}) do
    html.call(tag,'washDirt',{});html.call(tag,'dirt',marks)
  end
  for _,tag in ipairs({'@dynamic_dirt_glass','@dynamic_dirt_glass_rough'}) do
    html.call(tag,'washDirt',{});html.call(tag,'setGlass',{lv=.7,wet=.5,mud=.6,spray=.3})
  end
  html.call('@another_mod','draw',{})
end,{shade=0,glass=1})
assert(html.call==original and forwarded==1,'Canvas routing escaped its scope')
local before=jobs['@dynamic_dirt']
assert(not pcall(Canvas.paint,html,object,function() html.call('@dynamic_dirt','washDirt',{});error('failure') end,{shade=0,glass=1}))
assert(html.call==original and jobs['@dynamic_dirt']==before,'Failed repaint published partial cleanup')
print('DIRT_CANVAS_JOBS '..jsonEncode(jobs))
print('DIRT_CANVAS_SPEC_PASSED: atomic jobs, stream coalescing, forwarding and error cleanup')
