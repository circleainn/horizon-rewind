-- Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
-- Execute a complete Grime repaint in one browser task. No third-party JS is
-- patched: the installed renderer's public functions still do the drawing.
local M={}
local kinds={['@dynamic_dirt']='body',['@dynamic_dirt_rough']='rough',
  ['@dynamic_dirt_glass']='glass',['@dynamic_dirt_glass_rough']='glass'}

function M.script(calls,kind,style,encode)
  local code={'(function(){'}
  for _,call in ipairs(calls) do
    assert(call[1]:match('^%a[%w_]*$'),'Invalid canvas method')
    code[#code+1]=call[1]..'('..encode(call[2] or {})..');'
  end
  -- Grime schedules body/glass compositing 60–180 ms later. Its public style
  -- setters also redraw synchronously, including when an older timer is pending.
  -- Restore the same user settings before this single task can be displayed.
  if kind=='body' then
    code[#code+1]='setShade('..encode({shade=style.shade})..');'
  elseif kind=='glass' then
    code[#code+1]='setGlassEffect('..encode({effect=style.glass==0 and 1 or 0})..');'
    code[#code+1]='setGlassEffect('..encode({effect=style.glass})..');'
  end
  code[#code+1]='})();'
  return table.concat(code)
end

function M.paint(html,object,draw,style)
  local original,batches=html.call,{}
  local active=true
  local function collect(tag,method,data)
    if active and kinds[tag] then
      batches[tag]=batches[tag] or {}
      batches[tag][#batches[tag]+1]={method,data}
    else return original(tag,method,data) end
  end
  html.call=collect
  local ok,err=pcall(draw)
  active=false
  if html.call==collect then html.call=original end
  if not ok then error(err) end
  for tag,calls in pairs(batches) do
    local script=M.script(calls,kinds[tag],style,jsonEncode)
    -- Each job is a full snapshot, so the texture can discard obsolete queued
    -- previews and draw only the latest one at its own refresh rate.
    object:queueWebViewStreamJS(tag,'horizonRewindDirt',script)
  end
end
return M
